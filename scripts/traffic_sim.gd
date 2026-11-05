extends RefCounted
## Los viajes no se descartan: esperan, se desvían o quedan en cola hasta recuperar ruta.
const Settings = preload("res://scripts/world_settings.gd")
const MAX_VISIBLE_CARS = Settings.MAX_VISIBLE_CARS
const DEMAND_INTERVAL = Settings.DEMAND_INTERVAL
const FOLLOWING_GAP = 0.76 # Longitud de coche más margen, en casillas de carretera.
var g
var junctions
var occupants: Dictionary = {}
var collision_encounters: Dictionary = {}
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
	collision_encounters.clear()
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
	if g.signage.has_movement_rules:
		for start in city_ids:
			var origin: int = city_ids[start]
			var reachable: Array = g.graph.reachable_cities(start,city_ids)
			current_links[origin] = reachable
			for dest in reachable:
				if dest in g.cities[origin].unlocked: continue
				g.cities[origin].unlocked.append(dest)
				newly_connected = true
		if newly_connected: g.demand_clock = maxf(g.demand_clock,DEMAND_INTERVAL)
		return
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
	if car.step>0: return Vector2i(car.path[car.step]-car.path[car.step-1]).sign()
	return car.get("incoming",Vector2i.ZERO)

func curve_factor(car: Dictionary) -> float:
	if car.step+1>=car.path.size(): return 1.0
	var p = position(car)
	var outgoing = (Vector2i(car.path[car.step+1])-p).sign()
	if g.graph.has_point(g.point_id(p)):
		return g.graph.passage_factor(g.point_id(p),incoming_direction(car),outgoing)
	return g.graph.turn_factor(incoming_direction(car),outgoing)

func driving_speed(car: Dictionary) -> float:
	var p = position(car)
	if not g.roads.has(p): return 0.0
	var road = g.roads[p]
	var spec = g.Catalog.ROADS[road.kind]
	var length = maxf(1,car.path[car.step].distance_to(car.path[mini(car.step+1,car.path.size()-1)]))
	var speed: float = spec.speed*(0.35+0.65*road.hp/100.0)*g.services.speed_factor(p)*(0.8 if g.gameplay.profile(g.cities[car.origin])==1 else 1.0)*curve_factor(car)
	var heading = Vector2i(car.path[mini(car.step+1,car.path.size()-1)]-Vector2(p)).sign()
	return minf(speed,g.signage.speed_at(p,heading))/length

func movement_allowed(car: Dictionary, p: Vector2i, q: Vector2i) -> bool:
	if not g.drive_edge(p,q): return false
	return g.services.evacuating(p) or not g.signage.has_movement_rules or g.graph.allows_turn(g.point_id(p),incoming_direction(car),(q-p).sign())

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
				if path.size() < 2 and not g.signage.has_movement_rules: path = history.get(Vector3i(start.x, start.y, dest), PackedVector2Array([Vector2(start)]))
				if path.size() < 2: break
				if not spawn_has_following_gap(start, Vector2i(path[1])): break
				next_ticket += 1
				var length = 1.0
				for i in range(1,path.size()): length+=path[i-1].distance_to(path[i])
				var ideal = length / Settings.TRIP_REFERENCE_SPEED
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
	var positions: Dictionary = {}
	for car in g.cars:
		var p = position(car)
		positions[car.ticket]=p
		g.density[p] = g.density.get(p, 0) + 1
		g.incidents.used(p)
	for key in collision_encounters.keys():
		var junction = Vector2i(key.x,key.y)
		if not positions.has(key.z) or not positions.has(key.w) or (positions[key.z]-junction).abs().x+(positions[key.z]-junction).abs().y>1 or (positions[key.w]-junction).abs().x+(positions[key.w]-junction).abs().y>1:
			collision_encounters.erase(key)
	if dt <= 0: return
	var steps = clampi(int(ceil(dt / 0.08)), 1, 64)
	for i in steps: step_traffic(dt / steps)

