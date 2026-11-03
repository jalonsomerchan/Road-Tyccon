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
	for kind in [0, 5, 8, 13, 16, 23]:
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
	# Save/reload retains centerline data and can migrate earlier saves.
	game.save_game(false)
	var nodes: Dictionary = game.road_nodes.duplicate(true)
	game.road_nodes.clear()
	game.load_game()
	assert(game.road_nodes == nodes)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	game.road_nodes.clear()
	game.restore_road_nodes()
	assert(not game.road_nodes.is_empty())
	print("PASS: 96 sprites, thin road ports and opaque multilane tiles, rotated curves/T/crosses, all roads in one cell, save/load")
	game.free()
	quit()
func build(game, start: Vector2i, finish: Vector2i) -> void:
	game.anchor = start
	game.cursor = finish
	game.apply_action()
