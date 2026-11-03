extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	root.size = Vector2i(1280,800)
	game.title_has_save = false
	game.queue_redraw()
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/title-new.png")
	assert(game.ui_hits.size()==2)
	game.title_has_save = true
	game.title_index = 1
	game.queue_redraw()
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/title-load.png")
	assert(game.ui_hits.size()==3)
	game.title_action("title:new")
	game.queue_redraw()
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/title-confirm.png")
	assert(game.ui_hits.size()==2)
	game.free()
	quit()
