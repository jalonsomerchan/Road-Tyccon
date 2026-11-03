extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	root.size=Vector2i(1280,800)
	game.cheats.open()
	game.cheats.field.text="moremoney"
	game.cheats.submit("moremoney")
	for i in 3:
		await process_frame
		RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/cheats-console.png")
	assert(game.cheats.cover.get_rect().size==Vector2(1280,800))
	for button in game.cheats.buttons:
		assert(Rect2(Vector2.ZERO,Vector2(1280,800)).encloses(button.get_global_rect()))
	print("PASS: cheat dialog and all controller buttons fit 1280×800")
	game.free()
	quit()
