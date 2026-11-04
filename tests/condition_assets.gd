extends SceneTree

func check_roundabout_seam(roundabout: Image, road: Image, side: int, turns: int) -> void:
	roundabout = roundabout.duplicate()
	road = road.duplicate()
	for i in side: roundabout.rotate_90(COUNTERCLOCKWISE)
	for i in posmod(turns-side,4): road.rotate_90(CLOCKWISE)
	for y in 6:
		for x in 64:
			var actual = roundabout.get_pixel(64+x,y)
			var expected = road.get_pixel(x,63-y)
			assert(actual==expected or (actual.a==0 and expected.a==0),"The roundabout must copy the adjoining road profile")
		for x in 64:
			assert(roundabout.get_pixel(x,y).a==0 and roundabout.get_pixel(128+x,y).a==0)

func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	var count=0
	for index in game.visuals.road_conditions.size():
		var kind = game.visuals.road_conditions[index]
		assert(kind.size()==9)
		for state in game.incidents.STATES:
			var texture=kind[state]
			assert(texture!=null,"Every road has all nine requested state sprites")
			var size=192 if state=="roundabout" else 64
			assert(texture.get_width()==size and texture.get_height()==size)
			count+=1
		for side in 4:
			check_roundabout_seam(kind.roundabout.get_image(),game.visuals.road_variants[index].straight.get_image(),side,side%2)
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
	game.roads.clear()
	game.road_nodes.clear()
	game.cities.clear()
	game.city_cells.clear()
	game.terrain.fill(0)
	var center = Vector2i(100,100)
	game.cursor = center
	game.kind = 0
	game.build_roundabout()
	for side in [0,3]:
		var direction: Vector2i = game.visuals.Connections.DIRECTIONS[side]
		var p = center+direction*2
		game.roads[p] = game.city_road(20,side%2==1)
	game.rebuild_graph()
	game.visuals.prepare_road_layout()
	var mixed: Texture2D = game.visuals.roundabout_texture(center,0)
	assert(mixed!=game.visuals.road_conditions[0].roundabout)
	assert(game.visuals.roundabout_texture(center,0)==mixed,"Reusing an approach must reuse its texture")
	for side in [0,3]:
		check_roundabout_seam(mixed.get_image(),game.visuals.road_variants[20].straight.get_image(),side,side%2)
	print("PASS: 216 road state sprites, exact seams on 24 roundabouts and mixed approaches, 8 snow/fire frames, controller infrastructure selection")
	game.free()
	quit()
