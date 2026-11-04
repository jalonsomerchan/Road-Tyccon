extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var g = load("res://scenes/main.tscn").instantiate()
	root.add_child(g); g.set_process(false)
	g.roads.clear(); g.road_nodes.clear(); g.cars.clear(); g.traffic.reset(); g.services.reset(); g.incidents.reset()
	g.terrain.fill(0); g.incidents.rules.weather_enabled=false; g.incidents.rules.abandon_enabled=false
	var start = Vector2i(400,400)
	for i in 7:
		var p = start+Vector2i(i,0)
		g.roads[p]=g.city_road(3,true)
		g.road_nodes[p]={"kind":3,"axis":true}
	g.roads[start+Vector2i(2,0)].hp=40
	g.roads[start+Vector2i(4,0)].hp=60
	g.rebuild_graph()
	var path = PackedVector2Array()
	for i in range(1,7): path.append(Vector2(start+Vector2i(i,0)))
	var car = {"path":path,"step":0,"t":0.0,"age":0.0,"born":g.elapsed,"origin":0,"dest":1,"color":0,"ideal":10.0,"accident_clock":0.0,"crash_left":0.0,"route_revision":g.road_revision,"blocked":false,"ticket":999}
	g.cars=[car]
	g.select_tool(2);g.cursor=start+Vector2i(1,0);g.apply_action()
	assert(g.anchor==g.cursor)
	g.cursor=start+Vector2i(4,0);g.apply_action()
	assert(g.anchor==g.NO_CELL and g.services.service_jobs.size()==4)
	var tile = start+Vector2i(2,0)
	var before = g.services.service_jobs[tile].left
	g.services.update(30)
	assert(g.services.service_jobs[tile].left==before and g.services.evacuating(tile))
	assert(not g.services.evacuation_move(start,tile))
	g.save_path="res://tests/repair_range_save.bin";g.save_game(false)
	g.services.reset();assert(g.load_game())
	assert(g.services.evacuating(tile) and g.services.service_jobs[tile].left==before)
	g.rebuild_graph()
	for i in 200:
		g.traffic.update(0.1)
		if g.traffic.position(g.cars[0])==start+Vector2i(5,0): break
	assert(g.traffic.position(g.cars[0])==start+Vector2i(5,0), "A car already inside must leave the closed range")
	g.services.update(0.1)
	assert(not g.services.evacuating(tile) and g.services.service_jobs[tile].left<before)
	assert(not g.road_open(tile))
	g.services.update(30)
	assert(g.services.service_jobs.is_empty())
	for i in range(1,5): assert(g.road_open(start+Vector2i(i,0)) and g.roads[start+Vector2i(i,0)].hp==100)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.save_path))
	print("PASS: repair range closes, evacuates, waits, survives save, repairs and reopens")
	quit()
