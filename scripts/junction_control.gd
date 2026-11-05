extends RefCounted
## Prioridad y reserva en cruces regulados; los no regulados mantienen riesgo de colisión.
const Settings = preload("res://scripts/world_settings.gd")
var g
var clock = 0.0
var grants: Dictionary = {}
var cooldowns: Dictionary = {}
var topology: Dictionary = {}
var revision = -1

func _init(game) -> void:
	g = game

func reset() -> void:
	clock = 0.0
	grants.clear();cooldowns.clear();topology.clear();revision = -1

func uncontrolled(p: Vector2i) -> bool:
	if g.incidents.roundabout_cells.has(p) or g.is_bridge(p): return false
	if g.incidents.signals.has(p) and g.incidents.signals[p].enabled: return false
	if revision != g.road_revision:
		topology.clear();revision = g.road_revision
	if not topology.has(p):
		topology[p] = g.road_neighbours(p).size() >= 3
	return g.signage.controls_junction(p)

func collision_risk(p: Vector2i) -> bool:
	if not g.roads.has(p) or g.is_bridge(p) or g.incidents.roundabout_cells.has(p): return false
	if g.incidents.signals.has(p) and g.incidents.signals[p].enabled: return false
	if g.signage.controls_junction(p): return false
	if revision != g.road_revision:
		topology.clear();revision = g.road_revision
	if not topology.has(p): topology[p] = g.road_neighbours(p).size() >= 3
	return topology[p]

func approach_sign(car: Dictionary, p: Vector2i) -> String:
	return g.signage.approach_priority(p,(p-g.traffic.position(car)).sign())

func active_light(p: Vector2i) -> bool:
	return g.incidents.signals.has(p) and g.incidents.signals[p].enabled and not g.is_bridge(p)

func has_grant(car: Dictionary, p: Vector2i) -> bool:
	return car.ticket in grants.get(p,[])

func revoke(car: Dictionary, p: Vector2i) -> void:
	if not grants.has(p): return
	grants[p].erase(car.ticket)
	if grants[p].is_empty(): grants.erase(p)

func light_allows(car: Dictionary, p: Vector2i) -> bool:
	# Quien ya ha rebasado la línea con verde termina de entrar aunque cambie la fase.
	return g.incidents.signal_allows(p,p-g.traffic.position(car)) or (has_grant(car,p) and car.t>Settings.JUNCTION_STOP_LINE)

func needs_grant(car: Dictionary, p: Vector2i) -> bool:
	return active_light(p) or (uncontrolled(p) and (topology[p] or approach_sign(car,p) in ["stop","yield"]))

func rank(car: Dictionary, p: Vector2i) -> int:
	match approach_sign(car,p):
		"priority": return 0
		"yield","stop": return 2
	return 1

func target(car: Dictionary) -> Vector2i:
	return Vector2i(car.path[car.step+1]) if car.step+1 < car.path.size() else g.traffic.position(car)

func reset_wait(car: Dictionary) -> void:
	car.erase("yield_target");car.erase("yield_arrived");car.erase("yield_wait")
	car.yielding = false

func limit_progress(car: Dictionary) -> void:
	var p = target(car)
	if car.step+1 >= car.path.size() or not needs_grant(car,p):
		reset_wait(car)
		return
	if car.get("yield_target",p) != p: reset_wait(car)
	if (not light_allows(car,p) or not has_grant(car,p)) and car.t >= Settings.JUNCTION_STOP_LINE:
		car.t = Settings.JUNCTION_STOP_LINE
		car.blocked = true
		car.yielding = true

func movement(car: Dictionary, p: Vector2i) -> Array:
	var at_junction = g.traffic.position(car)==p
	var index: int = car.step if at_junction else car.step+1
	var incoming: Vector2i = g.traffic.incoming_direction(car) if at_junction else (p-g.traffic.position(car)).sign()
	var outgoing = (Vector2i(car.path[index+1])-p).sign() if index+1<car.path.size() else incoming
	return [incoming,outgoing]

func conflicts(a: Dictionary, b: Dictionary, p: Vector2i) -> bool:
	return movements_conflict(movement(a,p),movement(b,p))

