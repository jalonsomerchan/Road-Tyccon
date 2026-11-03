extends SceneTree
var game
func _initialize() -> void: call_deferred("run")
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	root.size = Vector2i(1280,800)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game.speed_index = 0
	game.notice_time = 0
	for zoom in [32,8,2,0.5]:
		print("Measuring zoom ",zoom)
		game.tile = zoom
		game.zoom_target = zoom
		for i in 12:
			game.queue_redraw()
			await process_frame
			RenderingServer.force_draw(false)
		var before_rebuilds = 0
		for block in game.visuals.terrain_cache.blocks.values(): before_rebuilds += block.ground.rebuilds+block.props.rebuilds
		var times: Array = []
		for i in 45:
			if "--moving" in OS.get_cmdline_user_args(): game.camera.x += 0.75
			var begin = Time.get_ticks_usec()
			game.queue_redraw()
			await process_frame
			RenderingServer.force_draw(false)
			times.append((Time.get_ticks_usec()-begin)/1000.0)
		var after_rebuilds = 0
		for block in game.visuals.terrain_cache.blocks.values(): after_rebuilds += block.ground.rebuilds+block.props.rebuilds
		print("Cache rebuilds during sample: ",after_rebuilds-before_rebuilds)
		times.sort()
		print("ZOOM %.1f: frame median %.2f ms p95 %.2f ms max %.2f ms; draw calls %d" % [zoom,times[22],times[42],times.back(),Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	game.free()
	quit()
