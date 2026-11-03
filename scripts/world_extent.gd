extends RefCounted
## Regiones descubiertas persistentes; el terreno de cada región se materializa por bloques de 32.
const REGION = 1024
const INITIAL_SIDE = preload("res://scripts/world_settings.gd").INITIAL_SIDE
const ORIGIN = Vector2i(8192,8192)
var regions: Dictionary = {}
var bounds = Rect2i()
var revision = 0

static func key_for(p: Vector2i) -> Vector2i:
	return Vector2i(floori(float(p.x)/REGION),floori(float(p.y)/REGION))

func reset() -> void:
	assert(INITIAL_SIDE>=REGION and INITIAL_SIDE%REGION==0,"INITIAL_SIDE debe ser múltiplo de 1024 y al menos 1024")
	regions.clear()
	var first = key_for(ORIGIN)-Vector2i.ONE*int(INITIAL_SIDE/REGION/2)
	bounds = Rect2i(first*REGION,Vector2i.ONE*INITIAL_SIDE)
	include_rect(bounds)

func contains(p: Vector2i) -> bool:
	return regions.has(key_for(p))

func include_rect(area: Rect2i) -> Array:
	var added: Array = []
	var first = key_for(area.position)
	var last = key_for(area.end-Vector2i.ONE)
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var key = Vector2i(x,y)
			if regions.has(key): continue
			regions[key] = true
			var block = Rect2i(key*REGION,Vector2i.ONE*REGION)
			bounds = bounds.merge(block) if bounds.has_area() else block
			added.append(key)
	if not added.is_empty(): revision += 1
	return added

func reveal(center: Vector2, half: Vector2) -> Array:
	var low = Vector2i((center-half).floor())
	var high = Vector2i((center+half).ceil())
	return include_rect(Rect2i(low,high-low+Vector2i.ONE))

func snapshot() -> Dictionary:
	return {"regions":regions}

func restore(data: Dictionary) -> void:
	regions = data.get("regions",{}).duplicate()
	bounds = Rect2i()
	for key in regions:
		var area = Rect2i(key*REGION,Vector2i.ONE*REGION)
		bounds = bounds.merge(area) if bounds.has_area() else area
	if regions.is_empty():
		# Guardados anteriores tenían toda la región de 16.384 casillas disponible.
		include_rect(Rect2i(0,0,16384,16384))
	revision += 1
