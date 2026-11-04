extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	assert(game.explored.bounds.size==Vector2i.ONE*game.WorldSettings.INITIAL_SIDE and game.cities.size() == game.INITIAL_CITY_COUNT)
	for i in game.cities.size():
		assert(not game.cities[i].accesses.is_empty())
		for j in range(i + 1, game.cities.size()):
			var distance = Vector2(game.cities[i].pos).distance_to(Vector2(game.cities[j].pos))
			if i==0 and j==1: assert(distance==game.START_CITY_DISTANCE)
			else: assert(distance>=game.MIN_CITY_DISTANCE)
		for access in game.cities[i].accesses:
			assert(game.roads.has(access.end) and game.road_open(access.gate))
	assert(game.cities[0].accesses[0].dir==Vector2i.RIGHT and game.cities[1].accesses[0].dir==Vector2i.LEFT)
	for p in game.line_cells(game.cities[0].accesses[0].end,game.cities[1].accesses[0].end): assert(game.ground(p) in [0,2])
	assert(game.terrain.chunks.size() <= game.World.MAX_CACHED_CHUNKS)
	# Test terrain determinism without allocating the full map.
	var world = game.World.new()
	world.reset(game.world_seed)
	var far = Vector2i(15000, 14000)
	assert(world.get_cell(far) == game.ground(far))
	assert(world.chunks.size() == 1)
	game.roads.clear()
	game.road_nodes.clear()
	game.cities.clear()
	game.city_cells.clear()
	game.city_connectors.clear()
	game.terrain.fill(0)
	game.add_city(Vector2i(100,100), "Prueba A", 1)
	game.add_city(Vector2i(130,100), "Prueba B", 1)
	game.anchor = game.cities[0].accesses[0].end
	game.cursor = game.cities[1].accesses[0].end
	game.apply_action()
	var funds: float = game.money
	game.rebuild_graph()
	assert(game.graph.get_point_path(game.point_id(Vector2i(100,100)), game.point_id(Vector2i(130,100))).is_empty())
	for i in 300: game._process(0.1)
	assert(game.trips > 0 and game.earned > 0 and game.money > funds)
	# Use a city plan with an actual north street to test its connector.
	game.cities[0].radius=2
	game.cities[0].design_style=0
	game.rebuild_city_lookup()
	game.ensure_city_accesses()
	game.anchor = Vector2i(100,90)
	game.cursor = Vector2i(100,97)
	game.apply_action()
	for i in 20: game._process(0.1)
	assert(game.city_connectors[Vector2i(100,97)]==0 and game.edge_allowed(Vector2i(100,97), Vector2i(100,98)))
	assert(not game.graph.get_point_path(game.point_id(Vector2i(100,90)), game.point_id(Vector2i(100,100))).is_empty())
	game.anchor = game.NO_CELL
	game.cursor = Vector2i(110,100)
	game.roads[game.cursor].hp = 40.0
	game.select_tool(2)
	game.apply_action()
	assert(game.anchor == game.cursor)
	game.apply_action()
	assert(game.services.service_jobs.has(game.cursor) and game.roads[game.cursor].closed)
	for i in 120: game._process(0.1)
	assert(not game.services.service_jobs.has(game.cursor) and not game.roads[game.cursor].closed)
	game.select_tool(1)
	game.apply_action()
	game.kind = 8
	game.upgrade_current()
	assert(game.roads[game.cursor].kind == 8)
	assert(not game.roads.has(game.cursor + Vector2i.UP) and not game.roads.has(game.cursor + Vector2i.DOWN), "Every upgrade stays in one cell")
	for i in 120: game._process(0.1)
	game.tool = 1
	game.apply_action()
	assert(not game.roads[game.cursor].closed)
	game.cursor = Vector2i(200,200)
	game.terrain.set_cell(game.cursor,1)
	game.tool = 0
	game.kind = 16
	game.anchor = Vector2i(200,199)
	funds = game.money
	game.apply_action()
	assert(not game.roads.has(game.cursor) and game.money == funds)
	game.kind = 10
	game.apply_action()
	assert(game.roads.has(game.cursor))
	# Expansion creates more gates without destroying the existing connection.
	game.cities[0].pop = 3000
	game.grow_cities()
	assert(game.cities[0].accesses.size() >= 4)
	game.rebuild_graph()
	assert(not game.graph.get_point_path(game.point_id(Vector2i(100,100)),game.point_id(Vector2i(130,100))).is_empty())
	var old_count: int = game.cities.size()
	game.spawn_city()
	assert(game.cities.size() == old_count + 1)
	for city in game.cities:
		if city == game.cities.back(): continue
		assert(Vector2(city.pos).distance_to(Vector2(game.cities.back().pos)) >= game.MIN_CITY_DISTANCE)
	game.save_game(false)
	funds = game.money
	var count: int = game.roads.size()
	game.money = 0
	game.load_game()
	assert(game.money == funds and game.roads.size() == count and game.cities[0].accesses.size() >= 4)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	for road in game.Catalog.ROADS: assert(road.w == 1 and road.lanes >= 1)
	assert(game.Catalog.ROADS.size() == 24)
	print("PASS: expanding lazy world, distant cities, default gates, gated traffic/income, repair/upgrade in one cell, bridges, growing accesses, distant new cities, v2 save/load, 24 road types")
	game.free()
	quit()
