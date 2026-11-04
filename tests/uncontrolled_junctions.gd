extends SceneTree
var g
const C = Vector2i(400,400)
func _initialize() -> void: call_deferred("run")
func driver(start: Vector2i, dest: Vector2i, ticket: int) -> Dictionary:
	return {"path":PackedVector2Array([Vector2(start),Vector2(C),Vector2(dest)]),"step":0,"t":0.95,"ticket":ticket,"sprite_id":0,"heading":Vector2(C-start),"born":0.0,"age":0.0,"origin":0,"dest":1 if ticket==1 else 2,"ideal":10.0,"accident_clock":0.0,"crash_left":0.0,"route_revision":g.road_revision}
func setup_crossing() -> void:
	g.roads.clear();g.road_nodes.clear();g.city_cells.clear();g.city_connectors.clear();g.cars.clear()
	g.traffic.reset();g.incidents.reset();g.services.reset();g.signage.reset()
	g.terrain.fill(0);g.elapsed=0;g.money=10000
	g.cities=[]
	for p in [C+Vector2i.LEFT,C+Vector2i.RIGHT,C+Vector2i.DOWN]:
		g.cities.append({"pos":p,"name":"Prueba","pop":1000,"profile":0,"received":0,"recent":0,"accesses":[],"access_dirs":[Vector2i.RIGHT]})
	for p in [C,C+Vector2i.LEFT,C+Vector2i.RIGHT,C+Vector2i.UP,C+Vector2i.DOWN]:
		g.roads[p]=g.city_road(3,true);g.road_nodes[p]={"kind":3,"axis":true}
	g.incidents.rules.weather_enabled=false;g.incidents.rules.abandon_enabled=false
	g.rebuild_graph()
func tick(dt: float) -> void:
	g.elapsed+=dt
	g.traffic.update(dt)
func seed_for_collision(should_collide: bool) -> int:
	for value in range(1,10000):
		g.rng.seed=value
		var sample=g.rng.randf()
		if (should_collide and sample<0.02) or (not should_collide and sample>0.95): return value
	return 1
func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false);g.hide()
	setup_crossing()
	var car=driver(C+Vector2i.LEFT,C+Vector2i.RIGHT,1)
	car.t=0.0;g.cars=[car]
	assert(g.traffic.junctions.collision_risk(C) and not g.traffic.junctions.needs_grant(car,C))
	for i in 5: tick(0.05)
	assert(car.step>0 or car.t>g.WorldSettings.JUNCTION_STOP_LINE)
	assert(g.incidents.accidents==0)
	setup_crossing()
	car=driver(C+Vector2i.LEFT,C+Vector2i.RIGHT,1)
	var other=driver(C+Vector2i.UP,C+Vector2i.DOWN,2)
	g.cars=[car,other]
	g.rng.seed=seed_for_collision(true)
	var money=g.money
	tick(0.05)
	assert(g.incidents.accidents==1 and car.crash_left>0 and other.crash_left>0)
	assert(g.money==money-g.WorldSettings.ACCIDENT_COST)
	var saved=g.traffic.snapshot();g.traffic.restore(saved)
	assert(g.cars[0].crash_left>0 and g.cars[1].crash_left>0)
	setup_crossing()
	car=driver(C+Vector2i.LEFT,C+Vector2i.RIGHT,1);other=driver(C+Vector2i.UP,C+Vector2i.DOWN,2)
	g.cars=[car,other];g.rng.seed=seed_for_collision(false)
	tick(0.05)
	assert(g.incidents.accidents==0 and not g.traffic.collision_encounters.is_empty())
	var rng_state=g.rng.state
	assert(not g.traffic.collision_encounter(car,other,C,1.0) and g.rng.state==rng_state)
	var checked=g.traffic.snapshot();g.traffic.restore(checked)
	assert(not g.traffic.collision_encounters.is_empty())
	car=driver(C+Vector2i.LEFT,C+Vector2i.DOWN,3)
	other=driver(C+Vector2i.UP,C+Vector2i.LEFT,4)
	g.traffic.collision_encounters.clear()
	assert(g.traffic.turns_right_at(car,C) and g.traffic.turns_right_at(other,C))
	assert(not g.traffic.collision_encounter(car,other,C,1.0) and g.traffic.collision_encounters.is_empty())
	car=driver(C+Vector2i.LEFT,C+Vector2i.RIGHT,5)
	other=driver(C+Vector2i.UP,C+Vector2i.DOWN,6)
	car.step_speed=4.0;other.step_speed=4.0
	var mid_seed=0
	for value in range(1,10000):
		g.rng.seed=value
		var sample=g.rng.randf()
		if sample>0.06 and sample<0.09: mid_seed=value;break
	assert(mid_seed!=0)
	g.rng.seed=mid_seed
	assert(g.traffic.collision_encounter(car,other,C,1.0))
	g.traffic.collision_encounters.clear();g.rng.seed=mid_seed
	assert(not g.traffic.collision_encounter(car,other,C,0.2))
	g.traffic.collision_encounters.clear();g.rng.seed=mid_seed
	car.step_speed=1.0;other.step_speed=1.0
	assert(not g.traffic.collision_encounter(car,other,C,0.5))
	setup_crossing()
	g.signage.placed[C]=[{"id":"stop","direction":1}];g.graph_dirty=true;g.rebuild_graph()
	car=driver(C+Vector2i.LEFT,C+Vector2i.RIGHT,1);other=driver(C+Vector2i.UP,C+Vector2i.DOWN,2)
	car.t=0;other.t=0;g.cars=[car,other]
	assert(not g.traffic.junctions.collision_risk(C) and g.traffic.junctions.needs_grant(car,C))
	for i in 80: tick(0.05)
	assert(g.incidents.accidents==0)
	setup_crossing()
	g.incidents.signals[C]={"ns":30.0,"ew":30.0,"enabled":true,"offset":0.0}
	g.graph_dirty=true;g.rebuild_graph()
	assert(not g.traffic.junctions.collision_risk(C))
	g.incidents.signals[C].enabled=false
	assert(g.traffic.junctions.collision_risk(C))
	print("PASS: uncontrolled crossings allow passage and collisions; signs and lights regulate them")
	quit()
