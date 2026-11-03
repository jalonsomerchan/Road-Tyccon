extends RefCounted
## Los viajes no se descartan: esperan, se desvían o quedan en cola hasta recuperar ruta.
const Settings = preload("res://scripts/world_settings.gd")
const MAX_VISIBLE_CARS = Settings.MAX_VISIBLE_CARS
const DEMAND_INTERVAL = Settings.DEMAND_INTERVAL
const FOLLOWING_GAP = 0.76 # Longitud de coche más margen, en casillas de carretera.
var g
var junctions
var occupants: Dictionary = {}
var pending: Dictionary = {}
var history: Dictionary = {}
var queued = 0
var next_ticket = 0
var current_links: Dictionary = {}
var pending_by_city: Dictionary = {}

func _init(game) -> void:
	g = game
	junctions = preload("res://scripts/junction_control.gd").new(g)

func reset() -> void:
	junctions.reset()
	occupants.clear()
	pending.clear()
	history.clear()
	queued = 0
	next_ticket = 0
	current_links.clear()
	pending_by_city.clear()

func refresh_connections() -> void:
	# Componentes fuertemente conexas: el estado actual no usa destinos históricos.
	current_links.clear()
	var newly_connected = false
	var city_ids: Dictionary = {}
	for i in g.cities.size():
		city_ids[g.point_id(g.cities[i].pos)] = i
		current_links[i] = []
		if not g.cities[i].has("unlocked"): g.cities[i].unlocked = []
	var reverse: Dictionary = {}
	var ids = g.graph.get_point_ids()
	for id in ids: reverse[id] = []
	for id in ids:
		for next in g.graph.get_point_connections(id): reverse[next].append(id)
	var seen: Dictionary = {}
	var order: Array = []
	for start in ids:
		if seen.has(start): continue
		var stack: Array = [Vector2i(start,0)]
		while not stack.is_empty():
			var item: Vector2i = stack.pop_back()
			if item.y == 1: order.append(item.x); continue
			if seen.has(item.x): continue
			seen[item.x] = true
			stack.append(Vector2i(item.x,1))
			for next in g.graph.get_point_connections(item.x):
				if not seen.has(next): stack.append(Vector2i(next,0))
	seen.clear()
	order.reverse()
	for start in order:
		if seen.has(start): continue
		var stack: Array = [start]
		var connected: Array = []
		seen[start] = true
		while not stack.is_empty():
			var id: int = stack.pop_back()
			if city_ids.has(id): connected.append(city_ids[id])
			for next in reverse[id]:
				if not seen.has(next): seen[next] = true; stack.append(next)
		for origin in connected:
			for dest in connected:
				if origin == dest: continue
				current_links[origin].append(dest)
				if not dest in g.cities[origin].unlocked:
					g.cities[origin].unlocked.append(dest)
					newly_connected = true
	if newly_connected: g.demand_clock = maxf(g.demand_clock,DEMAND_INTERVAL)

func spawn_demand() -> void:
	for origin in g.cities.size():
		var destinations: Array = g.cities[origin].get("unlocked", [])
		if destinations.is_empty(): continue
		var dest: int = g.gameplay.choose_destination(origin,destinations)
		var count = mini(Settings.DEMAND_MAX_CARS,Settings.DEMAND_BASE_CARS+int(g.cities[origin].pop/Settings.DEMAND_POPULATION_STEP))
		count=g.gameplay.demand_count(origin,count)
		if not g.cities[origin].get("departure_started",false):
			count=maxi(1,count)
			g.cities[origin].departure_started=true
		if count<=0: continue
		var key = Vector2i(origin, dest)
		if not pending.has(key): pending[key] = []
		var batches: Array = pending[key]
		batches.append({"born":g.elapsed, "count":count})
		# Fusionar lotes antiguos acota memoria, sin perder coches ni destinos.
		if batches.size() > 512:
			var a = batches.pop_front()
			var b = batches[0]
			b.born = (a.born * a.count + b.born * b.count) / (a.count + b.count)
			b.count += a.count
		queued += count
		pending_by_city[origin] = int(pending_by_city.get(origin,0))+count
	admit()

func position(car: Dictionary) -> Vector2i:
	return Vector2i(car.path[car.step])

func capacity(p: Vector2i) -> int:
	return maxi(1,int(g.Catalog.ROADS[g.roads[p].kind].cap*g.services.capacity_factor(p))) if g.roads.has(p) else MAX_VISIBLE_CARS

