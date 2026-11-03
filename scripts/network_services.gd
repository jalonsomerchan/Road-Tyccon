extends RefCounted
## Gestión por tramos, servicios meteorológicos, reservas y desvíos temporales.
var g
var selected: Array = []
var auto_enabled = false
var auto_threshold = 55.0
var repair_mode = "partial"
var service_jobs: Dictionary = {}
var auto_clock = 0.0
var undo_data: Dictionary = {}
var detour_armed = false
var detours: Array = []

func _init(game) -> void:
	g = game

func reset() -> void:
	selected.clear()
	service_jobs.clear()
	undo_data.clear()
	detours.clear()
	auto_enabled=false
	auto_threshold=55
	repair_mode="partial"
	auto_clock=0
	detour_armed=false

func neighbours(p: Vector2i) -> Array:
	var result: Array = []
	for direction in g.DIRS:
		if g.roads.has(p+direction): result.append(p+direction)
	return result

func select_segment(start: Vector2i) -> void:
	selected.clear()
	if not g.roads.has(start): g.tell("Sitúa el cursor sobre una carretera para elegir el tramo."); return
	if g.incidents.roundabout_cells.has(start):
		selected=g.incidents.ring_cells(g.incidents.roundabout_cells[start])
		return
	var seen: Dictionary = {}
	var pending: Array = [start]
	while not pending.is_empty() and selected.size()<2048:
		var p: Vector2i = pending.pop_back()
		if seen.has(p): continue
		seen[p]=true
		selected.append(p)
		var next = neighbours(p)
		if p!=start and (next.size()!=2 or g.incidents.roundabout_cells.has(p)): continue
		for q in next:
			if not seen.has(q): pending.append(q)
	g.tell("Tramo seleccionado · %d casillas hasta los cruces"%selected.size())

func cells() -> Array:
	var result: Array = []
	for p in selected:
		if g.roads.has(p):
			if g.incidents.roundabout_cells.has(p):
				for q in g.incidents.ring_cells(g.incidents.roundabout_cells[p]):
					if not q in result: result.append(q)
			elif not p in result: result.append(p)
	return result

func quote(targets: Array, partial: bool) -> float:
	var cost = 0.0
	for p in targets:
		if not g.roads.has(p): continue
		var road = g.roads[p]
		if road.hp>=99.9 or road.work>0 or service_jobs.has(p): continue
		cost+=g.Catalog.ROADS[road.kind].cost*g.WorldSettings.REPAIR_COST_RATIO*(1.5 if partial else 1.0)
	return cost

func repair(targets: Array, partial: bool, automatic: bool = false) -> bool:
	var valid: Array = []
	for p in targets:
		if not g.roads.has(p) or g.maintenance.jobs.has(p): continue
		var road = g.roads[p]
		if road.hp<99.9 and road.work<=0 and not service_jobs.has(p): valid.append(p)
	var cost = quote(valid,partial)
	if valid.is_empty():
		if not automatic: g.tell("No hay casillas deterioradas disponibles en el tramo.")
		return false
	if g.money<cost:
		if not automatic: g.tell("Fondos insuficientes · "+g.cash(cost))
		return false
	g.gameplay.begin_review("Mantenimiento del tramo")
	invalidate_undo(valid)
	g.transact(-cost,"repairs","Mantenimiento %s · %d casillas"%["parcial" if partial else "con cierre",valid.size()])
	for p in valid:
		var road = g.roads[p]
		var time = (g.WorldSettings.REPAIR_BASE_TIME+(100-road.hp)*g.WorldSettings.REPAIR_TIME_PER_DAMAGE)*(2.0 if partial else 1.0)
		service_jobs[p]={"left":time,"total":time,"partial":partial,"closed_before":road.closed}
		if not partial: road.closed=true
		road.last_used=g.elapsed
		road.player_modified=true
	g.graph_dirty=true
	if not automatic: g.tell("Mantenimiento aceptado · "+g.cash(cost)+" · Reapertura automática")
	return true

func capacity_factor(p: Vector2i) -> float:
	return 0.5 if service_jobs.has(p) and service_jobs[p].partial else 1.0

func speed_factor(p: Vector2i) -> float:
	return 0.55 if service_jobs.has(p) and service_jobs[p].partial else 1.0

func reserve() -> void:
	var targets = cells()
	if targets.is_empty(): g.tell("Selecciona primero un tramo."); return
	var enable = false
	for p in targets:
		if not g.roads[p].get("reserve",false): enable=true; break
	invalidate_undo(targets)
	for p in targets:
		g.roads[p].reserve=enable
		g.roads[p].player_modified=true
		g.roads[p].last_used=g.elapsed
	g.tell("Reserva protegida · Conservación +35 %" if enable else "Protección de reserva retirada")

