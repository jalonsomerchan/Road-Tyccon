extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	var counts = {"terrain":5,"props":4,"trees":4,"mountains":3,"scrub":2,
		"roads":24,"buildings":19,"vehicles":8,"city_streets":16}
	for family in game.visuals.sheets:
		var frames: Array = game.visuals.sheets[family]
		var count = 0
		for i in frames.size():
			var frame = frames[i]
			if frame == null: continue
			var side = 32 if family in ["trees","scrub"] or (family=="terrain" and i!=12) else 64
			assert(frame.get_width()==side and frame.get_height()==side)
			count += 1
		assert(count==counts[family],"All active frames load: "+family)
	assert(game.visuals.scenery_atlas.get_width()*game.visuals.scenery_atlas.get_height() <= 512*384)
	var variants = 0
	for road in game.visuals.road_variants:
		for shape in road:
			assert(road[shape] != null)
			variants += 1
	assert(variants == 96)
	assert(game.panel == "", "Panels are hidden initially")
	var key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_PLUS
	var initial: float = game.zoom_target
	game._unhandled_input(key)
	assert(game.zoom_target > initial, "Spanish plus key zooms in")
	key.keycode = KEY_KP_SUBTRACT
	game._unhandled_input(key)
	assert(is_equal_approx(game.zoom_target, initial), "Keypad zooms out")
	key.keycode = KEY_UNKNOWN
	key.physical_keycode = KEY_PAGEUP
	game._unhandled_input(key)
	assert(game.zoom_target > initial, "Page Up fallback")
	var mouse = InputEventMouseButton.new()
	mouse.pressed = true
	mouse.button_index = MOUSE_BUTTON_WHEEL_DOWN
	game._unhandled_input(mouse)
	assert(is_equal_approx(game.zoom_target, initial), "Mouse wheel")
	game.ui_action("zoom_in")
	assert(game.zoom_target > initial, "Visible zoom button")
	var pad = InputEventJoypadButton.new()
	pad.pressed = true
	pad.button_index = JOY_BUTTON_LEFT_STICK
	initial = game.zoom_target
	game._unhandled_input(pad)
	pad.pressed=false;game._unhandled_input(pad);pad.pressed=true
	assert(game.zoom_target == initial and game.speed_index==0, "L3 pauses without changing zoom or opening menus")
	game._unhandled_input(pad)
	pad.pressed=false;game._unhandled_input(pad);pad.pressed=true
	assert(game.speed_index==1 and game.panel=="", "L3 resumes the simulation")
	game.set_zoom(500)
	assert(game.zoom_target == 96)
	game.set_zoom(1)
	assert(game.zoom_target == 1)
	game.set_zoom(64)
	game.speed_index = 0
	for i in 60: game._process(0.016)
	assert(is_equal_approx(game.tile, 64), "Zoom animation reaches target")
	var at: Vector2 = game.screen(Vector2(game.cursor))
	var adjacent: Vector2 = game.screen(Vector2(game.cursor + Vector2i.RIGHT))
	assert(is_equal_approx(adjacent.x - at.x, 64), "Projection follows zoom")
	game.money_popups.clear()
	game.emit_income(37, 0)
	assert(game.money_popups.size() == 1 and game.money_popups[0].amount == 37)
	assert(game.income_pulse == 1)
	game._process(0.5)
	assert(game.money_popups[0].age == 0.5, "Effects animate in real time, even while paused")
	game._process(2.0)
	assert(game.money_popups.is_empty(), "Effects clean up")
	for i in 200: game.emit_income(12, 1)
	assert(game.money_popups.size() <= 96, "Effect count remains bounded")
	game.ui_action("info")
	assert(game.panel == "info")
	game.ui_action("close")
	game.ui_action("map")
	assert(game.panel == "map")
	print("PASS: packed scenery and 96 road variants, compact interface, keyboard/keypad/PageUp/wheel/button/controller zoom, projection, income animation, effect cleanup, on-demand details")
	game.free()
	quit()
