extends RefCounted
## Obras reversibles en el guardado: cobro único al aceptarlas y finalización por tiempo simulado.
const Settings = preload("res://scripts/world_settings.gd")
var g
var jobs: Dictionary = {}
var demolished = 0
var trees_cut = 0

func _init(game) -> void:
	g = game

func reset() -> void:
	jobs.clear()
	demolished = 0
	trees_cut = 0

func demolition(p: Vector2i) -> void:
	var center: Vector2i = g.incidents.roundabout_cells.get(p,p)
	var group: bool = g.incidents.roundabouts.has(center)
	var cells: Array = g.incidents.ring_cells(center) if group else [p]
	if not group and not g.roads.has(p): g.tell("No hay ninguna vía que destruir."); return
	for cell in cells:
		if jobs.has(cell) or g.services.service_jobs.has(cell) or (g.roads.has(cell) and g.roads[cell].work > 0):
			g.tell("Espera a que termine la obra actual."); return
	if jobs.has(center): g.tell("La demolición ya está en marcha."); return
	var cost = 0.0
	for cell in cells:
		if g.roads.has(cell): cost += g.Catalog.ROADS[g.roads[cell].kind].cost * Settings.DEMOLITION_COST_RATIO
	if group: cost += g.Catalog.ROADS[g.incidents.roundabouts[center].kind].cost * Settings.DEMOLITION_COST_RATIO
	if g.money < cost: g.tell("Fondos insuficientes: " + g.cash(cost)); return
	g.services.invalidate_undo(cells)
	g.transact(-cost,"demolition","Demolición de rotonda" if group else "Demolición de carretera")
	for cell in cells:
		if g.roads.has(cell):
			g.roads[cell].closed = true
			g.roads[cell].work = Settings.DEMOLITION_TIME
			g.roads[cell].total = Settings.DEMOLITION_TIME
			g.roads[cell].demolishing = true
	jobs[center] = {"type":"demolition","cells":cells,"left":Settings.DEMOLITION_TIME,"total":Settings.DEMOLITION_TIME}
	g.graph_dirty = true
	g.tell("Demolición · %.1f s · " % Settings.DEMOLITION_TIME + g.accounts.format_money(cost) + " · Los coches afectados esperarán")

func logging(p: Vector2i) -> void:
	if jobs.has(p): g.tell("Ya hay una obra en esta casilla."); return
	if not g.inside(p) or g.ground(p) != 2 or g.city_at(p) >= 0 or g.roads.has(p) or g.incidents.roundabout_cells.has(p):
		g.tell("Selecciona una casilla con árboles."); return
	if g.money < Settings.LOGGING_COST: g.tell("La tala cuesta " + g.cash(Settings.LOGGING_COST)); return
	g.transact(-Settings.LOGGING_COST,"logging","Tala de árboles")
	jobs[p] = {"type":"logging","cells":[p],"left":Settings.LOGGING_TIME,"total":Settings.LOGGING_TIME}
	g.tell("Tala de árboles · %.1f s · " % Settings.LOGGING_TIME + g.cash(Settings.LOGGING_COST))

func update(dt: float) -> void:
	if dt <= 0: return
	for p in jobs.keys():
		var job = jobs[p]
		job.left = maxf(0,job.left-dt)
		if job.left > 0: continue
		if job.type == "logging":
			g.terrain.set_cell(p,0)
			g.navigator.changed()
			trees_cut += 1
		else:
			for cell in job.cells:
				if g.incidents.protected_access(cell): g.demolished_access_tiles[cell] = true
			g.incidents.erase_road(p,true)
			demolished += job.cells.size()
		jobs.erase(p)

func snapshot() -> Dictionary:
	return {"jobs":jobs,"demolished":demolished,"trees_cut":trees_cut}

func restore(data: Dictionary) -> void:
	reset()
	jobs = data.get("jobs",{})
	demolished = data.get("demolished",0)
	trees_cut = data.get("trees_cut",0)