func movements_conflict(first: Array, second: Array) -> bool:
	if first[0]==second[0] and first[1]==second[1]: return false
	if first[0]==-second[0] and first[1]==first[0] and second[1]==second[0]: return false
	var first_right: bool = first[0].x*first[1].y-first[0].y*first[1].x>0
	var second_right: bool = second[0].x*second[1].y-second[0].y*second[1].x>0
	if first[0]==-second[0] and ((first_right and second[1]==second[0]) or (second_right and first[1]==first[0])): return false
	return not (first_right and second_right)

func exit_clear(car: Dictionary, p: Vector2i) -> bool:
	var index: int = car.step+2
	if index>=car.path.size(): return true
	var exit = Vector2i(car.path[index])
	if not g.road_open(exit) and not g.services.evacuation_move(p,exit): return false
	# No reservar el cruce si la cola de salida invade la zona de conflicto.
	var outgoing = (exit-p).sign()
	for other in g.traffic.occupants.get(p,[]):
		if other==car or target(other)!=exit: continue
		if other.get("crash_left",0.0)>0 or other.get("blocked",false): return false
	for other in g.traffic.occupants.get(exit,[]):
		if g.traffic.incoming_direction(other)!=outgoing: continue
		if other.get("crash_left",0.0)>0 or other.get("blocked",false): return false
	return true

func clearance_time(car: Dictionary) -> float:
	var next = car.duplicate()
	next.step += 1
	return maxf(0,1-car.t)/maxf(0.001,g.traffic.driving_speed(car))+Settings.JUNCTION_CLEAR_PROGRESS/maxf(0.001,g.traffic.driving_speed(next))+Settings.JUNCTION_HEADWAY

