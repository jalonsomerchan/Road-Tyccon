extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	root.size = Vector2i(1280, 800)
	game.notice_time = 0
	game.show_minimap = true
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/preview.png")
	game.panel = "catalog"
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/catalog.png")
	game.panel = ""
	game.cities[0].pop = 3000
	game.grow_cities()
	game.rebuild_graph()
	game.cursor = game.cities[0].pos
	game.camera = Vector2(game.cursor)
	game.tile = 32
	game.zoom_target = 32
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/city-accesses.png")
	game.panel = "help"
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/help.png")
	game.free()
	quit()
