extends RefCounted
## Terreno determinista sin borde fijo, con caché de bloques limitada.
const Settings = preload("res://scripts/world_settings.gd")
# Valores históricos para migrar guardados que no incluían su configuración.
const LEGACY_TERRAIN = {"noise_frequency":0.008,"forest_threshold":0.06,"mountain_threshold":0.43,"rock_threshold":-0.48,"river_x_spacing":1400.0,"river_y_spacing":2100.0,"river_x_half_width":3.5,"river_y_half_width":2.5}
var parameters = Settings.TERRAIN.duplicate()
const SIZE = 16384 # Tamaño de los guardados antiguos.
const NO_CELL = Vector2i(-2147483648,-2147483648)
const CHUNK = 32
const MAX_CACHED_CHUNKS = 192
var seed_value = Settings.WORLD_SEED
var noise = FastNoiseLite.new()
var chunks: Dictionary = {}
var lake_basins: Dictionary = {}
var legacy_dry_regions: Dictionary = {}
var overrides: Dictionary = {}
var flat_override = -1
var generation = 0
var render_versions: Dictionary = {}
var map_versions: Dictionary = {}

func reset(seed: int) -> void:
	generation += 1
	render_versions.clear()
	map_versions.clear()
	seed_value = seed
	noise.seed = seed
	parameters = Settings.TERRAIN.duplicate()
	noise.frequency = parameters.noise_frequency
	chunks.clear()
	lake_basins.clear()
	legacy_dry_regions.clear()
	overrides.clear()
	flat_override = -1

func fill(value: int) -> void:
	generation += 1
	render_versions.clear()
	map_versions.clear()
	flat_override = value
	chunks.clear()
	lake_basins.clear()
	legacy_dry_regions.clear()
	overrides.clear()

