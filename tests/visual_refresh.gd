extends SceneTree
func _initialize() -> void: call_deferred("run")
func city_plan(game,city: Dictionary) -> Array:
	var result: Array = []
	for y in range(-city.radius,city.radius+1):
		for x in range(-city.radius,city.radius+1): result.append(game.CityDesign.cell(city,Vector2i(x,y)))
	return result
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	assert(game.visuals.sheets.buildings.size()==8 and game.visuals.sheets.vehicles.size()==8)
	# All open seams, including shoulders, must match the neighboring straight exactly.
	var ports = [[0,2],[0,1],[0,1,3],[0,1,2,3]]
	for kind in 24:
		var vertical: Image = game.visuals.road_variants[kind].straight.get_image()
		var horizontal = vertical.duplicate()
		horizontal.rotate_90(COUNTERCLOCKWISE)
		for j in 4:
			var frame: Image = game.visuals.road_variants[kind][game.visuals.Connections.SHAPES[j]].get_image()
			for edge in ports[j]:
				for pixel in 64:
					var at = [Vector2i(pixel,0),Vector2i(63,pixel),Vector2i(pixel,63),Vector2i(0,pixel)][edge]
					var other = [Vector2i(pixel,63),Vector2i(0,pixel),Vector2i(pixel,0),Vector2i(63,pixel)][edge]
					var expected = vertical if edge in [0,2] else horizontal
					var actual_pixel = frame.get_pixelv(at)
					var expected_pixel = expected.get_pixelv(other)
					assert((actual_pixel.a==0 and expected_pixel.a==0) or actual_pixel==expected_pixel,"Open road seam differs: "+str(kind)+" "+str(j)+" "+str(edge)+" "+str(pixel))
	for family in ["buildings","vehicles"]:
		var hashes: Dictionary = {}
		for texture in game.visuals.sheets[family]:
			var pixels: Image = texture.get_image()
			assert(pixels.get_size()==Vector2i(64,64))
			assert(pixels.get_pixel(0,0).a==0)
			hashes[hash(pixels.get_data())] = true
		assert(hashes.size()==8,"All eight assets must be distinct")
	game.cities.clear();game.city_cells.clear();game.city_connectors.clear();game.roads.clear();game.road_nodes.clear()
	game.terrain.fill(0)
	var styles: Dictionary = {}
	var layouts: Dictionary = {}
	for i in 4:
		game.add_city(Vector2i(100+i*30,100),"Ciudad "+str(i),4)
		var city = game.cities[i]
		styles[city.design_style] = true
		var plan = city_plan(game,city)
		assert(plan==city_plan(game,city),"Design is deterministic")
		layouts[hash(plan)] = true
	assert(styles.size()==4 and layouts.size()==4)
	var before: Array = []
	for city in game.cities: before.append(city_plan(game,city))
	game.save_path = "res://tests/visual_save.bin"
	game.save_game(false)
	var file = FileAccess.open(game.save_path,FileAccess.READ)
	var data: Dictionary = file.get_var(false)
	file.close()
	game.world_seed = 987654
	game.load_game()
	for i in 4: assert(before[i]==city_plan(game,game.cities[i]))
	# Old saves receive the same stable identities every time they are loaded.
	for city in data.cities:
		city.erase("design_seed");city.erase("design_style")
	file = FileAccess.open(game.save_path,FileAccess.WRITE);file.store_var(data);file.close()
	game.world_seed = 123
	game.load_game()
	for i in 4: assert(before[i]==city_plan(game,game.cities[i]))
	var seed: int = game.cities[0].design_seed
	var style: int = game.cities[0].design_style
	var signature: int = game.CityDesign.signature(game.cities[0])
	game.cities[0].pop=5000
	game.grow_cities()
	assert(game.cities[0].design_seed==seed and game.cities[0].design_style==style)
	assert(game.CityDesign.signature(game.cities[0])!=signature)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	print("PASS: 96 road sprites with exact shared seams, eight distinct cars/buildings, four city designs, deterministic appearance, save persistence, old-save migration and growth identity")
	game.free()
	quit()
