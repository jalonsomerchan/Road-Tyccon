extends SceneTree
var g
func _initialize() -> void: call_deferred("run")

func fixture(mode: String = "free") -> void:
	g.roads.clear(); g.road_nodes.clear(); g.cities.clear(); g.city_cells.clear(); g.city_connectors.clear()
	g.cars.clear(); g.traffic.reset(); g.incidents.reset(); g.maintenance.reset(); g.services.reset()
	g.demolished_access_tiles.clear(); g.terrain.fill(0)
	g.elapsed=0; g.trips=0; g.earned=0; g.demand_clock=0; g.growth_clock=0; g.money=80000
	g.accounts.reset(80000); g.gameplay.reset(mode); g.kind=0; g.tool=0; g.panel=""; g.anchor=g.NO_CELL; g.speed_index=1
	g.add_city(Vector2i(100,100),"Valverde",1); g.add_city(Vector2i(130,100),"Los Olmos",1)
	for city in g.cities: city.profile=0
	g.incidents.rules.weather_enabled=false; g.incidents.rules.abandon_enabled=false
	g.rebuild_graph()

func build(a: Vector2i, b: Vector2i, kind: int = 0) -> void:
	g.kind=kind; g.anchor=a; g.cursor=b; g.apply_road_operation(0)

func run() -> void:
	g=load("res://scenes/main.tscn").instantiate(); root.add_child(g); g.set_process(false)
	g.gameplay.records_path="res://tests/gameplay_scores.bin"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.gameplay.records_path))
	fixture("progression")
	assert(g.gameplay.upkeep_per_minute()==0,"Municipal roads have no player upkeep")
	var funds: float = g.money
	build(Vector2i(200,200),Vector2i(205,200),8)
	assert(g.money==funds and not g.roads.has(Vector2i(200,200)),"Locked road cannot be built")
	build(Vector2i(200,200),Vector2i(205,200))
	assert(g.services.can_undo())
	g.services.undo_build()
	assert(g.money==funds and not g.roads.has(Vector2i(200,200)))
	build(Vector2i(104,100),Vector2i(126,100))
	for i in 25: g._process(0.1)
	assert(g.gameplay.connected_count()==2 and g.cities[0].connected_at>=0)
	funds=g.money; g.gameplay.claim(0)
	assert(g.money==funds+2000 and g.gameplay.reputation==20 and g.gameplay.unlocked(4) and not g.gameplay.unlocked(8))
	funds=g.money;g.gameplay.claim(0)
	assert(g.money==funds,"A claimed milestone cannot pay twice")
	for i in 800: g._process(0.1)
	assert(g.trips>0 and not g.gameplay.routes.is_empty() and not g.gameplay.road_income.is_empty())
	assert(not g.services.can_undo(),"Vehicles invalidate construction undo")
	var route_key: Vector2i = g.gameplay.routes.keys()[0]
	var report: Dictionary = g.gameplay.route_report(route_key)
	assert(report.trips>0 and report.upkeep>0 and report.income>0)
	assert(is_equal_approx(g.money,g.accounts.opening+g.accounts.income()-g.accounts.expenses()))
	# Contracts award reputation and unlock each road tier.
	g.trips=300;g.gameplay.efficient_trips=300
	g.gameplay.claim(1);g.gameplay.claim(2);g.gameplay.claim(1)
	assert(g.gameplay.tier>=2 and g.gameplay.unlocked(7))
	for i in 5: g.gameplay.claim(2)
	assert(g.gameplay.tier==3 and g.gameplay.unlocked(23))
	# Unconnected cities are stable until they have joined the network.
	fixture();g.elapsed=500
	var population: int = g.cities[0].pop
	g.grow_cities()
	assert(g.cities[0].pop>=population)
	g.cities[0].connected_at=0;population=g.cities[0].pop;g.grow_cities()
	assert(g.cities[0].pop<population)
	# Profiles change demand by time and season, with fractional carry.
	for profile in 4:
		g.cities[0].profile=profile;g.gameplay.demand_credit.clear()
		g.elapsed=120 if profile!=3 else 900
		var peak=0
		for i in 10: peak+=g.gameplay.demand_count(0,2)
		g.gameplay.demand_credit.clear();g.elapsed=360 if profile!=3 else 0
		var quiet=0
		for i in 10: quiet+=g.gameplay.demand_count(0,2)
		if profile==2: assert(peak<quiet or peak==quiet) # tourist peak is tested explicitly below
		elif profile!=1: assert(peak>quiet)
	g.cities[0].profile=2;g.gameplay.demand_credit.clear();g.elapsed=0
	assert(g.gameplay.demand_count(0,10)==16)
	g.cities[0].profile=1;g.gameplay.demand_credit.clear();g.elapsed=0
	assert(g.gameplay.demand_count(0,10)==6)
	g.elapsed=120;assert(g.gameplay.demand_count(0,10)==12)
	# Partial work preserves passage, reduces capacity, charges once, and persists.
	fixture();build(Vector2i(200,200),Vector2i(204,200),3)
	for p in g.services.undo_data.cells: g.roads[p].work=0;g.roads[p].hp=40
	g.cursor=Vector2i(202,200);g.services.select_segment(g.cursor)
	assert(g.services.cells().size()==5)
	var cost: float = g.services.quote(g.services.cells(),true)
	funds=g.money;assert(g.services.repair(g.services.cells(),true))
	assert(is_equal_approx(g.money,funds-cost) and g.road_open(g.cursor))
	assert(g.traffic.capacity(g.cursor)==2 and g.services.speed_factor(g.cursor)<1)
	funds=g.money;assert(not g.services.repair(g.services.cells(),true) and g.money==funds)
	g.services.update(3)
	g.save_path="res://tests/gameplay_save.bin";g.save_game(false)
	var remaining: float = g.services.service_jobs[g.cursor].left
	g.services.reset();g.gameplay.reset();assert(g.load_game())
	assert(g.services.service_jobs[g.cursor].left==remaining)
	g.services.update(30)
	assert(g.services.service_jobs.is_empty() and g.roads[g.cursor].hp==100 and g.road_open(g.cursor))
	g.roads[g.cursor].hp=35
	assert(g.services.repair([g.cursor],false) and not g.road_open(g.cursor))
	g.services.update(30);assert(g.road_open(g.cursor))
	# Automated maintenance ignores untouched municipal streets.
	g.roads[g.cursor].hp=30;g.services.auto_enabled=true;g.services.update(10.1)
	assert(g.services.service_jobs.has(g.cursor))
	g.services.update(30)
	# Reserve protection survives abandonment, with a transparent upkeep premium.
	g.services.reserve();g.incidents.rules.abandon_enabled=true
	g.roads[g.cursor].last_used=-10000
	assert(g.incidents.fade(g.cursor)==0 and g.roads[g.cursor].reserve)
	g.incidents.update(.1);assert(g.roads.has(g.cursor))
	# Temporary routes wait until cars leave before removal.
	fixture();g.services.detour_armed=true;build(Vector2i(200,200),Vector2i(202,200))
	assert(g.services.detours.size()==1 and g.roads[g.cursor].reserve)
	var fake={"path":PackedVector2Array([Vector2(201,200)]),"step":0,"ticket":100}
	g.cars=[fake];g.elapsed=301;g.services.update(.1);assert(g.roads.has(Vector2i(201,200)))
	g.cars.clear();g.services.update(.1);assert(not g.roads.has(Vector2i(201,200)))
	# Services clear both active effects and extinguished fire spread sources.
	fixture();g.cursor=Vector2i(110,100)
	g.incidents.ignite(g.cursor);g.incidents.snow_zone(g.cursor,3)
	funds=g.money;g.services.deploy("fire",g.cursor);g.services.deploy("snow",g.cursor)
	assert(g.incidents.fire.is_empty() and g.incidents.snow.is_empty() and g.money==funds-430)
	g.elapsed+=6;g.incidents.update(6);assert(g.incidents.fire.is_empty())
	funds=g.money;g.services.deploy("fire",g.cursor);assert(g.money==funds)
	# Roundabout undo also restores an original road on the centre cell.
	fixture();build(Vector2i(199,200),Vector2i(201,200))
	for p in g.services.undo_data.cells: g.roads[p].work=0;g.roads[p].closed=true
	g.cursor=Vector2i(200,200);g.build_roundabout()
	assert(g.incidents.roundabouts.has(g.cursor) and g.services.can_undo())
	g.services.undo_build();assert(not g.incidents.roundabouts.has(g.cursor) and g.roads.has(g.cursor) and g.roads[g.cursor].closed)
	# Before/after reports require both a measurement window and completed trips.
	fixture();g.gameplay.samples=[]
	for i in 5: g.gameplay.samples.append({"at":0,"duration":50.0,"delay":40.0,"fare":10.0})
	g.gameplay.begin_review("Semáforo");g.elapsed=61;g.gameplay.finish_review();assert(g.gameplay.improvements.is_empty())
	g.trips=5;g.gameplay.samples=[]
	for i in 5: g.gameplay.samples.append({"at":61,"duration":20.0,"delay":10.0,"fare":10.0})
	g.gameplay.finish_review()
	assert(g.gameplay.improvements[0].after.delay<g.gameplay.improvements[0].before.delay)
	# Legacy saves migrate to free mode with profiles, without resetting the ledger.
	g.save_game(false)
	var file=FileAccess.open(g.save_path,FileAccess.READ);var data=file.get_var(false);file.close()
	data.erase("gameplay");data.erase("services")
	for city in data.cities: city.erase("profile");city.erase("connected_at")
	file=FileAccess.open(g.save_path,FileAccess.WRITE);file.store_var(data);file.close()
	assert(g.load_game() and g.gameplay.mode=="free" and g.cities[0].has("profile"))
	# Scenario seeds, deadline, results, cheat exclusion, records and replay.
	g.selected_mode="scenario";g.selected_scenario="budget";g.start_new_session()
	var first_positions: Array = []
	for city in g.cities: first_positions.append(city.pos)
	assert(g.money==12000 and g.accounts.opening==12000 and g.world_seed==42193)
	g.start_new_session()
	for i in g.cities.size(): assert(g.cities[i].pos==first_positions[i])
	g.trips=121;g._process(901)
	assert(g.elapsed==900 and g.gameplay.scenario_done and g.gameplay.scenario_result.success and g.speed_index==0)
	var saved_scores=g.gameplay.scores.duplicate(true)
	g.start_new_session();g.cheats.execute("sun");g.trips=1000;g._process(901)
	assert(not g.gameplay.scenario_result.ranked and g.gameplay.scores==saved_scores)
	g.gameplay.scores.clear();g.gameplay.load_scores();assert(g.gameplay.scores==saved_scores)
	g.gameplay_ui.action("play:continue");assert(g.gameplay.mode=="free" and not g.gameplay.scenario_done)
	g.selected_scenario="winter";g.start_new_session()
	assert(g.world_seed==71129 and g.money==30000 and g.incidents.rules.weather_interval==90 and g.gameplay.weather_kind()=="snow")
	g.reset_armed=true;g.new_game()
	assert(g.money==30000 and g.accounts.opening==30000 and g.incidents.rules.weather_interval==90)
	g.save_game(false);assert(g.load_game())
	assert(g.gameplay.scenario_id=="winter" and not g.gameplay.scenario_done and g.incidents.rules.weather_interval==90)
	for path in [g.save_path,g.gameplay.records_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PASS: contracts, every unlock tier, profiles/peaks, connection grace, upkeep and route income, reversible construction/roundabouts, partial/closed/auto maintenance, saved jobs, reserves, safe detours, emergency response, improvement feedback, v2 migration, seeded scenarios, deadlines, scores, cheat exclusion and replay")
	g.free();quit()
