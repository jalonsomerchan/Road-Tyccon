extends SceneTree
var g
const CENTER = Vector2i(100,100)
const WEST = CENTER+Vector2i.LEFT*2
const EAST = CENTER+Vector2i.RIGHT*2
const NORTH = CENTER+Vector2i.UP*2

func _initialize() -> void: call_deferred("run")

func road(p: Vector2i, along_x: bool) -> void:
	g.roads[p] = g.city_road(8,along_x)
	g.road_nodes[p] = {"kind":8,"axis":along_x}

func place_sign(p: Vector2i, id: String, heading: int) -> void:
	g.cursor = p
	g.construction_mode = "sign:"+id
	g.signage.heading = heading
	g.apply_action()
	g.rebuild_graph()

func path(a: Vector2i, b: Vector2i) -> PackedVector2Array:
	return g.graph.driving_path(g.point_id(a),g.point_id(b))

func run() -> void:
	g = load("res://scenes/main.tscn").instantiate()
	root.add_child(g)
	g.set_process(false)
	g.hide()
	g.cities.clear()
	g.city_cells.clear()
	g.roads.clear()
	g.road_nodes.clear()
	g.terrain.fill(0)
	for i in range(-2,3):
		road(CENTER+Vector2i(i,0),true)
		if i!=0: road(CENTER+Vector2i(0,i),false)
	g.rebuild_graph()
	assert(path(WEST,NORTH).size()==5)
	place_sign(CENTER,"no_left",1)
	var alternative = path(WEST,NORTH)
	assert(alternative.is_empty() or alternative.size()>5)
	assert(path(NORTH,WEST).size()==5)
	place_sign(CENTER,"no_left",1)
	place_sign(CENTER,"no_entry",1)
	assert(path(WEST,EAST).is_empty() and path(EAST,WEST).size()==5)
	place_sign(CENTER,"no_entry",1)
	place_sign(CENTER,"one_way",1)
	assert(path(WEST,EAST).size()==5 and path(EAST,WEST).is_empty())
	for p in [WEST,EAST]:
		g.cities.append({"pos":p,"name":"Prueba","pop":1000,"profile":0,"received":0,"recent":0,"accesses":[],"access_dirs":[Vector2i.RIGHT]})
	g.rebuild_graph()
	assert(g.traffic.current_links[0]==[1] and g.traffic.current_links[1].is_empty())
	place_sign(CENTER,"one_way",3)
	assert(path(WEST,EAST).is_empty() and path(EAST,WEST).size()==5)
	assert(g.traffic.current_links[1]==[0] and g.traffic.current_links[0].is_empty())
	place_sign(CENTER,"one_way",3)
	place_sign(WEST,"limit_30",1)
	assert(is_equal_approx(g.signage.speed_at(WEST,Vector2i.RIGHT),2))
	assert(is_equal_approx(g.signage.speed_at(WEST+Vector2i.RIGHT,Vector2i.RIGHT),2))
	assert(is_inf(g.signage.speed_at(CENTER,Vector2i.RIGHT)))
	assert(is_inf(g.signage.speed_at(WEST,Vector2i.LEFT)))
	place_sign(WEST+Vector2i.RIGHT,"end_limit",1)
	assert(is_inf(g.signage.speed_at(WEST+Vector2i.RIGHT,Vector2i.RIGHT)))
	place_sign(WEST+Vector2i.RIGHT,"stop",1)
	var car = {"path":path(WEST,EAST),"step":0,"t":0.0,"ticket":1,"origin":0,"dest":1,
		"born":0.0,"ideal":3.0,"accident_clock":0.0,"crash_left":0.0,"route_revision":g.road_revision}
	assert(g.traffic.junctions.needs_grant(car,WEST+Vector2i.RIGHT))
	assert(not g.traffic.junctions.needs_grant({"path":path(EAST,WEST),"step":2},WEST+Vector2i.RIGHT))
	g.cars=[car]
	for i in 20:
		g.elapsed+=0.02
		g.traffic.update(0.02)
	assert(car.step==0 and car.yielding and is_equal_approx(car.t,g.WorldSettings.JUNCTION_STOP_LINE))
	for i in 150:
		g.elapsed+=0.02
		g.traffic.update(0.02)
	assert(g.trips==1 and g.cars.is_empty())
	g.cities.clear()
	place_sign(NORTH,"hospital",2)
	g.save_path = "/tmp/road-signs-%d.save"%OS.get_process_id()
	g.save_game(false)
	var before: Dictionary = g.signage.snapshot().duplicate(true)
	g.signage.reset()
	assert(g.load_game() and g.signage.snapshot()==before)
	assert(g.construction_mode=="sign:hospital")
	g.incidents.erase_road(NORTH,true)
	assert(not g.signage.placed.has(NORTH))
	DirAccess.remove_absolute(g.save_path)
	print("PASS: directional turns and one-way routing, speed limits and end signs, STOP clearance, removal and sign save/load")
	g.free()
	quit()