# Si la ruta guardada termina dentro del cierre, buscar una salida transitable.
func find_evacuation_path(car: Dictionary) -> PackedVector2Array:
	var start = position(car)
	var queue: Array = [start]
	var previous: Dictionary = {start:start}
	var index = 0
	while index<queue.size():
		var p: Vector2i = queue[index]
		index+=1
		for q in g.road_neighbours(p):
			if previous.has(q) or not g.services.evacuation_move(p,q) or not g.drive_edge(p,q): continue
			previous[q]=p
			if g.road_open(q):
				var result = PackedVector2Array([Vector2(q)])
				while q!=start:
					q=previous[q]
					result.insert(0,Vector2(q))
				return result
			queue.append(q)
	return PackedVector2Array()

func step_traffic(dt: float) -> void:
	var ready: Array = []
	var prior_progress: Dictionary = {}
	occupants.clear()
	for car in g.cars:
		prior_progress[car.ticket] = car.t
		var p = position(car)
		if not occupants.has(p): occupants[p] = []
		occupants[p].append(car)
	# Reservar antes de avanzar evita frenar o retroceder con verde, también
	# al recuperar coches guardados que ya estaban cerca de entrar.
	junctions.update(0.0,prior_progress)
	for car in g.cars:
		var p = position(car)
		if car.step+1<car.path.size():
			var heading = car.path[car.step+1]-car.path[car.step]
			if heading.length_squared()>0: car.heading = heading.normalized()
		car.age = maxf(0, g.elapsed - car.born)
		car.collision_cooldown = maxf(0.0,car.get("collision_cooldown",0.0)-dt)
		car.blocked = false
		if car.get("crash_left", 0.0) > 0:
			car.accident_clock += dt
			car.crash_left = maxf(0, car.crash_left - dt)
			car.blocked = true
			continue
		if g.incidents.accident(car, p, dt): car.blocked = true; continue
		if not g.services.evacuating(p) and (car.get("route_revision", -1) != g.road_revision or car.path.size() < 2):
			var previous_next = Vector2i(car.path[car.step+1]) if car.step+1<car.path.size() else p
			var previous_progress: float = car.t
			car.incoming=incoming_direction(car)
			var replacement = route(p,car.dest,car.incoming)
			if replacement.size() > 1:
				car.path = replacement
				car.step = 0
				car.t = previous_progress if Vector2i(replacement[1])==previous_next else 0.0
			car.route_revision = g.road_revision
		if g.services.evacuating(p) and (car.path.size()<2 or (g.services.evacuating(Vector2i(car.path[-1])) and Vector2i(car.path[-1])!=g.cities[car.dest].pos)):
			var escape = find_evacuation_path(car)
			if escape.size()>1:
				var old_next = Vector2i(car.path[car.step+1]) if car.step+1<car.path.size() else p
				car.t = car.t if Vector2i(escape[1])==old_next else 0.0
				car.path=escape
				car.step=0
		if car.path.size() < 2 or car.step >= car.path.size()-1:
			car.blocked = true
			continue
		if not g.road_open(p) and not g.services.evacuating(p): car.blocked = true; continue
		var next = Vector2i(car.path[car.step + 1])
		if not (g.road_open(p) and g.road_open(next) or g.services.evacuation_move(p,next)) or not movement_allowed(car,p,next):
			car.blocked = true
			continue
		var v = driving_speed(car)
		car.step_speed=v
		if not junctions.light_allows(car,next) and junctions.has_grant(car,next):
			junctions.revoke(car,next)
		var r = g.roads[p]
		if not r.has("urban_city"):
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
		# La distancia de seguridad continúa al otro lado del límite de casilla,
		# también cuando el coche de delante está esperando un STOP o un rojo.
		var length = maxf(1,Vector2(q-p).length())
		for other in occupants.get(q,[]):
			if other==car or other.step+1>=other.path.size(): continue
			var outgoing = Vector2i(other.path[other.step+1])-q
			if incoming_direction(other)!=(q-p).sign() and outgoing.sign()!=(q-p).sign(): continue
			var ahead = minf(other.t,prior_progress.get(other.ticket,other.t))*maxf(1,Vector2(outgoing).length())
			var safe = maxf(0,1+(ahead-FOLLOWING_GAP)/length)
			if car.t>safe: car.t=safe;car.blocked=true
	for group in segments.values():
		if group.size()<2: continue
		var lead = group[0]
		var gap = FOLLOWING_GAP/maxf(1,lead.path[lead.step].distance_to(lead.path[lead.step+1]))
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
				var safe = maxf(0.0,leader_progress-gap)
				if car.t>safe: car.t=safe;car.blocked=true
			tied_progress=minf(tied_progress,car.t)
	junctions.update(dt,prior_progress)
	for car in g.cars:
		if car.t >= 1 and car.step+1 < car.path.size() and car.get("crash_left",0.0)<=0:
			var p = position(car)
			var q = Vector2i(car.path[car.step+1])
			if not (g.road_open(p) and g.road_open(q) or g.services.evacuation_move(p,q)) or not movement_allowed(car,p,q): continue
			if not junctions.light_allows(car,q): continue
			if junctions.needs_grant(car,q) and not junctions.has_grant(car,q): continue
			ready.append({"car":car,"p":position(car),"q":Vector2i(car.path[car.step+1])})
	resolve_uncontrolled_collisions(ready)
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
	var index: int = move.car.step+2
	var planned_exit: Vector2i = Vector2i(move.car.path[index]) if index<move.car.path.size() else move.q
	var entry_distance = entry_progress(move.car)*maxf(1,Vector2(planned_exit-move.q).length())
	for other in occupants.get(move.q,[]):
		if other == move.car or other.path.size() < 2 or other.step >= other.path.size()-1: continue
		if position(other) != move.q: continue
		var next: Vector2i = Vector2i(other.path[other.step+1])
		var outgoing: Vector2 = Vector2(next-move.q).normalized()
		var same_lane = incoming_direction(other)==(move.q-move.p).sign() or next==planned_exit or incoming.dot(outgoing)>0.5
		if same_lane and other.t*maxf(1,Vector2(next-move.q).length())-entry_distance < FOLLOWING_GAP:
			return false
	return true

