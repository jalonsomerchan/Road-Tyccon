extends SceneTree
const Connections = preload("res://scripts/road_connections.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	# Every rotated canonical topology is recovered from its neighbor mask.
	for base in [3, 11, 15, 5]:
		for turns in 4:
			var mask = Connections.rotate_mask(base, turns)
			var result = Connections.shape_for(mask)
			var canonical = {"curve":3, "tee":11, "cross":15, "straight":5}[result.shape]
			assert(Connections.rotate_mask(canonical, result.turns) == mask)
	var loaded = 0
	for variants in game.visuals.road_variants:
		for shape in Connections.SHAPES:
			var texture = variants[shape]
			assert(texture != null, "Each road type has all four generated sprites")
			var image = texture.get_image()
			assert(image.get_width() == 64 and image.get_height() == 64)
			var mask = 0
			for edge in 4:
				var count = 0
				for pixel in 64:
					var p = [Vector2i(pixel, 0), Vector2i(63, pixel), Vector2i(pixel, 63), Vector2i(0, pixel)][edge]
					if image.get_pixelv(p).a > 0.5: count += 1
				if count > 4: mask |= 1 << edge
			if game.Catalog.ROADS[loaded / 4].lanes == 1:
				assert(mask == {"straight":5, "curve":3, "tee":11, "cross":15}[shape], "Thin sprite ports match topology")
			else:
				for y in 64:
					for x in 64: assert(image.get_pixel(x,y).a == 1.0, "Multilane pavement fills the cell")
			loaded += 1
	assert(loaded == 96)
	# Occupied lateral cells of wide roads never count as branching centerlines.
	game.cities.clear()
	game.city_connectors.clear()
	game.city_cells.clear()
	game.terrain.fill(0)
	for kind in [0, 5, 8, 16, 23]:
		game.roads.clear()
		game.road_nodes.clear()
		game.kind = kind
		game.money = 1000000
		game.tool = 0
		build(game, Vector2i(100,100), Vector2i(110,100))
		game.rebuild_graph()
		game.visuals.prepare_road_layout()
		assert(game.visuals.node_shapes[Vector2i(105,100)].shape == "straight")
		assert(game.visuals.junctions.is_empty(), "Wide straight roads have no false junctions")
		build(game, Vector2i(110,100), Vector2i(110,110))
		game.rebuild_graph()
		game.visuals.prepare_road_layout()
		assert(game.visuals.node_shapes[Vector2i(110,100)].shape == "curve")
		build(game, Vector2i(110,105), Vector2i(115,105))
		game.rebuild_graph()
		game.visuals.prepare_road_layout()
		assert(game.visuals.node_shapes[Vector2i(110,105)].shape == "tee")
		build(game, Vector2i(105,105), Vector2i(110,105))
		game.rebuild_graph()
		game.visuals.prepare_road_layout()
		assert(game.visuals.node_shapes[Vector2i(110,105)].shape == "cross")
		assert(game.Catalog.ROADS[kind].w == 1)
		assert(game.footprint([Vector2i(110,105)], 1).size() == 1)
	var crossing = Vector2i(120,120)
	for bridge_first in [false,true]:
		game.roads.clear()
		game.road_nodes.clear()
		game.bridge_spans.clear()
		game.kind = 13 if bridge_first else 5
		var direction = Vector2i.UP if bridge_first else Vector2i.LEFT
		build(game,crossing+direction*2,crossing-direction*2)
		game.update_roads(60)
		game.rebuild_graph()
		game.kind = 5 if bridge_first else 13
		direction = Vector2i.LEFT if bridge_first else Vector2i.UP
		var before: float = game.money
		build(game,crossing+direction*2,crossing-direction*2)
		assert(game.money==before-5*game.Catalog.ROADS[game.kind].cost)
		game.rebuild_graph()
		assert(game.services.can_undo())
		game.services.undo_build()
		game.rebuild_graph()
		assert(game.money==before and game.bridge_decks.is_empty())
		build(game,crossing+direction*2,crossing-direction*2)
		game.update_roads(60)
		game.rebuild_graph()
		check_overpass(game,crossing)
	# Save/reload retains centerline data and can migrate earlier saves.
	game.save_game(false)
	var nodes: Dictionary = game.road_nodes.duplicate(true)
	game.road_nodes.clear()
	game.load_game()
	assert(game.road_nodes == nodes)
	check_overpass(game,crossing)
	var file = FileAccess.open(game.save_path,FileAccess.READ)
	var snapshot: Dictionary = file.get_var()
	file.close()
	for old_kind in [5,13]:
		var legacy: Dictionary = snapshot.duplicate(true)
		legacy.erase("bridge_spans")
		legacy.roads[crossing].kind=old_kind
		legacy.roads[crossing].axis=old_kind==5
		legacy.traffic.vehicles=[{"pos":crossing,"next":crossing+Vector2i.DOWN,"t":0.25}]
		file=FileAccess.open(game.save_path,FileAccess.WRITE)
		file.store_var(legacy)
		file.close()
		game.load_game()
		check_overpass(game,crossing)
		assert(game.cars[0].path==PackedVector2Array([Vector2(crossing+Vector2i.UP),Vector2(crossing+Vector2i.DOWN)]))
		assert(is_equal_approx(game.cars[0].t,0.625))
	# The deck survives removal of the road below it and closes independently.
	game.incidents.erase_road(crossing,true)
	game.rebuild_graph()
	assert(game.bridge_decks.has(crossing) and game.edge_allowed(crossing+Vector2i.UP,crossing+Vector2i.DOWN))
	game.incidents.erase_road(crossing+Vector2i.UP,true)
	game.rebuild_graph()
	assert(not game.bridge_decks.has(crossing))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	game.road_nodes.clear()
	game.restore_road_nodes()
	assert(not game.road_nodes.is_empty())
	print("PASS: 96 sprites, road junctions, independent overpass routes in both build orders, undo, save/load and legacy overpass migration")
	game.free()
	quit()
func build(game, start: Vector2i, finish: Vector2i) -> void:
	game.anchor = start
	game.cursor = finish
	game.apply_action()

func check_overpass(game, crossing: Vector2i) -> void:
	var left: int = game.point_id(crossing+Vector2i.LEFT*2)
	var right: int = game.point_id(crossing+Vector2i.RIGHT*2)
	var top: int = game.point_id(crossing+Vector2i.UP*2)
	var bottom: int = game.point_id(crossing+Vector2i.DOWN*2)
	assert(game.roads[crossing].kind==5 and game.bridge_decks.has(crossing))
	assert(game.graph.driving_path(left,right).size()==5)
	assert(game.graph.driving_path(top,bottom).size()==4)
	assert(game.graph.driving_path(top,right).is_empty())
	assert(game.graph.driving_path(left,bottom).is_empty())
	assert(not game.traffic.junctions.uncontrolled(crossing))
	game.visuals.prepare_road_layout()
	assert(game.visuals.node_shapes[crossing]=={"shape":"straight","turns":1})
	game.roads[crossing+Vector2i.UP].closed=true
	game.rebuild_graph()
	assert(game.graph.driving_path(top,bottom).is_empty())
	assert(game.graph.driving_path(left,right).size()==5)
	game.roads[crossing+Vector2i.UP].closed=false
	game.roads[crossing].closed=true
	game.rebuild_graph()
	assert(game.graph.driving_path(left,right).is_empty())
	assert(game.graph.driving_path(top,bottom).size()==4)
	game.roads[crossing].closed=false
	game.rebuild_graph()
