extends RefCounted
## Capas estáticas en bloques; solo las vías y los efectos se dibujan cada frame.
const Chunk = preload("res://scripts/terrain_chunk.gd")
const SIDE = 32
const MAX_BLOCKS = 48
var g
var ground_root: Node2D
var props_root: Node2D
var road_layer: Node2D
var blocks: Dictionary = {}
var visible_roads: Array = []
var roads_by_block: Dictionary = {}
var road_stamps: Dictionary = {}
var city_stamps: Dictionary = {}
var road_revision = -1
var clock = 0

class RoadLayer extends Node2D:
	var visuals
	func _draw() -> void:
		visuals.canvas = self
		visuals.draw_roads()
		visuals.canvas = visuals.g

func _init(game) -> void:
	g = game
	ground_root = Node2D.new()
	ground_root.name = "CachedGround"
	ground_root.show_behind_parent = true
	g.add_child(ground_root)
	road_layer = RoadLayer.new()
	road_layer.name = "Roads"
	road_layer.visuals = g.visuals
	road_layer.show_behind_parent = true
	g.add_child(road_layer)
	props_root = Node2D.new()
	props_root.name = "CachedScenery"
	props_root.show_behind_parent = true
	g.add_child(props_root)

static func key_for(p: Vector2i) -> Vector2i:
	return Vector2i(floori(float(p.x)/SIDE),floori(float(p.y)/SIDE))

func index_roads() -> void:
	if road_revision==g.road_revision: return
	road_revision = g.road_revision
	roads_by_block.clear(); road_stamps.clear(); city_stamps.clear()
	for p in g.roads:
		var key = key_for(p)
		if not roads_by_block.has(key): roads_by_block[key] = []
		roads_by_block[key].append(p)
		road_stamps[key] = int(road_stamps.get(key,0))+g.point_id(p)+1
	for p in g.city_cells:
		var key = key_for(p)
		city_stamps[key] = int(city_stamps.get(key,0))+g.point_id(p)+1+g.CityDesign.signature(g.cities[g.city_cells[p]])

func prepare() -> void:
	clock += 1
	index_roads()
	var half = Vector2(660,420)/g.tile
	var low = Vector2i((g.camera-half).floor())
	var high = Vector2i((g.camera+half).ceil())
	var first = key_for(low)
	var last = key_for(high)
	visible_roads.clear()
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var key = Vector2i(x,y)
			if not g.explored.contains(key*SIDE): continue
			if not blocks.has(key):
				var ground = Chunk.new()
				ground.game = g; ground.origin = key*SIDE
				ground_root.add_child(ground)
				var props = Chunk.new()
				props.game = g; props.origin = key*SIDE; props.props = true
				props_root.add_child(props)
				blocks[key] = {"ground":ground,"props":props,"used":clock}
			var block = blocks[key]
			block.used = clock
			var base_stamp = [g.terrain.generation,g.terrain.render_versions.get(key,0),city_stamps.get(key,0)]
			var props_stamp = base_stamp+[road_stamps.get(key,0),g.tile<16]
			for node in [block.ground,block.props]:
				if not node.visible: node.visible = true
				node.position = g.screen(Vector2(key*SIDE))-Vector2.ONE*g.tile/2
				node.scale = Vector2.ONE*g.tile/Chunk.CELL
			var ground: Node2D = block.ground
			if ground.stamp != base_stamp:
				ground.stamp = base_stamp
				ground.queue_redraw()
			var props: Node2D = block.props
			if props.stamp != props_stamp:
				props.stamp = props_stamp
				props.sparse = g.tile<16
				props.queue_redraw()
			visible_roads.append_array(roads_by_block.get(key,[]))
	for block in blocks.values():
		if block.used != clock and block.ground.visible:
			block.ground.visible = false
			block.props.visible = false
	while blocks.size()>MAX_BLOCKS:
		var oldest: Variant = null
		var age = clock
		for key in blocks:
			if blocks[key].used < age: oldest = key; age = blocks[key].used
		if oldest==null: break
		blocks[oldest].ground.free()
		blocks[oldest].props.free()
		blocks.erase(oldest)
	road_layer.queue_redraw()

func set_visible(value: bool) -> void:
	ground_root.visible=value
	props_root.visible=value
	road_layer.visible=value
