extends RefCounted
## Descubrir terreno es inmediato; sus poblaciones se incorporan con presupuesto por frame.
const Settings = preload("res://scripts/world_settings.gd")
const BUDGET_USEC = 1500
var g
var jobs: Array = []
var random = RandomNumberGenerator.new()
var completed = 0

func _init(game) -> void: g = game

func reset() -> void:
	jobs.clear();completed = 0

func enqueue(keys: Array) -> void:
	for key in keys: jobs.append(region_job(key))

func region_job(key: Vector2i) -> Dictionary:
	random.seed = g.world_seed+key.x*73856093+key.y*19349663
	return {"key":key,"site":0,"attempt":0,"random":random.state}

func update(budget: int = BUDGET_USEC) -> void:
	if jobs.is_empty() or g.graph_dirty: return
	var deadline = Time.get_ticks_usec()+budget
	while not jobs.is_empty() and Time.get_ticks_usec()<deadline:
		var job = jobs[0]
		if job.site>=Settings.EXPLORATION_CITY_COUNT:
			jobs.pop_front();completed += 1
			continue
		var pos = next_site(job)
		if pos==g.NO_CELL: continue
		g.city_serial += 1
		g.append_streamed_city(pos,"Villa "+str(g.city_serial))

func next_site(job: Dictionary) -> Vector2i:
	random.state = job.random
	# Mantener la parcela dentro de la región que originó el trabajo.
	var margin = Settings.CITY_MAX_RADIUS+5
	var limit = g.Extent.REGION-1-margin
	var pos = job.key*g.Extent.REGION+Vector2i(random.randi_range(margin,limit),random.randi_range(margin,limit))
	job.random = random.state
	var valid = available(pos)
	job.attempt += 1
	if valid or job.attempt>=Settings.EXPLORATION_CITY_ATTEMPTS:
		job.site += 1
		job.attempt = 0
	return pos if valid else g.NO_CELL

func available(pos: Vector2i) -> bool:
	if g.terrain.sample_cell(pos) not in [0,2]: return false
	for city in g.cities:
		if Vector2(pos).distance_squared_to(Vector2(city.pos))<g.MIN_CITY_DISTANCE*g.MIN_CITY_DISTANCE: return false
	# La población se añade como componente aislada: no tocar carreteras ni
	# conectarse por accidente a una vía existente evita reconstruir toda la red.
	var margin = g.CityDesign.initial_radius(pos,g.world_seed)+Settings.CITY_ACCESS_LENGTH+1
	for y in range(-margin,margin+1):
		for x in range(-margin,margin+1):
			if g.roads.has(pos+Vector2i(x,y)): return false
	return true

func snapshot() -> Array:
	return jobs.duplicate(true)

func restore(data: Array) -> void:
	reset();jobs = data.duplicate(true)