func deploy(kind: String, center: Vector2i) -> void:
	var affected: Array = []
	var incident: Dictionary = g.incidents.fire if kind=="fire" else g.incidents.snow
	for p in incident:
		if Vector2(p).distance_squared_to(Vector2(center))<=144: affected.append(p)
	if affected.is_empty(): g.tell("No hay %s a menos de 12 casillas del cursor."%("fuego" if kind=="fire" else "nieve")); return
	var cost = 250.0 if kind=="fire" else 180.0
	if g.money<cost: g.tell("Fondos insuficientes · "+g.cash(cost)); return
	g.gameplay.begin_review("Intervención de "+("bomberos" if kind=="fire" else "quitanieves"))
	g.transact(-cost,"services","Bomberos" if kind=="fire" else "Quitanieves")
	for p in affected: incident.erase(p)
	if kind=="fire":
		# Quitar también las fuentes extinguidas, para que no vuelvan a propagarse.
		for zone in g.incidents.zones:
			for p in affected: zone.cells.erase(p)
	g.tell("%s · %d casillas despejadas"%["Bomberos" if kind=="fire" else "Quitanieves",affected.size()])

func record_build(targets: Array, before: Dictionary, cost: float, roundabout: Vector2i = Vector2i(2147483647,2147483647)) -> void:
	undo_data={"cells":targets.duplicate(),"before":before,"cost":cost,"at":g.elapsed,"kind":g.kind,"roundabout":roundabout,"used":false}
	if detour_armed:
		for p in targets:
			if g.roads.has(p): g.roads[p].reserve=true
		detours.append({"cells":targets.duplicate(),"expires":g.elapsed+300.0})
		detour_armed=false
		g.tell("Desvío temporal · 5 min · Se retira cuando esté vacío")

func invalidate_undo(targets: Array) -> void:
	if undo_data.is_empty(): return
	for p in targets:
		if p in undo_data.cells: undo_data.clear(); return

func note_used(p: Vector2i) -> void:
	if not undo_data.is_empty() and p in undo_data.cells: undo_data.used=true

func can_undo() -> bool:
	if undo_data.is_empty() or undo_data.used or g.elapsed-undo_data.at>60: return false
	for p in undo_data.cells:
		if p==undo_data.roundabout: continue
		if not g.roads.has(p) or g.roads[p].kind!=undo_data.kind or g.density.get(p,0)>0: return false
		if service_jobs.has(p) or g.maintenance.jobs.has(p) or g.incidents.signals.has(p): return false
	return true

func undo_build() -> void:
	if not can_undo(): g.tell("Solo puedes deshacer durante 60 s y antes del primer uso."); return
	var targets: Array = undo_data.cells.duplicate()
	var center: Vector2i = undo_data.roundabout
	if g.incidents.roundabouts.has(center): g.incidents.erase_road(center,true)
	for p in targets:
		if undo_data.before.has(p):
			g.roads[p]=undo_data.before[p].road
			if undo_data.before[p].has("node"): g.road_nodes[p]=undo_data.before[p].node
		else:
			g.roads.erase(p)
			g.road_nodes.erase(p)
	for detour in detours.duplicate():
		if detour.cells==targets: detours.erase(detour)
	g.transact(undo_data.cost,"refunds","Deshacer construcción sin uso")
	undo_data.clear()
	g.graph_dirty=true
	g.tell("Construcción deshecha · Importe devuelto")

func update(dt: float) -> void:
	if dt<=0: return
	for p in service_jobs.keys():
		if not g.roads.has(p): service_jobs.erase(p); continue
		var job = service_jobs[p]
		job.left=maxf(0,job.left-dt)
		if job.left>0: continue
		g.roads[p].hp=100.0
		g.roads[p].last_used=g.elapsed
		g.roads[p].closed=job.closed_before
		service_jobs.erase(p)
		g.graph_dirty=true
	for detour in detours.duplicate():
		if g.elapsed<detour.expires: continue
		var occupied = false
		for car in g.cars:
			if g.traffic.position(car) in detour.cells: occupied=true; break
		if occupied: continue
		for p in detour.cells:
			if service_jobs.has(p) or g.maintenance.jobs.has(p): occupied=true; break
		if occupied: continue
		for p in detour.cells:
			if g.roads.has(p) and not g.incidents.protected_access(p): g.incidents.erase_road(p,true)
		detours.erase(detour)
		g.tell("Desvío temporal retirado al quedar vacío")
	auto_clock+=dt
	if auto_enabled and auto_clock>=10:
		auto_clock=fmod(auto_clock,10)
		var targets: Array = []
		for p in g.roads:
			var road = g.roads[p]
			if not g.gameplay.is_player_road(p): continue
			if road.hp<auto_threshold and road.work<=0 and not service_jobs.has(p):
				targets.append(p)
				if targets.size()>=32: break
		repair(targets,repair_mode=="partial",true)

func snapshot() -> Dictionary:
	return {"auto_enabled":auto_enabled,"auto_threshold":auto_threshold,"repair_mode":repair_mode,"service_jobs":service_jobs,"auto_clock":auto_clock,"detours":detours,"selected":selected}

func restore(data: Dictionary) -> void:
	reset()
	for key in ["auto_enabled","auto_threshold","repair_mode","service_jobs","auto_clock","detours","selected"]:
		if data.has(key): set(key,data[key])
