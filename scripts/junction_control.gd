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
	return g.signage.has_priority(p)

func collision_risk(p: Vector2i) -> bool:
	if not g.roads.has(p) or g.is_bridge(p) or g.incidents.roundabout_cells.has(p): return false
	if g.incidents.signals.has(p) and g.incidents.signals[p].enabled: return false
	if g.signage.has_priority(p): return false
	if revision != g.road_revision:
		topology.clear();revision = g.road_revision
	if not topology.has(p): topology[p] = g.road_neighbours(p).size() >= 3
	return topology[p]

func approach_sign(car: Dictionary, p: Vector2i) -> String:
	return g.signage.priority(p,(p-g.traffic.position(car)).sign())

func needs_grant(car: Dictionary, p: Vector2i) -> bool:
	return uncontrolled(p) and (topology[p] or approach_sign(car,p) in ["stop","yield"])

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
	if grants.get(p,-1) != car.ticket and car.t >= Settings.JUNCTION_STOP_LINE:
		car.t = Settings.JUNCTION_STOP_LINE
		car.blocked = true
		car.yielding = true

func update(dt: float, previous: Dictionary) -> void:
	clock += dt
	var candidates: Dictionary = {}
	var holders: Dictionary = {}
	for car in g.cars:
		var p = target(car)
		if car.get("yield_target",p) != p: reset_wait(car)
		if car.step+1>=car.path.size() or not needs_grant(car,p) or car.get("crash_left",0.0)>0 or not (g.road_open(p) and g.road_open(g.traffic.position(car)) or g.services.evacuation_move(g.traffic.position(car),p)) or not g.traffic.movement_allowed(car,g.traffic.position(car),p):
			reset_wait(car)
			continue
		if grants.get(p,-1) == car.ticket: holders[p] = car.ticket
		if car.t < Settings.JUNCTION_STOP_LINE: continue
		if not car.has("yield_target"):
			car.yield_target = p;car.yield_arrived = clock;car.yield_wait = 0.0
		# Solo cuenta el tiempo realmente parado, después de aplicar la distancia de seguridad.
		if previous.get(car.ticket,0.0) >= Settings.JUNCTION_STOP_LINE:
			car.yield_wait += dt
		var sign = approach_sign(car,p)
		var must_stop = sign=="stop"
		if must_stop and car.yield_wait < Settings.JUNCTION_STOP_TIME: continue
		var other = candidates.get(p,{})
		var current_rank = rank(car,p)
		var other_rank = 3 if other.is_empty() else rank(other,p)
		if current_rank<other_rank or (current_rank==other_rank and (car.yield_arrived<other.yield_arrived or (car.yield_arrived==other.yield_arrived and car.ticket<other.ticket))):
			candidates[p] = car
	for p in grants.keys():
		if not holders.has(p): grants.erase(p)
	for p in cooldowns.keys():
		if cooldowns[p] <= clock: cooldowns.erase(p)
	for p in candidates:
		if grants.has(p) or cooldowns.has(p): continue
		var occupied = false
		for other in g.traffic.occupants.get(p,[]):
			# Cruces contiguos: una salida que ya espera en su siguiente stop
			# puede liberarse en el mismo ciclo de movimiento del simulador.
			var leaving = other.get("yield_wait",0.0) >= Settings.JUNCTION_STOP_TIME
			if other.get("crash_left",0.0)>0 or not g.road_open(target(other)) or (other.t < Settings.JUNCTION_CLEAR_PROGRESS and not leaving):
				occupied = true;break
		if not occupied:
			grants[p] = candidates[p].ticket
			candidates[p].yielding = false

func entered(car: Dictionary, p: Vector2i) -> void:
	if grants.get(p,-1) == car.ticket:
		grants.erase(p)
		cooldowns[p] = clock+Settings.JUNCTION_HEADWAY
	reset_wait(car)

func snapshot() -> Dictionary:
	return {"clock":clock,"cooldowns":cooldowns.duplicate(),"grants":grants.duplicate()}

func restore(data: Dictionary) -> void:
	reset()
	clock = data.get("clock",0.0)
	cooldowns = data.get("cooldowns",{}).duplicate()
	grants = data.get("grants",{}).duplicate()
