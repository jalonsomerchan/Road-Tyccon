extends "res://tests/junction_safety.gd"

func tee_fixture(on_access: bool = false) -> void:
	fixture()
	for i in range(1,4):
		g.roads.erase(C+Vector2i.UP*i);g.road_nodes.erase(C+Vector2i.UP*i)
	for i in range(-3,4):
		var p=C+Vector2i.RIGHT*i
		g.roads[p]=g.city_road(0,true);g.road_nodes[p]={"kind":0,"axis":true}
	place_sign(C+Vector2i.DOWN if on_access else C,"yield",0)

func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false);g.hide()
	# The screenshot: an asphalt branch yields to both directions of a dirt road.
	for on_access in [false,true]:
		for reverse_order in [false,true]:
			tee_fixture(on_access)
			var east=driver([C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1)
			var west=driver([C+Vector2i.RIGHT,C,C+Vector2i.LEFT,C+Vector2i.LEFT*2,C+Vector2i.LEFT*3],2,0)
			var branch=driver([C+Vector2i.DOWN,C,C+Vector2i.LEFT,C+Vector2i.LEFT*2,C+Vector2i.LEFT*3],3,0)
			branch.t=g.WorldSettings.JUNCTION_STOP_LINE
			g.cars=[branch,west,east] if reverse_order else [east,west,branch]
			for i in 400:
				tick()
				for main in [east,west]:
					if main.step==0:
						assert(not main.get("yielding",false) and not main.get("blocked",false),"Only the signed asphalt branch must yield; the dirt road keeps flowing")
				if east.step==0 or west.step==0: assert(branch.step==0)
				if g.cars.is_empty(): break
			assert(g.trips==3 and g.incidents.accidents==0)
	# A right turn off the priority road does not obstruct the opposite through lane.
	tee_fixture()
	var turning=driver([C+Vector2i.LEFT,C,C+Vector2i.DOWN,C+Vector2i.DOWN*2,C+Vector2i.DOWN*3],1,2)
	var through=driver([C+Vector2i.RIGHT,C,C+Vector2i.LEFT,C+Vector2i.LEFT*2,C+Vector2i.LEFT*3],2,0)
	g.cars=[turning,through]
	for i in 400:
		tick()
		for vehicle in [turning,through]:
			if vehicle.step==0: assert(not vehicle.get("yielding",false) and not vehicle.get("blocked",false))
		if g.cars.is_empty(): break
	assert(g.trips==2 and g.incidents.accidents==0)
	# A left turn yields to oncoming priority traffic, even with the lower ticket.
	tee_fixture()
	turning=driver([C+Vector2i.RIGHT,C,C+Vector2i.DOWN,C+Vector2i.DOWN*2,C+Vector2i.DOWN*3],1,2)
	through=driver([C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],2,1)
	g.cars=[turning,through]
	for i in 400:
		tick()
		if through.step==0: assert(not through.get("yielding",false) and not through.get("blocked",false) and turning.step==0)
		if g.cars.is_empty(): break
	assert(g.trips==2 and g.incidents.accidents==0)
	# A continuous convoy must not inherit the branch's stop line or cooldown.
	tee_fixture(true)
	var points: Array=[]
	for i in range(-3,4): points.append(C+Vector2i.RIGHT*i)
	for i in 3:
		var main=driver(points,i+1,1);main.step=i;g.cars.append(main)
	var branch=driver([C+Vector2i.DOWN,C,C+Vector2i.LEFT,C+Vector2i.LEFT*2,C+Vector2i.LEFT*3],4,0)
	branch.t=g.WorldSettings.JUNCTION_STOP_LINE;g.cars.append(branch)
	for i in 400:
		tick()
		for vehicle in g.cars:
			if vehicle.ticket!=branch.ticket: assert(not vehicle.get("blocked",false) and not vehicle.get("yielding",false))
		if g.cars.is_empty(): break
	assert(g.trips==4 and g.incidents.accidents==0)
	# The branch must see priority traffic before it reaches the last approach cell.
	tee_fixture()
	var main=driver([C+Vector2i.LEFT*2,C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1)
	main.t=0.6
	branch=driver([C+Vector2i.DOWN,C,C+Vector2i.LEFT,C+Vector2i.LEFT*2,C+Vector2i.LEFT*3],2,0)
	branch.t=g.WorldSettings.JUNCTION_STOP_LINE;g.cars=[branch,main]
	tick();assert(not g.traffic.junctions.has_grant(branch,C))
	for i in 400:
		tick()
		if main.step<2: assert(not main.get("blocked",false) and not main.get("yielding",false))
		if g.cars.is_empty(): break
	assert(g.trips==2 and g.incidents.accidents==0)
	# A sufficiently large gap still lets the branch join before distant traffic.
	tee_fixture()
	main=driver(points,1,1)
	branch=driver([C+Vector2i.DOWN,C,C+Vector2i.LEFT,C+Vector2i.LEFT*2,C+Vector2i.LEFT*3],2,0)
	branch.t=g.WorldSettings.JUNCTION_STOP_LINE;g.cars=[main,branch]
	tick();assert(g.traffic.junctions.has_grant(branch,C))
	for i in 400:
		tick()
		if main.step<3: assert(not main.get("blocked",false) and not main.get("yielding",false))
		if g.cars.is_empty(): break
	assert(g.trips==2 and g.incidents.accidents==0)
	# Both simultaneous permissions survive save/load without sharing mutable arrays.
	tee_fixture()
	main=driver([C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1)
	var other=driver([C+Vector2i.RIGHT,C,C+Vector2i.LEFT,C+Vector2i.LEFT*2,C+Vector2i.LEFT*3],2,0)
	g.cars=[main,other];tick()
	var saved=g.traffic.snapshot()
	assert(saved.junctions.grants[C].size()==2)
	g.traffic.restore(saved)
	for i in 400:
		tick()
		for vehicle in g.cars: assert(not vehicle.get("yielding",false) and not vehicle.get("blocked",false))
		if g.cars.is_empty(): break
	assert(g.trips==2 and saved.junctions.grants[C].size()==2)
	g.traffic.junctions.restore({"clock":0.0,"grants":{C:1},"cooldowns":{C:0.4}})
	assert(g.traffic.junctions.has_grant(main,C))
	g.traffic.junctions.update(0.5,{})
	assert(g.traffic.junctions.grants.is_empty() and g.traffic.junctions.cooldowns.is_empty())
	print("PASS: priority dirt road flows in both directions while the signed asphalt branch yields")
	g.free();quit()