func spawn_has_following_gap(start: Vector2i, next: Vector2i) -> bool:
	for other in g.cars:
		if other.path.size() < 2 or other.step >= other.path.size()-1: continue
		if position(other) == start and Vector2i(other.path[other.step+1]) == next and other.t*maxf(1,Vector2(next-start).length()) < FOLLOWING_GAP:
			return false
	return true

# Dos giros a la derecha usan esquinas distintas y no se cruzan.
func turns_right_at(car: Dictionary, junction: Vector2i) -> bool:
	var step: int = car.step
	var at_junction = position(car)==junction
	var index = step if at_junction else step+1
	if index+1>=car.path.size(): return false
	var incoming = incoming_direction(car) if at_junction else (junction-position(car)).sign()
	var outgoing = (Vector2i(car.path[index+1])-junction).sign()
	return incoming.x*outgoing.y-incoming.y*outgoing.x>0

func collision_encounter(a: Dictionary, b: Dictionary, p: Vector2i, exposure: float) -> bool:
	if a.get("collision_cooldown",0.0)>0 or b.get("collision_cooldown",0.0)>0: return false
	if turns_right_at(a,p) and turns_right_at(b,p): return false
	var key = Vector4i(p.x,p.y,mini(a.ticket,b.ticket),maxi(a.ticket,b.ticket))
	if collision_encounters.has(key): return false
	collision_encounters[key]=true
	var speed = (float(a.get("step_speed",driving_speed(a)))+float(b.get("step_speed",driving_speed(b))))*0.5
	var probability = clampf(Settings.JUNCTION_COLLISION_RISK * clampf(speed/4.0,0.5,1.5) * exposure,0.0,1.0)
	return g.rng.randf()<probability

