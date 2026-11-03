extends SceneTree
var g
var center = Vector2i(101,100)
var straight = PackedVector2Array([Vector2(100,100),Vector2(101,100),Vector2(102,100),Vector2(103,100)])

func _initialize() -> void: call_deferred("run")

func fixture(crossing: bool = false) -> void:
	g.roads.clear();g.road_nodes.clear();g.city_cells.clear();g.city_connectors.clear();g.demolished_access_tiles.clear();g.cars.clear()
	g.traffic.reset();g.incidents.reset();g.services.reset();g.maintenance.reset();g.gameplay.reset()
	g.elapsed=0;g.trips=0;g.earned=0;g.terrain.fill(0);g.money=100000
	g.cities=[]
	for i in 2:
		g.cities.append({"pos":Vector2i(straight[0] if i==0 else straight[-1]),"name":"Prueba "+str(i),"pop":1000,"profile":0,"received":0,"recent":0,"accesses":[],"access_dirs":[Vector2i.RIGHT]})
	for cell in straight: add_road(Vector2i(cell))
	if crossing:
		add_road(center+Vector2i.UP);add_road(center+Vector2i.DOWN)
	g.incidents.rules.weather_enabled=false;g.incidents.rules.abandon_enabled=false
	g.incidents.rules.fire_spread=1000.0
	g.rebuild_graph()

func add_road(p: Vector2i) -> void:
	g.roads[p]=g.city_road(3,true);g.road_nodes[p]={"kind":3,"axis":true}

func driver(path: PackedVector2Array, ticket: int = 1) -> Dictionary:
	return {"path":path,"step":0,"t":0.0,"ticket":ticket,"sprite_id":0,"heading":Vector2.RIGHT,"born":0.0,"age":0.0,"origin":0,"dest":1,"ideal":10.0,"accident_clock":0.0,"crash_left":0.0,"route_revision":g.road_revision}

func tick(dt: float, incidents: bool = false) -> void:
	g.elapsed+=dt
	if incidents: g.incidents.update(dt)
	if g.graph_dirty: g.rebuild_graph()
	g.traffic.update(dt)