func route(start: Vector2i, dest: int, incoming: Vector2i = Vector2i.ZERO) -> PackedVector2Array:
	var key = Vector3i(start.x,start.y,dest) if incoming==Vector2i.ZERO else Vector4i(start.x,start.y,dest,g.graph.direction_index(incoming))
	if not g.route_cache.has(key):
		g.route_cache[key] = g.graph.driving_path(g.point_id(start),g.point_id(g.cities[dest].pos),incoming) if g.graph.has_point(g.point_id(start)) else PackedVector2Array()
	var path: PackedVector2Array = g.route_cache[key]
	if path.size() > 1:
		if history.size() >= 512 and not history.has(key): history.erase(history.keys()[0])
		history[key] = path
	return path

func incoming_direction(car: Dictionary) -> Vector2i:
	if car.step>0: return Vector2i(car.path[car.step]-car.path[car.step-1])
	return car.get("incoming",Vector2i.ZERO)

func curve_factor(car: Dictionary) -> float:
	if car.step+1>=car.path.size(): return 1.0
	var p = position(car)
	var outgoing = Vector2i(car.path[car.step+1])-p
	if g.graph.has_point(g.point_id(p)):
		return g.graph.passage_factor(g.point_id(p),incoming_direction(car),outgoing)
	return g.graph.turn_factor(incoming_direction(car),outgoing)

func driving_speed(car: Dictionary) -> float:
	var p = position(car)
	if not g.roads.has(p): return 0.0
	var road = g.roads[p]
	var spec = g.Catalog.ROADS[road.kind]
	return spec.speed*(0.35+0.65*road.hp/100.0)*g.services.speed_factor(p)*(0.8 if g.gameplay.profile(g.cities[car.origin])==1 else 1.0)*curve_factor(car)

func admit() -> void:
	if g.cars.size() >= MAX_VISIBLE_CARS: return
	for key in pending.keys():
		if g.cars.size() >= MAX_VISIBLE_CARS: break
		var origin: int = key.x
		var dest: int = key.y
		if origin >= g.cities.size() or dest >= g.cities.size(): continue
		var batches: Array = pending[key]
		if batches.is_empty(): pending.erase(key); continue
		for access in g.cities[origin].accesses:
			var start: Vector2i = access.gate
			if not g.road_open(start): continue
			var free = capacity(start) - int(g.density.get(start, 0))
			while free > 0 and not batches.is_empty() and g.cars.size() < MAX_VISIBLE_CARS:
				var batch = batches[0]
				var path = route(start, dest)
				if path.size() < 2: path = history.get(Vector3i(start.x, start.y, dest), PackedVector2Array([Vector2(start)]))
				if path.size() < 2: break
				if not spawn_has_following_gap(start, Vector2i(path[1])): break
				next_ticket += 1
				var ideal = path.size() / Settings.TRIP_REFERENCE_SPEED
				g.cars.append({"path":path, "step":0, "t":0.0, "age":g.elapsed - batch.born, "born":batch.born, "origin":origin, "dest":dest, "color":next_ticket % 8, "sprite_id":next_ticket % 8, "heading":Vector2.UP, "ideal":maxf(1, ideal), "accident_clock":0.0, "crash_left":0.0, "route_revision":g.road_revision, "blocked":false, "ticket":next_ticket})
				batch.count -= 1
				queued -= 1
				pending_by_city[origin] = maxi(0,int(pending_by_city.get(origin,0))-1)
				if batch.count <= 0: batches.pop_front()
				g.density[start] = g.density.get(start, 0) + 1
				free -= 1
		if batches.is_empty(): pending.erase(key)

func update(dt: float) -> void:
	g.density.clear()
	for car in g.cars:
		var p = position(car)
		g.density[p] = g.density.get(p, 0) + 1
		g.incidents.used(p)
	if dt <= 0: return
	var steps = clampi(int(ceil(dt / 0.08)), 1, 64)
	for i in steps: step_traffic(dt / steps)

