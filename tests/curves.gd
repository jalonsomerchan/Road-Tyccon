extends SceneTree
var g
func _initialize() -> void: call_deferred("run")

func fixture(path: PackedVector2Array, kind: int = 3) -> void:
	g.roads.clear();g.road_nodes.clear();g.city_cells.clear();g.city_connectors.clear();g.cars.clear()
	g.traffic.reset();g.incidents.reset();g.services.reset();g.gameplay.reset()
	g.elapsed=0;g.trips=0;g.earned=0;g.terrain.fill(0)
	g.cities=[]
	for i in 2:
		g.cities.append({"pos":Vector2i(path[0] if i==0 else path[-1]),"name":"Prueba "+str(i),"pop":1000,"profile":0,"received":0,"recent":0,"accesses":[],"access_dirs":[Vector2i.RIGHT]})
	for cell in path:
		var p=Vector2i(cell)
		g.roads[p]=g.city_road(kind,true);g.road_nodes[p]={"kind":kind,"axis":true}
	g.incidents.rules.weather_enabled=false;g.incidents.rules.abandon_enabled=false
	g.rebuild_graph()

func driver(path: PackedVector2Array, step: int = 0) -> Dictionary:
	return {"path":path,"step":step,"t":0.0,"ticket":1,"sprite_id":0,"heading":Vector2.RIGHT,"born":0.0,"age":0.0,"origin":0,"dest":1,"ideal":10.0,"accident_clock":0.0,"crash_left":0.0,"route_revision":g.road_revision}

func duration(path: PackedVector2Array) -> float:
	fixture(path)
	g.cars=[driver(path)]
	for i in 2000:
		g.elapsed+=.01;g.traffic.update(.01)
		if g.cars.is_empty(): return g.elapsed
	assert(false,"The vehicle must finish its journey")
	return INF

func turns(path: PackedVector2Array) -> int:
	var result=0
	for i in range(1,path.size()-1):
		if path[i]-path[i-1]!=path[i+1]-path[i]: result+=1
	return result

func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false);g.hide()
	var straight=PackedVector2Array()
	for i in 9: straight.append(Vector2(100+i,100))
	var bent=PackedVector2Array([Vector2(100,100),Vector2(101,100),Vector2(102,100),Vector2(103,100),Vector2(103,101),Vector2(104,101),Vector2(105,101),Vector2(105,102),Vector2(106,102)])
	var straight_time=duration(straight)
	var bent_time=duration(bent)
	assert(bent_time>straight_time and turns(bent)==4)
	var predicted=(8+turns(bent)*(1/g.WorldSettings.CURVE_SPEED_FACTOR-1))/g.Catalog.ROADS[3].speed
	assert(absf(bent_time-predicted)<.03 and absf(straight_time-8/g.Catalog.ROADS[3].speed)<.03)
	# Turning at a four-way crossing slows only the vehicle that actually turns.
	var corner=PackedVector2Array([Vector2(100,100),Vector2(101,100),Vector2(101,101)])
	fixture(corner)
	for p in [Vector2i(102,100),Vector2i(101,99)]: g.roads[p]=g.city_road(3,true)
	g.rebuild_graph()
	var turning=driver(corner,1)
	var continuing=driver(PackedVector2Array([Vector2(100,100),Vector2(101,100),Vector2(102,100)]),1)
	assert(is_equal_approx(g.traffic.driving_speed(turning)/g.traffic.driving_speed(continuing),g.WorldSettings.CURVE_SPEED_FACTOR))
	# A mid-frame crossing converts remaining time to the lower corner speed.
	g.cars=[driver(corner)];g.cars[0].t=.95
	g.elapsed=.04;g.traffic.update(.04)
	assert(g.cars[0].step==1 and absf(g.cars[0].t-(.95+3.2*.04-1)*g.WorldSettings.CURVE_SPEED_FACTOR)<.0001)
	# Replanning and save/load preserve the incoming direction at a corner.
	g.cars=[turning];g.rebuild_graph();g.elapsed=.01;g.traffic.update(.01)
	assert(g.cars[0].step==0 and g.traffic.curve_factor(g.cars[0])==g.WorldSettings.CURVE_SPEED_FACTOR)
	var saved=g.traffic.snapshot();g.traffic.restore(saved)
	assert(g.cars[0].incoming==Vector2i.RIGHT and g.traffic.curve_factor(g.cars[0])==g.WorldSettings.CURVE_SPEED_FACTOR)
	# The same start/destination can need different paths for different headings.
	var top=PackedVector2Array([Vector2(100,100),Vector2(101,100),Vector2(102,100),Vector2(102,101),Vector2(102,102)])
	var bottom=PackedVector2Array([Vector2(100,100),Vector2(100,101),Vector2(100,102),Vector2(101,102),Vector2(102,102)])
	fixture(top)
	for cell in bottom:
		var p=Vector2i(cell);g.roads[p]=g.city_road(3,true);g.road_nodes[p]={"kind":3,"axis":true}
	g.rebuild_graph()
	var right=g.traffic.route(Vector2i(100,100),1,Vector2i.RIGHT)
	var down=g.traffic.route(Vector2i(100,100),1,Vector2i.DOWN)
	assert(right==top and down==bottom,"Heading-aware route caches must not mix paths")
	assert(g.traffic.route(Vector2i(100,100),1,Vector2i.RIGHT)==top)
	g.roads[Vector2i(101,100)].closed=true;g.rebuild_graph()
	assert(g.traffic.route(Vector2i(100,100),1,Vector2i.RIGHT)==bottom)
	g.roads[Vector2i(100,101)].closed=true;g.rebuild_graph()
	assert(g.traffic.route(Vector2i(100,100),1).is_empty())
	# With equally long choices, the router favours fewer corners.
	var smooth=PackedVector2Array([Vector2(100,100),Vector2(101,100),Vector2(102,100),Vector2(103,100),Vector2(104,100),Vector2(104,101),Vector2(104,102)])
	var winding=PackedVector2Array([Vector2(100,100),Vector2(100,101),Vector2(101,101),Vector2(101,102),Vector2(102,102),Vector2(103,102),Vector2(104,102)])
	fixture(smooth)
	for cell in winding:
		var p=Vector2i(cell);g.roads[p]=g.city_road(3,true);g.road_nodes[p]={"kind":3,"axis":true}
	g.rebuild_graph();assert(g.traffic.route(Vector2i(100,100),1)==smooth)
	# One-way roundabout connections remain valid under directional routing.
	fixture(PackedVector2Array([Vector2(200,198),Vector2(202,200)]))
	g.cursor=Vector2i(200,200);g.kind=3;g.build_roundabout()
	for p in g.roads: g.roads[p].work=0
	g.rebuild_graph()
	var ring_path=g.traffic.route(Vector2i(200,198),1)
	assert(ring_path.size()>2)
	for i in range(ring_path.size()-1): assert(g.edge_allowed(Vector2i(ring_path[i]),Vector2i(ring_path[i+1])))
	print("PASS: same-length straight %.2f s vs four-turn %.2f s, crossing turns, precise speed transition, replanning/save headings, directional cache, fewer-turn routing, closures and one-way roundabouts"%[straight_time,bent_time])
	g.free();quit()