func approaching(candidates: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if candidates.is_empty(): return result
	for car in g.cars:
		if car.get("crash_left",0.0)>0: continue
		var projected = car.duplicate()
		var eta = 0.0
		# Mirar también los tramos anteriores evita que el ceda reserve un hueco
		# que un vehículo con prioridad alcanzará antes de terminar el giro.
		for index in range(car.step+1,mini(car.path.size(),car.step+9)):
			projected.step = index-1
			var start = g.traffic.position(projected)
			var p = Vector2i(car.path[index])
			if not g.road_open(start) or not g.traffic.movement_allowed(projected,start,p): break
			var speed = g.traffic.driving_speed(projected)
			if speed<=0: break
			eta += maxf(0,1-car.t)/speed if index==car.step+1 else 1/speed
			if not candidates.has(p): continue
			if not result.has(p): result[p] = []
			result[p].append({"car":projected.duplicate(),"eta":eta})
	return result

func must_yield(car: Dictionary, p: Vector2i, approaches: Dictionary) -> bool:
	var clear_time = clearance_time(car)
	var current = movement(car,p)
	var current_rank = 1 if active_light(p) else rank(car,p)
	for approach in approaches.get(p,[]):
		var other: Dictionary = approach.car
		if other.ticket==car.ticket or approach.eta>clear_time: continue
		if active_light(p) and not g.incidents.signal_allows(p,p-g.traffic.position(other)): continue
		var other_rank = 1 if active_light(p) else rank(other,p)
		var incoming = movement(other,p)
		var turning_left: bool = current[0].x*current[1].y-current[0].y*current[1].x<0 or current[1]==-current[0]
		var oncoming: bool = current[0]==-incoming[0] and (incoming[1]==incoming[0] or incoming[0].x*incoming[1].y-incoming[0].y*incoming[1].x>0)
		var preferred: bool = other_rank<current_rank or (other_rank==current_rank and turning_left and oncoming)
		if preferred and conflicts(car,other,p) and exit_clear(other,p): return true
	return false

func update(dt: float, previous: Dictionary) -> void:
	clock += dt
	var candidates: Dictionary = {}
	var held: Dictionary = {}
	for car in g.cars:
		var p = target(car)
		if car.get("yield_target",p) != p: reset_wait(car)
		if car.step+1>=car.path.size() or not needs_grant(car,p) or car.get("crash_left",0.0)>0 or not (g.road_open(p) and g.road_open(g.traffic.position(car)) or g.services.evacuation_move(g.traffic.position(car),p)) or not g.traffic.movement_allowed(car,g.traffic.position(car),p) or not light_allows(car,p):
			reset_wait(car)
			continue
		if has_grant(car,p): held[car.ticket] = true
		var sign = "" if active_light(p) else approach_sign(car,p)
		if sign in ["stop","yield"] and car.t < Settings.JUNCTION_STOP_LINE: continue
		if not car.has("yield_target"):
			car.yield_target = p;car.yield_arrived = clock;car.yield_wait = 0.0
		# Solo cuenta el tiempo realmente parado, después de aplicar la distancia de seguridad.
		if previous.get(car.ticket,0.0) >= Settings.JUNCTION_STOP_LINE:
			car.yield_wait += dt
		if sign=="stop" and car.yield_wait < Settings.JUNCTION_STOP_TIME: continue
		if not candidates.has(p): candidates[p] = []
		candidates[p].append(car)
	var approaches = approaching(candidates)
	grants.clear()
	for p in cooldowns.keys():
		cooldowns[p] = cooldowns[p].filter(func(item): return item.until>clock)
		if cooldowns[p].is_empty(): cooldowns.erase(p)
	for p in candidates:
		var group: Array = candidates[p]
		group.sort_custom(func(a,b):
			var a_committed: bool = held.has(a.ticket) and a.t>Settings.JUNCTION_STOP_LINE
			var b_committed: bool = held.has(b.ticket) and b.t>Settings.JUNCTION_STOP_LINE
			if a_committed!=b_committed: return a_committed
			if g.traffic.position(a)==g.traffic.position(b) and a.t!=b.t: return a.t>b.t
			var a_rank = 1 if active_light(p) else rank(a,p)
			var b_rank = 1 if active_light(p) else rank(b,p)
			if a_rank!=b_rank: return a_rank<b_rank
			if held.has(a.ticket)!=held.has(b.ticket): return held.has(a.ticket)
			if a.yield_arrived!=b.yield_arrived: return a.yield_arrived<b.yield_arrived
			return a.ticket<b.ticket)
		var approved: Array = []
		for car in group:
			var committed: bool = held.has(car.ticket) and car.t>Settings.JUNCTION_STOP_LINE
			if not committed and (not exit_clear(car,p) or must_yield(car,p,approaches)): continue
			var occupied = false
			# El margen temporal afecta a movimientos incompatibles. La vía con
			# prioridad no hereda la espera del acceso que tiene STOP o ceda.
			if not committed and (active_light(p) or rank(car,p)>=2):
				for item in cooldowns.get(p,[]):
					if item.movement.is_empty() or movements_conflict(movement(car,p),item.movement): occupied = true;break
			for other in approved:
				if conflicts(car,other,p): occupied = true;break
			for other in g.traffic.occupants.get(p,[]):
				if other.get("crash_left",0.0)>0 or (other.t < Settings.JUNCTION_CLEAR_PROGRESS and conflicts(car,other,p)):
					occupied = true;break
			if occupied: continue
			if not grants.has(p): grants[p] = []
			grants[p].append(car.ticket)
			approved.append(car)
			car.yielding = false

func entered(car: Dictionary, p: Vector2i) -> void:
	if has_grant(car,p):
		revoke(car,p)
		if not cooldowns.has(p): cooldowns[p] = []
		cooldowns[p].append({"until":clock+Settings.JUNCTION_HEADWAY,"movement":movement(car,p)})
	reset_wait(car)

func snapshot() -> Dictionary:
	return {"clock":clock,"cooldowns":cooldowns.duplicate(true),"grants":grants.duplicate(true)}

func restore(data: Dictionary) -> void:
	reset()
	clock = data.get("clock",0.0)
	cooldowns = data.get("cooldowns",{}).duplicate(true)
	grants = data.get("grants",{}).duplicate(true)
	# Guardados anteriores: una sola reserva y un margen global por cruce.
	for p in grants:
		if not grants[p] is Array: grants[p] = [grants[p]]
	for p in cooldowns:
		if not cooldowns[p] is Array: cooldowns[p] = [{"until":cooldowns[p],"movement":[]}]