func step_traffic(dt: float) -> void:
	var ready: Array = []
	var prior_progress: Dictionary = {}
	occupants.clear()
	for car in g.cars:
		prior_progress[car.ticket] = car.t
		var p = position(car)
		if not occupants.has(p): occupants[p] = []
		occupants[p].append(car)
	for car in g.cars:
		var p = position(car)
		if car.step+1<car.path.size():
			var heading = car.path[car.step+1]-car.path[car.step]
			if heading.length_squared()>0: car.heading = heading.normalized()
		car.age = maxf(0, g.elapsed - car.born)
		car.blocked = false
		if car.get("crash_left", 0.0) > 0:
			car.accident_clock += dt
			car.crash_left = maxf(0, car.crash_left - dt)
			car.blocked = true
			continue
		if g.incidents.accident(car, p, dt): car.blocked = true; continue
		if car.get("route_revision", -1) != g.road_revision or car.path.size() < 2:
			var previous_next = Vector2i(car.path[car.step+1]) if car.step+1<car.path.size() else p
			var previous_progress: float = car.t
			car.incoming=incoming_direction(car)
			var replacement = route(p,car.dest,car.incoming)
			if replacement.size() > 1:
				car.path = replacement
				car.step = 0
				car.t = previous_progress if Vector2i(replacement[1])==previous_next else 0.0
			car.route_revision = g.road_revision
		if car.path.size() < 2 or car.step >= car.path.size()-1:
			car.blocked = true
			continue
		if not g.road_open(p): car.blocked = true; continue
		var next = Vector2i(car.path[car.step + 1])
		var allowed = g.road_open(next) and g.edge_allowed(p, next)
		if not allowed or not g.incidents.signal_allows(next,next-p):
			car.blocked = true
			continue
		var v = driving_speed(car)
		car.step_speed=v
		var r = g.roads[p]
		r.hp = maxf(minf(r.hp,Settings.ROAD_MIN_HEALTH),r.hp-dt*Settings.ROAD_TRAFFIC_WEAR)
		car.t = minf(1.999999, car.t + dt * v)
		junctions.limit_progress(car)
	# Agrupar por tramo evita comparar cada coche con todos los demás.
	var segments: Dictionary = {}
	for car in g.cars:
		if car.path.size()<2 or car.step>=car.path.size()-1: continue
		var p = position(car)
		var q = Vector2i(car.path[car.step+1])
		var key = Vector4i(p.x,p.y,q.x,q.y)
		if not segments.has(key): segments[key] = []
		segments[key].append(car)
	for group in segments.values():
		if group.size()<2: continue
		group.sort_custom(func(a,b): return prior_progress[a.ticket]>prior_progress[b.ticket])
		var leader_progress = INF
		var previous = INF
		var tied_progress = INF
		for car in group:
			var before: float = prior_progress[car.ticket]
			if before<previous:
				leader_progress=minf(leader_progress,tied_progress)
				tied_progress=INF;previous=before
			if car.get("crash_left",0.0)<=0 and leader_progress<INF:
				var safe = maxf(0.0,leader_progress-FOLLOWING_GAP)
				if car.t>safe: car.t=safe;car.blocked=true
			tied_progress=minf(tied_progress,car.t)
	junctions.update(dt,prior_progress)
	for car in g.cars:
		if car.t >= 1 and car.step+1 < car.path.size() and car.get("crash_left",0.0)<=0:
			var p = position(car)
			var q = Vector2i(car.path[car.step+1])
			if not g.road_open(p) or not g.road_open(q) or not g.edge_allowed(p,q) or not g.incidents.signal_allows(q,q-p): continue
			if junctions.uncontrolled(q) and junctions.grants.get(q,-1)!=car.ticket: continue
			ready.append({"car":car,"p":position(car),"q":Vector2i(car.path[car.step+1])})
	ready.sort_custom(func(a,b): return a.car.ticket < b.car.ticket)
	var finished: Dictionary = {}
	while not ready.is_empty():
		var changed = false
		# Las salidas liberan plazas para los coches que esperan detrás.
		for move in ready.duplicate():
			if g.density.get(move.q,0) < capacity(move.q) and has_following_gap(move):
				commit_move(move,finished)
				ready.erase(move)
				changed = true
		if changed: continue
		# Intercambios y ciclos se reservan simultáneamente: no hay atasco artificial
		# cuando dos sentidos se cruzan o una rotonda llena puede seguir circulando.
		var outgoing: Dictionary = {}
		for move in ready:
			if not outgoing.has(move.p): outgoing[move.p] = move
		for start in outgoing:
			var seen: Dictionary = {}
			var chain: Array = []
			var p: Vector2i = start
			while outgoing.has(p):
				if seen.has(p):
					var cycle = chain.slice(seen[p])
					for move in cycle: g.density[move.p] = int(g.density.get(move.p,1))-1
					for move in cycle:
						commit_move(move,finished,false)
						ready.erase(move)
					changed = true
					break
				seen[p] = chain.size()
				var move = outgoing[p]
				chain.append(move)
				p = move.q
			if changed: break
		if not changed: break
	for move in ready:
		move.car.blocked = true
		move.car.t = minf(1,move.car.t)
	for i in range(g.cars.size()-1,-1,-1):
		if finished.has(g.cars[i].ticket): g.cars.remove_at(i)
	admit()

func has_following_gap(move: Dictionary) -> bool:
	# Si ya hay un coche entrando en la casilla de destino por el mismo sentido,
	# espera hasta que avance lo suficiente para dejar sitio al siguiente.
	var incoming: Vector2 = Vector2(move.q-move.p).normalized()
	for other in occupants.get(move.q,[]):
		if other == move.car or other.path.size() < 2 or other.step >= other.path.size()-1: continue
		if position(other) != move.q: continue
		var next: Vector2i = Vector2i(other.path[other.step+1])
		var outgoing: Vector2 = Vector2(next-move.q).normalized()
		if incoming.dot(outgoing) > 0.5 and other.t < FOLLOWING_GAP:
			return false
	return true

