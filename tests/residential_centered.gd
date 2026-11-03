extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	var vertical: Image = game.visuals.road_variants[19].straight.get_image()
	var painted = 0
	for y in 64:
		for x in 64: assert(vertical.get_pixel(x,y)==vertical.get_pixel(63-x,y),"Residential road must be centered with symmetric sidewalks")
		for x in range(20,44):
			var color = vertical.get_pixel(x,y)
			if color.r>.82 and color.g>.82 and color.b>.82:
				assert(x in [31,32],"White centerline must lie on the tile midpoint")
				painted+=1
	assert(painted>0)
	for state in game.incidents.STATES:
		var frame: Image = game.visuals.road_conditions[19][state].get_image()
		if state=="roundabout":
			for x in 64:
				assert(frame.get_pixel(64+x,0)==vertical.get_pixel(x,0))
				assert(frame.get_pixel(64+x,191)==vertical.get_pixel(x,63))
		else:
			for y in range(0,6):
				for x in 64:
					assert(frame.get_pixel(x,y)==vertical.get_pixel(x,y),"State changes must preserve the centered road port")
					assert(frame.get_pixel(x,63-y)==vertical.get_pixel(x,63-y))
	assert(game.visuals.sheets.city_streets.size()==16)
	print("PASS: residential road mirror symmetry, midpoint centerline, state and roundabout alignment, city street atlas")
	game.free()
	quit()