func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false);g.hide()
	# Municipal destruction survives the real save/load path and can be rebuilt.
	g.save_path="/tmp/fire-junctions-%d.save"%OS.get_process_id()
	var municipal=g.NO_CELL
	for p in g.roads:
		if g.roads[p].has("urban_city"): municipal=p;break
	assert(municipal!=g.NO_CELL)
	var municipal_kind=g.roads[municipal].kind
	g.roads[municipal].hp=1.0;g.incidents.ignite(municipal)
	g.elapsed+=.5;g.incidents.update(.5)
	assert(not g.roads.has(municipal))
	g.save_game(false);assert(g.load_game())
	assert(not g.roads.has(municipal) and g.demolished_access_tiles.has(municipal) and not g.road_open(municipal))
	g.services.deploy("fire",municipal);g.cursor=municipal;g.kind=municipal_kind;g.anchor=g.NO_CELL
	g.apply_road_operation(0)
	assert(g.roads.has(municipal) and not g.demolished_access_tiles.has(municipal))
	DirAccess.remove_absolute(g.save_path)
	fixture()
	var car=driver(straight);car.t=1.1;g.cars=[car]
	g.incidents.ignite(center)
	assert(not g.road_open(center) and g.graph_dirty)
	tick(.2)
	assert(g.traffic.position(car)==Vector2i(straight[0]),"Even a ready vehicle cannot enter a burning cell")
	assert(g.traffic.route(Vector2i(straight[0]),1).is_empty())
	assert(g.gameplay.car_reason(car).contains("Incendio"))
	g.incidents.update(0)
	assert(g.roads[center].hp==100,"Pause must not consume roads")
	g.elapsed+=10;g.incidents.update(10)
	assert(is_equal_approx(g.roads[center].hp,80),"Fire must do gradual, timed damage")
	g.services.deploy("fire",center)
	assert(g.graph_dirty and g.incidents.fire.is_empty())
	g.rebuild_graph();assert(g.road_open(center) and g.traffic.route(Vector2i(straight[0]),1).size()==4)
	for i in 100: tick(.02)
	assert(g.cars.is_empty() and g.trips==1,"The interrupted journey resumes without losing its destination")
	# A fire diverts a moving vehicle instead of discarding its trip.
	fixture()
	for x in range(100,104): add_road(Vector2i(x,101))
	g.rebuild_graph();car=driver(straight);g.cars=[car]
	g.incidents.ignite(center);tick(.02)
	assert(not car.path.has(Vector2(center)) and Vector2i(car.path[1])==Vector2i(100,101))
	for i in 300: tick(.02)
	assert(g.trips==1 and g.cars.is_empty())
	# Expiration only damages the fraction of the step for which fire was active.
	fixture();g.incidents.ignite(center,2)
	g.elapsed=5;g.incidents.update(5)
	assert(is_equal_approx(g.roads[center].hp,96) and g.road_open(center) and g.graph_dirty)
	# Spread into a road also invalidates routes immediately.
	fixture()
	var source=center+Vector2i.UP
	for d in g.DIRS:
		if source+d!=center: g.terrain.set_cell(source+d,1)
	g.incidents.ignite(source);g.rebuild_graph()
	g.incidents.spread_fire(g.incidents.zones[0])
	assert(g.incidents.fire.has(center) and not g.road_open(center) and g.graph_dirty)
	# Repairs in progress cannot heal burning asphalt; new repairs are refused.
	fixture();g.roads[center].hp=50
	assert(g.services.repair([center],true))
	var left=g.services.service_jobs[center].left
	g.incidents.ignite(center);g.services.update(20)
	assert(g.services.service_jobs[center].left==left)
	g.elapsed=10;g.incidents.update(10)
	assert(g.roads[center].hp==30)
	var other=Vector2i(102,100);g.roads[other].hp=50;g.incidents.ignite(other)
	assert(not g.services.repair([other],true))
	fixture();g.speed_index=1;g.roads[center].hp=50;g.roads[center].work=1;g.roads[center].total=1
	g.incidents.ignite(center);g._process(2)
	assert(g.roads[center].work==1 and g.roads[center].hp==46,"Construction also pauses while burning")
	# Fire reaches zero and removes roads, including protected municipal streets.
	fixture();g.roads[center].urban_city=0
	g.incidents.ignite(center);g.elapsed=49;g.incidents.update(49)
	assert(g.roads.has(center) and g.roads[center].hp==2)
	g.elapsed=50;g.incidents.update(1)
	assert(not g.roads.has(center) and g.demolished_access_tiles.has(center))
	g.services.deploy("fire",center)
	add_road(center);g.rebuild_graph();assert(g.road_open(center))
	# An occupant is held in place if ignition happens underneath it.
	fixture();car=driver(straight);car.step=1;car.t=.8;g.cars=[car]
	g.incidents.ignite(center);tick(.5)
	assert(g.traffic.position(car)==center and car.t==.8)
	# General wear is much faster, and traffic adds its own wear.
	fixture();g.speed_index=1
	var hp=g.roads[center].hp
	g._process(10)
	assert(absf(hp-g.roads[center].hp-.8)<.001)
	fixture();car=driver(straight);g.cars=[car];tick(.1)
	assert(absf(g.roads[Vector2i(straight[0])].hp-(100-.014))<.001)
	# A lone driver must actually stop before an uncontrolled crossing.
	fixture(true);car=driver(straight);g.cars=[car]
	for i in 10: tick(.02)
	assert(car.step==0 and is_equal_approx(car.t,g.WorldSettings.JUNCTION_STOP_LINE))
	assert(car.yielding and g.gameplay.car_reason(car).contains("Cediendo"))
	for i in 25: tick(.02)
	assert(car.step==0 and car.t==g.WorldSettings.JUNCTION_STOP_LINE)
	var wait=car.yield_wait
	g.traffic.update(0);assert(car.yield_wait==wait)
	var saved=g.traffic.snapshot();g.traffic.restore(saved);car=g.cars[0]
	assert(car.yield_wait==wait and g.traffic.junctions.clock==saved.junctions.clock)
	for i in 100: tick(.02)
	assert(g.trips==1 and g.cars.is_empty())
	# Loading a vehicle already granted passage must never send it backwards.
	fixture(true);car=driver(straight);g.cars=[car]
	for i in 60:
		tick(.02)
		if car.step==0 and car.t>g.WorldSettings.JUNCTION_STOP_LINE: break
	assert(car.step==0 and car.t>g.WorldSettings.JUNCTION_STOP_LINE)
	var progress=car.t
	saved=g.traffic.snapshot();g.traffic.restore(saved);car=g.cars[0];tick(.02)
	assert(car.step>0 or car.t>progress)
	# Simultaneous arrivals get distinct turns, then all complete their trips.
	fixture(true)
	var across=driver(PackedVector2Array([Vector2(101,99),Vector2(center),Vector2(102,100),Vector2(103,100)]),2)
	car=driver(straight);g.cars=[across,car] # Reverse array order to verify stable tie-breaking.
	var entries: Dictionary = {}
	for i in 500:
		tick(.02)
		for vehicle in [car,across]:
			if vehicle.step>=1 and not entries.has(vehicle.ticket): entries[vehicle.ticket]=g.elapsed
		if g.cars.is_empty(): break
	assert(entries.has(1) and entries.has(2) and entries[2]>entries[1])
	assert(entries[2]-entries[1]>=g.WorldSettings.JUNCTION_HEADWAY and g.trips==2)
	# Enabled green lights remove the extra stop; red lights still hold traffic.
	fixture(true);g.incidents.signals[center]={"ns":1.0,"ew":120.0,"enabled":true,"offset":1.0}
	g.graph_dirty=true;car=driver(straight);g.cars=[car]
	for i in 20: tick(.02)
	assert(car.step>=1 and not car.get("yielding",false))
	g.rebuild_graph();assert(not g.graph.junction_delays.has(g.point_id(center)))
	fixture(true);g.incidents.signals[center]={"ns":120.0,"ew":1.0,"enabled":true,"offset":0.0}
	car=driver(straight);g.cars=[car]
	for i in 50: tick(.02)
	assert(car.step==0 and car.t==0 and g.gameplay.car_reason(car)=="Semáforo en rojo")
	g.incidents.signals[center].enabled=false;g.graph_dirty=true
	for i in 20: tick(.02)
	assert(car.step==0 and car.yielding)
	assert(g.graph.junction_delays.has(g.point_id(center)))
	# Contiguous junctions must not deadlock a pair of opposing vehicles.
	fixture(true)
	add_road(Vector2i(102,99));add_road(Vector2i(102,101));g.rebuild_graph()
	car=driver(straight)
	var reverse_path=straight.duplicate();reverse_path.reverse()
	across=driver(reverse_path,2);across.origin=1;across.dest=0
	g.cars=[car,across]
	for i in 700:
		tick(.02)
		if g.cars.is_empty(): break
	assert(g.cars.is_empty() and g.trips==2,"Adjacent junctions must keep draining their queues")
	print("PASS: fire blocks and reroutes, progressive destruction, emergency reopening, paused repairs, faster wear, junction stops, fair queues, signals, saved waits and adjacent crossings")
	g.free();quit()