func spawn_has_following_gap(start: Vector2i, next: Vector2i) -> bool:
	for other in g.cars:
		if other.path.size() < 2 or other.step >= other.path.size()-1: continue
		if position(other) == start and Vector2i(other.path[other.step+1]) == next and other.t < FOLLOWING_GAP:
			return false
	return true

func commit_move(move: Dictionary, finished: Dictionary, release: bool = true) -> void:
	var car = move.car
	if occupants.has(move.p): occupants[move.p].erase(car)
	if not occupants.has(move.q): occupants[move.q] = []
	occupants[move.q].append(car)
	if release: g.density[move.p] = maxi(0,int(g.density.get(move.p,1))-1)
	g.density[move.q] = int(g.density.get(move.q,0))+1
	var remaining_time = maxf(0,car.t-1)/maxf(0.001,car.get("step_speed",driving_speed(car)))
	car.incoming=move.q-move.p
	car.step += 1
	car.t = remaining_time*driving_speed(car)
	car.blocked = false
	junctions.entered(car,move.q)
	junctions.limit_progress(car)
	g.incidents.used(move.q)
	if car.step >= car.path.size()-1 and move.q == g.cities[car.dest].pos:
		complete(car)
		finished[car.ticket] = true
		occupants[move.q].erase(car)
		g.density[move.q] = maxi(0,int(g.density.get(move.q,1))-1)

func complete(car: Dictionary) -> void:
	var distance = maxf(car.ideal * Settings.TRIP_REFERENCE_SPEED, 1)
	var fare = (Settings.TRIP_BASE_FARE + distance * Settings.TRIP_FARE_PER_CELL) * clampf(car.ideal / maxf(1, car.age), Settings.TRIP_MIN_TIME_MULTIPLIER, Settings.TRIP_MAX_TIME_MULTIPLIER)
	fare *= [1.0,1.4,1.25,1.2][g.gameplay.profile(g.cities[car.get("origin",0)])]
	g.transact(fare,"trips","Viaje completado")
	g.gameplay.trip_completed(car,fare)
	g.earned += fare
	g.trips += 1
	g.cities[car.dest].received += 1
	g.cities[car.dest].recent += 1
	g.emit_income(fare, car.dest)

func city_queue(city: int) -> int:
	return int(pending_by_city.get(city,0))

func snapshot() -> Dictionary:
	var vehicles: Array = []
	for car in g.cars:
		var data = car.duplicate()
		data.incoming=incoming_direction(car)
		data.erase("step_speed")
		data.erase("path")
		data.erase("step")
		data.pos = position(car)
		data.next = Vector2i(car.path[mini(car.step+1,car.path.size()-1)])
		vehicles.append(data)
	return {"pending":pending, "queued":queued, "ticket":next_ticket, "vehicles":vehicles,"junctions":junctions.snapshot()}

func restore(data: Dictionary) -> void:
	reset()
	junctions.restore(data.get("junctions",{}))
	pending = data.get("pending", {})
	queued = data.get("queued", 0)
	for key in pending:
		for batch in pending[key]: pending_by_city[key.x] = int(pending_by_city.get(key.x,0))+batch.count
	next_ticket = data.get("ticket", 0)
	g.cars.clear()
	for saved in data.get("vehicles", []):
		var car = saved.duplicate()
		car.sprite_id = int(car.get("sprite_id",car.get("color",0)))%8
		car.heading = car.get("heading",Vector2.UP)
		var start: Vector2i = car.pos
		var next: Vector2i = car.get("next",start)
		# Antes las rutas atravesaban edificios. Migrar esos coches a la calle
		# más cercana de su ciudad sin perder destino, espera ni identidad.
		if g.retired_city_cells.has(start):
			start=g.CityRoads.nearest_street(g,start,g.retired_city_cells[start]);next=start
		var city = g.city_at(start)
		if city>=0 and not g.roads.has(start) and not g.demolished_access_tiles.has(start):
			var nearest = start
			var distance = INF
			for p in g.roads:
				if g.city_at(p)!=city: continue
				var candidate = Vector2(p).distance_squared_to(Vector2(start))
				if candidate<distance: nearest=p; distance=candidate
			start=nearest; next=nearest
		if start!=car.pos: car.incoming=Vector2i.ZERO
		car.path = PackedVector2Array([Vector2(start),Vector2(next)]) if start!=next else PackedVector2Array([Vector2(start)])
		car.step = 0
		car.t = clampf(car.get("t",0.0),0,1) if start!=next else 0.0
		car.erase("next")
		car.route_revision = -1
		car.erase("pos")
		g.cars.append(car)