func set_cell(p: Vector2i, value: int) -> void:
	if overrides.has(p) and overrides[p]==value: return
	overrides[p] = value
	var map_key = Vector2i(floori(p.x/256.0),floori(p.y/256.0))
	map_versions[map_key]=int(map_versions.get(map_key,0))+1
	# La ribera de la casilla vecina también cambia al modificar un río.
	for offset in [Vector2i.ZERO,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
		var q = p+offset
		var key = Vector2i(floori(float(q.x)/CHUNK),floori(float(q.y)/CHUNK))
		render_versions[key] = int(render_versions.get(key,0))+1

func get_cell(p: Vector2i) -> int:
	if overrides.has(p): return overrides[p]
	if flat_override >= 0: return flat_override
	var key = Vector2i(floori(float(p.x)/CHUNK),floori(float(p.y)/CHUNK))
	if not chunks.has(key):
		if chunks.size() >= MAX_CACHED_CHUNKS: chunks.erase(chunks.keys()[0])
		chunks[key] = generate_chunk(key)
	return chunks[key][posmod(p.y, CHUNK) * CHUNK + posmod(p.x, CHUNK)]

func generate_chunk(key: Vector2i) -> PackedByteArray:
	var data = PackedByteArray()
	data.resize(CHUNK * CHUNK)
	for row in CHUNK:
		var y = key.y * CHUNK + row
		var offset_x = 420 + sin(y * 0.003 + seed_value % 7) * 65 + sin(y * 0.011) * 12
		for col in CHUNK:
			var x = key.x * CHUNK + col
			var n = noise.get_noise_2d(x, y)
			var river_x = fposmod(x - offset_x, parameters.river_x_spacing)
			var river_y = fposmod(y - 900 - sin(x * 0.004 + seed_value % 5) * 65, parameters.river_y_spacing)
			var water = minf(river_x, parameters.river_x_spacing - river_x) < parameters.river_x_half_width or minf(river_y, parameters.river_y_spacing - river_y) < parameters.river_y_half_width
			data[row * CHUNK + col] = 1 if water or lake_at(Vector2i(x,y),n) else (3 if n > parameters.mountain_threshold else (2 if n > parameters.forest_threshold else (4 if n < parameters.rock_threshold else 0)))
	return data

func snapshot() -> Dictionary:
	return {"seed":seed_value, "overrides":overrides, "flat":flat_override,"parameters":parameters.duplicate(),"legacy_dry_regions":legacy_dry_regions.duplicate()}

func restore(data: Dictionary) -> void:
	reset(data.seed)
	parameters = LEGACY_TERRAIN.duplicate()
	parameters.merge(data.get("parameters",{}),true)
	noise.frequency = parameters.noise_frequency
	overrides = data.get("overrides", {})
	flat_override = data.get("flat", -1)
	legacy_dry_regions = data.get("legacy_dry_regions",{}).duplicate()

func sample_cell(p: Vector2i) -> int:
	# El mapa consulta puntos sueltos sin generar ni retener bloques de 32×32.
	if overrides.has(p): return overrides[p]
	if flat_override >= 0: return flat_override
	var x = p.x
	var y = p.y
	var n = noise.get_noise_2d(x,y)
	var offset_x = 420 + sin(y*0.003+seed_value%7)*65 + sin(y*0.011)*12
	var river_x = fposmod(x-offset_x,parameters.river_x_spacing)
	var river_y = fposmod(y-900-sin(x*0.004+seed_value%5)*65,parameters.river_y_spacing)
	var water = minf(river_x,parameters.river_x_spacing-river_x)<parameters.river_x_half_width or minf(river_y,parameters.river_y_spacing-river_y)<parameters.river_y_half_width
	return 1 if water or lake_at(p,n) else (3 if n>parameters.mountain_threshold else (2 if n>parameters.forest_threshold else (4 if n< parameters.rock_threshold else 0)))

func lake_basin(key: Vector2i) -> Dictionary:
	if lake_basins.has(key): return lake_basins[key]
	var chance=float(parameters.get("lake_chance",0.0))
	var spacing=float(parameters.get("lake_spacing",360.0))
	var hash_value=posmod(seed_value*48271+key.x*73856093+key.y*19349663,2147483647)
	var basin:Dictionary={}
	if float(hash_value%10000)/10000.0<chance:
		var low=float(parameters.get("lake_min_radius",14.0))
		var high=minf(float(parameters.get("lake_max_radius",48.0)),spacing*.2)
		var radius=lerpf(low,high,float(int(hash_value/101)%1000)/999.0)
		basin={"center":Vector2(key)*spacing+Vector2(.3+float(int(hash_value/17)%1000)/2500.0,.3+float(int(hash_value/31)%1000)/2500.0)*spacing,"radius":Vector2(radius,radius*(.6+float(int(hash_value/67)%1000)/1400.0))}
	if lake_basins.size()>=256: lake_basins.erase(lake_basins.keys()[0])
	lake_basins[key]=basin
	return basin

func enable_frontier_lakes(known_regions: Dictionary) -> void:
	if parameters.has("lake_chance"): return
	legacy_dry_regions=known_regions.duplicate()
	for key in ["lake_spacing","lake_chance","lake_min_radius","lake_max_radius"]: parameters[key]=Settings.TERRAIN[key]
	chunks.clear();lake_basins.clear()

func lake_at(p: Vector2i, terrain_noise: float) -> bool:
	if not legacy_dry_regions.is_empty() and legacy_dry_regions.has(Vector2i(floori(p.x/1024.0),floori(p.y/1024.0))): return false
	if float(parameters.get("lake_chance",0.0))<=0: return false
	var spacing=float(parameters.get("lake_spacing",360.0))
	var key=Vector2i(floori(p.x/spacing),floori(p.y/spacing))
	var basin=lake_basin(key)
	if basin.is_empty(): return false
	var delta=(Vector2(p)-basin.center)/basin.radius
	return delta.length_squared()<1.0+terrain_noise*.22+sin((p.x+p.y)*.13+seed_value%13)*.035
