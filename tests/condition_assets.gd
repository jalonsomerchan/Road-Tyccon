extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	var count=0
	for kind in game.visuals.road_conditions:
		assert(kind.size()==9)
		for state in game.incidents.STATES:
			var texture=kind[state]
			assert(texture!=null,"Every road has all nine requested state sprites")
			var size=192 if state=="roundabout" else 64
			assert(texture.get_width()==size and texture.get_height()==size)
			count+=1
	assert(count==216)
	for family in ["fire","snow"]:
		assert(game.visuals.environment[family].size()==4)
		for frame in game.visuals.environment[family]:
			assert(frame!=null and frame.get_width()==64 and frame.get_height()==64)
	game.ui_action("infrastructure")
	assert(game.panel=="infrastructure")
	var pad=InputEventJoypadButton.new()
	pad.pressed=true
	pad.button_index=JOY_BUTTON_DPAD_DOWN
	game._unhandled_input(pad)
	assert(game.infrastructure_index==1)
	pad.button_index=JOY_BUTTON_A
	game._unhandled_input(pad)
	assert(game.construction_mode=="roundabout" and game.panel=="")
	print("PASS: 216 road state sprites, 24 roundabouts at 192x192, 8 snow/fire frames, controller infrastructure selection")
	game.free()
	quit()
