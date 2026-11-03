extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	for seed in [42193,0,1,2,7,19,72,901,12345,99999,245760,999999]:
		game.world_seed = seed
		game.generate_world()
		var a = game.cities[0]
		var b = game.cities[1]
		assert(b.pos-a.pos==Vector2i(game.START_CITY_DISTANCE,0))
		assert(game.cities.size()==game.INITIAL_CITY_COUNT)
		assert(game.explored.bounds.size==Vector2i.ONE*game.WorldSettings.INITIAL_SIDE and game.explored.regions.size()==int(game.WorldSettings.INITIAL_SIDE/game.Extent.REGION)**2)
		for city in game.cities: assert(game.explored.bounds.has_point(city.pos))
		for i in game.cities.size():
			for j in range(i+1,game.cities.size()):
				assert(Vector2(game.cities[i].pos).distance_to(Vector2(game.cities[j].pos))>=game.MIN_CITY_DISTANCE)
		assert(a.accesses[0].dir==Vector2i.RIGHT and b.accesses[0].dir==Vector2i.LEFT)
		for city in [a,b]: assert(Vector2(city.pos).distance_to(Vector2(game.cities[2].pos))>=game.MIN_CITY_DISTANCE)
		for p in game.line_cells(a.accesses[0].end,b.accesses[0].end): assert(game.ground(p) in [0,2],"Starter connection stays on passable terrain")
		assert(game.terrain.chunks.size()<=game.World.MAX_CACHED_CHUNKS)
	var initial_count: int = game.cities.size()
	assert(initial_count==game.INITIAL_CITY_COUNT)
	assert(not game.spawn_city(false),"All city slots are generated at the start")
	game._process(240.0)
	assert(game.cities.size()==initial_count,"Time never spawns additional cities")
	var expected: Array = []
	game.generate_world()
	for city in game.cities: expected.append(city.pos)
	game.generate_world()
	for i in expected.size(): assert(game.cities[i].pos==expected[i],"Initial cities are deterministic for a world seed")
	game.anchor = game.cities[0].accesses[0].end
	game.cursor = game.cities[1].accesses[0].end
	game.apply_action()
	game.incidents.rules.weather_enabled = false
	for i in 600: game._process(0.1)
	assert(game.trips>0 and game.traffic.current_links[0]==[1])
	print("PASS: 12 seeds with nearby aligned starter cities, facing accesses and natural passable route; configured initial cities inside compact region; no timed spawns; deterministic placement; starter road generates trips")
	game.free()
	quit()
