extends SceneTree
func _initialize() -> void:
	call_deferred("run")

func fixture(with_cities: bool = false):
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.roads.clear()
	game.road_nodes.clear()
	game.cities.clear()
	game.city_cells.clear()
	game.city_connectors.clear()
	game.cars.clear()
	game.traffic.reset()
	game.incidents.reset()
	game.incidents.rules.weather_enabled = false
	game.incidents.rules.abandon_enabled = false
	game.terrain.fill(0)
	game.money = 1000000
	game.kind = 0
	game.tool = 0
	if with_cities:
		game.add_city(Vector2i(100,100),"A",1)
		game.add_city(Vector2i(130,100),"B",1)
	game.rebuild_graph()
	return game

func build(game, a: Vector2i, b: Vector2i) -> void:
	game.anchor = a
	game.cursor = b
	game.apply_road_operation(0)
	for i in 20: game._process(0.1)

func run() -> void:
	var game = fixture(true)
	# Traffic appears on connection and respects the capacity of every physical tile.
	build(game,Vector2i(104,100),Vector2i(126,100))
	for i in 400:
		game._process(0.1)
		for p in game.density:
			if game.roads.has(p): assert(game.density[p] <= game.Catalog.ROADS[game.roads[p].kind].cap)
	assert(game.trips > 0 and not game.cars.is_empty())
	game.cursor = Vector2i(115,100)
	game.anchor = game.NO_CELL
	game.tool = 1
	game.apply_action()
	for i in 1800: game._process(0.1)
	var settled_trips: int = game.trips
	var before_queue: int = game.traffic.queued
	var before_cars: int = game.cars.size()
	for i in 300: game._process(0.1)
	assert(game.trips == settled_trips, "Broken network stops completed journeys")
	assert(game.traffic.queued+game.cars.size() > before_queue+before_cars, "Disconnected cities keep generating cars; queues grow")
	var stuck = 0
	for car in game.cars:
		if car.blocked: stuck += 1
		assert(car.dest in [0,1])
	assert(stuck > 0)
	game.tool = 1
	game.apply_action()
	for i in 500: game._process(0.1)
	assert(game.trips > settled_trips, "Waiting cars resume when their route is restored")
	# Penalty and accident stop duration are exact; hazards add to deterioration risk.
	var p = Vector2i(110,100)
	game.roads[p].hp = 70.0
	assert(is_equal_approx(game.incidents.risk(p),0.05))
	game.incidents.snow[p] = game.elapsed + 120
	game.incidents.fire[p] = game.elapsed + 60
	assert(is_equal_approx(game.incidents.risk(p),0.65))
	game.roads[p].hp = 30.0
	assert(is_equal_approx(game.incidents.risk(p),0.75))
	game.roads[p].hp = 10.0
	assert(is_equal_approx(game.incidents.risk(p),0.9))
	var money: float = game.money
	var probe = {"accident_clock":0.0,"crash_left":0.0}
	var happened = false
	for seed in 30:
		game.rng.seed = seed
		probe.accident_clock = 30.0
		if game.incidents.accident(probe,p,0.0): happened = true; break
	assert(happened and game.money == money - 100)
	assert(probe.crash_left == 15 and game.incidents.accidents == 1)
	assert(game.incidents.accident_losses == 100)
	game.incidents.snow.clear()
	game.incidents.fire.clear()
	# Waiting reduces the reward for the same journey, rather than creating extra income.
	var wallet: float = game.money
	game.traffic.complete({"ideal":10.0,"age":10.0,"dest":1})
	var fast_reward: float = game.money - wallet
	wallet = game.money
	game.traffic.complete({"ideal":10.0,"age":100.0,"dest":1})
	assert(game.money - wallet < fast_reward)
	# Save/load includes vehicles, queues, destinations, accident counters and signals.
	game.cursor = p
	game.install_signal()
	game.signal_index = 0
	game.adjust_signal(1)
	assert(game.incidents.signals[p].ns == 12)
	game.panel = ""
	var vehicle_count: int = game.cars.size()
	var queue_count: int = game.traffic.queued
	var first_dest: int = game.cars[0].dest
	game.save_game(false)
	game.cars.clear()
	game.traffic.reset()
	game.load_game()
	assert(game.cars.size() == vehicle_count and game.traffic.queued == queue_count)
	assert(game.cars[0].dest == first_dest and game.incidents.accidents == 1)
	assert(game.incidents.signals[p].ns == 12)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	game.free()
	# A crashed vehicle remains stationary for the confirmed fifteen simulated seconds.
	game = fixture(true)
	build(game,Vector2i(104,100),Vector2i(126,100))
	assert(not game.cars.is_empty())
	var stopped = game.cars[0]
	game.cars = [stopped]
	game.traffic.pending.clear()
	game.traffic.pending_by_city.clear()
	game.traffic.queued = 0
	stopped.crash_left = 15.0
	stopped.accident_clock = 0.0
	var stop_pos = game.traffic.position(stopped)
	for i in 149:
		game.elapsed += 0.1
		game.update_cars(0.1)
	assert(game.traffic.position(stopped) == stop_pos and stopped.crash_left > 0)
	for i in 3:
		game.elapsed += 0.1
		game.update_cars(0.1)
	assert(stopped.crash_left == 0 and (stopped.t > 0 or game.traffic.position(stopped) != stop_pos))
	game.free()
	# A red light prevents an actual vehicle entering, and switching it off releases it.
	game = fixture(true)
	build(game,Vector2i(104,100),Vector2i(126,100))
	game.cars.clear()
	game.traffic.reset()
	game.cursor = Vector2i(115,100)
	game.install_signal()
	game.incidents.signals[game.cursor].ns = 120.0
	var at = Vector2i(114,100)
	var driver = {"path":game.graph.get_point_path(game.point_id(at),game.point_id(Vector2i(130,100))),"step":0,"t":0.0,"age":0.0,"born":game.elapsed,"origin":0,"dest":1,"color":0,"ideal":10.0,"accident_clock":0.0,"crash_left":0.0,"route_revision":game.road_revision,"blocked":false,"ticket":999}
	game.cars.append(driver)
	for i in 10:
		game.elapsed += 0.1
		game.update_cars(0.1)
	assert(game.traffic.position(driver) == at and driver.t == 0 and driver.blocked)
	game.incidents.signals[game.cursor].enabled = false
	game.elapsed += 0.2
	game.update_cars(0.2)
	assert(driver.t > 0 or game.traffic.position(driver) != at)
	game.free()
	# A 3x3 roundabout has eight one-way road cells and a reserved central island.
	game = fixture()
	game.cursor = Vector2i(200,200)
	game.construction_mode = "roundabout"
	game.apply_action()
	assert(game.incidents.roundabout_cells.size() == 9 and game.roads.size() == 8)
	game.construction_mode = "road"
	for endpoint in [Vector2i(200,198),Vector2i(202,200),Vector2i(200,202),Vector2i(198,200)]:
		build(game,endpoint,endpoint)
	game.rebuild_graph()
	assert(not game.graph.has_point(game.point_id(Vector2i(200,200))))
	var clockwise = game.graph.get_point_path(game.point_id(Vector2i(200,198)),game.point_id(Vector2i(202,200)))
	var reverse = game.graph.get_point_path(game.point_id(Vector2i(202,200)),game.point_id(Vector2i(200,198)))
	assert(clockwise.size() > reverse.size() and reverse.size() > 0, "Roundabout has directed circulation")
	game.cursor = Vector2i(202,200)
	game.install_signal()
	assert(game.incidents.signal_allows(game.cursor,Vector2i.UP))
	assert(not game.incidents.signal_allows(game.cursor,Vector2i.RIGHT))
	game.elapsed += 10.01
	assert(not game.incidents.signal_allows(game.cursor,Vector2i.UP))
	assert(game.incidents.signal_allows(game.cursor,Vector2i.RIGHT))
	game.incidents.signals[game.cursor].enabled = false
	assert(game.incidents.signal_allows(game.cursor,Vector2i.UP) and game.incidents.signal_allows(game.cursor,Vector2i.RIGHT))
	game.free()
	# Environmental overlays coexist, spread gradually and expire.
	game = fixture()
	p = Vector2i(300,300)
	game.incidents.snow_zone(p,2)
	game.incidents.ignite(p)
	assert(game.incidents.fire.has(p) and game.incidents.snow.has(p))
	for i in 6:
		game.elapsed += 1
		game.incidents.update(1)
	assert(game.incidents.fire.size() > 1)
	for i in 125:
		game.elapsed += 1
		game.incidents.update(1)
	assert(game.incidents.fire.is_empty() and game.incidents.snow.is_empty())
	build(game,p,p)
	game.incidents.rules.abandon_enabled = true
	game.roads[p].last_used = game.elapsed - 601
	assert(game.incidents.fade(p) > 0)
	game.roads[p].last_used = game.elapsed - 899
	game.incidents.update(0.1)
	assert(game.roads.has(p))
	game.roads[p].last_used = game.elapsed - 901
	game.incidents.update(0.1)
	assert(not game.roads.has(p))
	game.add_city(Vector2i(400,400),"Protegida",1)
	p = game.cities[0].accesses[0].end
	game.roads[p].last_used = -100000
	game.rebuild_graph()
	game.incidents.update(1)
	assert(game.roads.has(p) and game.incidents.fade(p) == 0)
	game.free()
	print("PASS: hard capacity, persistent disconnection queues, resumed journeys, additive risk, 30s accidents/-100€/15s stop, vehicle/queue save, directed 3x3 roundabouts, configurable lights, coexisting spreading/expiring weather, abandonment and protected access")
	quit()