# Se evalúa una vez cada encuentro entre vehículos de ejes perpendiculares.
func resolve_uncontrolled_collisions(ready: Array) -> void:
	var approaches: Dictionary = {}
	for move in ready:
		if junctions.collision_risk(move.q):
			if not approaches.has(move.q): approaches[move.q]=[]
			approaches[move.q].append(move)
	var crashed: Dictionary = {}
	for p in approaches:
		var group: Array = approaches[p]
		for i in group.size():
			var move = group[i]
			if crashed.has(move.car.ticket): continue
			var direction: Vector2i = (p-move.p).sign()
			var other_car: Dictionary = {}
			for j in range(i+1,group.size()):
				var other = group[j]
				if not crashed.has(other.car.ticket) and Vector2(direction).dot(Vector2((p-other.p).sign()))==0 and collision_encounter(move.car,other.car,p,1.0):
					other_car=other.car;break
			if other_car.is_empty():
				for other in occupants.get(p,[]):
					if other.get("crash_left",0.0)>0 or other.t>=Settings.JUNCTION_CLEAR_PROGRESS: continue
					var incoming = incoming_direction(other)
					var exposure = clampf(1.0-other.t/Settings.JUNCTION_CLEAR_PROGRESS,0.0,1.0)
					if incoming!=Vector2i.ZERO and Vector2(direction).dot(Vector2(incoming))==0 and collision_encounter(move.car,other,p,exposure): other_car=other;break
			if other_car.is_empty(): continue
			g.incidents.record_accident([move.car,other_car],p)
			crashed[move.car.ticket]=true;crashed[other_car.ticket]=true
	for move in ready.duplicate():
		if crashed.has(move.car.ticket): ready.erase(move)

func entry_progress(car: Dictionary) -> float:
	var next = car.duplicate()
	next.incoming = (Vector2i(car.path[car.step+1])-position(car)).sign()
	next.step += 1
	return maxf(0,car.t-1)/maxf(0.001,car.get("step_speed",driving_speed(car)))*driving_speed(next)

func commit_move(move: Dictionary, finished: Dictionary, release: bool = true) -> void:
	var car = move.car
	if occupants.has(move.p): occupants[move.p].erase(car)
	if not occupants.has(move.q): occupants[move.q] = []
	occupants[move.q].append(car)
	if release: g.density[move.p] = maxi(0,int(g.density.get(move.p,1))-1)
	g.density[move.q] = int(g.density.get(move.q,0))+1
	var progress = entry_progress(car)
	car.incoming=(move.q-move.p).sign()
	car.step += 1
	car.t = progress
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
		if g.services.evacuating(position(car)):
			data.evacuation_path = car.path.slice(car.step)
		data.erase("path")
		data.erase("step")
		data.pos = position(car)
		data.next = Vector2i(car.path[mini(car.step+1,car.path.size()-1)])
		vehicles.append(data)
	return {"pending":pending, "queued":queued, "ticket":next_ticket, "vehicles":vehicles,"junctions":junctions.snapshot(),"collision_encounters":collision_encounters.duplicate()}

func restore(data: Dictionary, legacy_overpasses: bool = false) -> void:
	reset()
	junctions.restore(data.get("junctions",{}))
	collision_encounters=data.get("collision_encounters",{}).duplicate()
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
		if legacy_overpasses and start!=next and g.bridge_decks.has(start):
			var span: Vector4i = g.bridge_decks[start]
			var direction = (next-start).sign()
			if (span.x!=span.z and direction.y==0) or (span.y!=span.w and direction.x==0):
				var a = Vector2i(span.x,span.y)
				var b = Vector2i(span.z,span.w)
				if direction.x<0 or direction.y<0:
					a = Vector2i(span.z,span.w)
					b = Vector2i(span.x,span.y)
				car.t = (Vector2(a).distance_to(Vector2(start))+float(car.get("t",0.0)))/Vector2(a).distance_to(Vector2(b))
				start=a
				next=b
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
		car.path = car.get("evacuation_path",PackedVector2Array()) if start==car.pos else PackedVector2Array()
		if car.path.is_empty(): car.path = PackedVector2Array([Vector2(start),Vector2(next)]) if start!=next else PackedVector2Array([Vector2(start)])
		car.erase("evacuation_path")
		car.step = 0
		car.t = clampf(car.get("t",0.0),0,1) if start!=next else 0.0
		car.erase("next")
		car.route_revision = -1
		car.erase("pos")
		g.cars.append(car)
