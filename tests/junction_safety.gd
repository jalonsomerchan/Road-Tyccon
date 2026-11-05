extends SceneTree
const C = Vector2i(400,400)
var g

func _initialize() -> void: call_deferred("run")

func fixture() -> void:
	g.roads.clear();g.road_nodes.clear();g.city_cells.clear();g.city_connectors.clear();g.cars.clear()
	g.traffic.reset();g.incidents.reset();g.services.reset();g.signage.reset()
	g.terrain.fill(0);g.elapsed=0;g.trips=0;g.money=100000
	g.cities=[]
	for p in [C+Vector2i.LEFT*3,C+Vector2i.RIGHT*3,C+Vector2i.DOWN*3,C+Vector2i.UP*3]:
		g.cities.append({"pos":p,"name":"Prueba","pop":1000,"profile":0,"received":0,"recent":0,"accesses":[],"access_dirs":[Vector2i.RIGHT]})
	for i in range(-3,4):
		for p in [C+Vector2i(i,0),C+Vector2i(0,i)]:
			g.roads[p]=g.city_road(3,true);g.road_nodes[p]={"kind":3,"axis":true}
	g.incidents.rules.weather_enabled=false;g.incidents.rules.abandon_enabled=false
	g.rebuild_graph()

func driver(points: Array, ticket: int, dest: int) -> Dictionary:
	return {"path":PackedVector2Array(points),"step":0,"t":0.0,"ticket":ticket,"born":0.0,"age":0.0,"origin":0,"dest":dest,"ideal":10.0,"accident_clock":0.0,"crash_left":0.0,"route_revision":g.road_revision}

func tick(dt: float = 0.02) -> void:
	g.elapsed+=dt;g.traffic.update(dt)

func place_sign(p: Vector2i, id: String, direction: int) -> void:
	g.signage.placed[p]=[{"id":id,"direction":direction}]
	g.rebuild_graph()

func light(ns: float, ew: float, offset: float = 0.0) -> void:
	g.incidents.signals[C]={"ns":ns,"ew":ew,"enabled":true,"offset":offset}

func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false);g.hide()
	# A STOP on the approach protects the following junction, after its full stop.
	fixture();place_sign(C+Vector2i.LEFT,"stop",1)
	var car=driver([C+Vector2i.LEFT*2,C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1)
	g.cars=[car]
	assert(not g.traffic.junctions.collision_risk(C))
	for i in 25: tick()
	assert(car.step==0 and is_equal_approx(car.t,g.WorldSettings.JUNCTION_STOP_LINE))
	for i in 200: tick()
	assert(g.trips==1 and g.cars.is_empty())
	# Direction matters: a sign facing away from the intersection does not protect it.
	fixture();place_sign(C+Vector2i.LEFT,"yield",3)
	assert(g.traffic.junctions.collision_risk(C))
	# A yielding driver waits for priority traffic before it reaches the stop line.
	for reverse_order in [false,true]:
		fixture();place_sign(C+Vector2i.LEFT,"yield",1)
		car=driver([C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1)
		car.t=g.WorldSettings.JUNCTION_STOP_LINE
		var priority=driver([C+Vector2i.UP,C,C+Vector2i.DOWN,C+Vector2i.DOWN*2,C+Vector2i.DOWN*3],2,2)
		g.cars=[priority,car] if reverse_order else [car,priority]
		tick()
		assert(g.traffic.junctions.has_grant(priority,C) and car.step==0)
		var entries: Array=[]
		for i in 200:
			tick()
			for vehicle in [car,priority]:
				if vehicle.step>0 and not vehicle.ticket in entries: entries.append(vehicle.ticket)
		assert(entries==[2,1] and g.trips==2 and g.incidents.accidents==0)
	# Red traffic approaches the line; green overrides STOP signs.
	fixture();light(120,1)
	car=driver([C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1);g.cars=[car]
	tick();assert(g.gameplay.car_reason(car)=="Acercándose al semáforo en rojo")
	for i in 100: tick()
	assert(car.step==0 and is_equal_approx(car.t,g.WorldSettings.JUNCTION_STOP_LINE))
	assert(g.gameplay.car_reason(car)=="Semáforo en rojo")
	g.incidents.signals[C].enabled=false
	for i in 100: tick()
	assert(g.trips==1)
	fixture();place_sign(C,"stop",1);light(1,120,1)
	car=driver([C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1);g.cars=[car]
	for i in 20: tick()
	assert(car.step>=1,"Green must not impose the STOP waiting time")
	# A phase change lets an already committed driver clear before cross traffic.
	fixture();light(1,120,1)
	car=driver([C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1);g.cars=[car]
	for i in 100:
		tick()
		if car.t>0.7: break
	assert(car.step==0 and car.t>0.7)
	var progress: float=car.t
	var across=driver([C+Vector2i.UP,C,C+Vector2i.DOWN,C+Vector2i.DOWN*2,C+Vector2i.DOWN*3],2,2)
	across.t=g.WorldSettings.JUNCTION_STOP_LINE;g.cars.append(across)
	light(120,1);tick()
	assert(car.t>progress and across.step==0)
	assert(g.gameplay.car_reason(car)!="Semáforo en rojo")
	for i in 100:
		tick()
		if car.step==0 or (car.step==1 and car.t<g.WorldSettings.JUNCTION_CLEAR_PROGRESS):
			assert(across.step==0,"A new green must wait for the previous movement to clear")
	assert(across.step>0 and g.incidents.accidents==0)
	# A grant made before the line is revoked on red, including after save/load.
	fixture();light(1,120,1)
	car=driver([C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1);g.cars=[car]
	tick();assert(g.traffic.junctions.has_grant(car,C) and car.t<g.WorldSettings.JUNCTION_STOP_LINE)
	var saved=g.traffic.snapshot();g.traffic.restore(saved);car=g.cars[0]
	light(120,1)
	for i in 50: tick()
	assert(car.step==0 and is_equal_approx(car.t,g.WorldSettings.JUNCTION_STOP_LINE))
	# Opposing left turns sharing green cannot occupy the conflict zone together.
	fixture();light(1,120,1)
	car=driver([C+Vector2i.LEFT,C,C+Vector2i.UP,C+Vector2i.UP*2,C+Vector2i.UP*3],1,3)
	across=driver([C+Vector2i.RIGHT,C,C+Vector2i.DOWN,C+Vector2i.DOWN*2,C+Vector2i.DOWN*3],2,2);g.cars=[across,car]
	for i in 250:
		tick()
		assert(not (car.step==1 and across.step==1 and car.t<g.WorldSettings.JUNCTION_CLEAR_PROGRESS and across.t<g.WorldSettings.JUNCTION_CLEAR_PROGRESS))
	assert(g.trips==2)
	# A blocked exit holds green traffic outside the junction until space returns.
	fixture();light(1,120,1)
	car=driver([C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1)
	var queue=driver([C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],2,1)
	queue.incoming=Vector2i.RIGHT;queue.crash_left=5;g.cars=[car,queue]
	for i in 100: tick()
	assert(car.step==0 and is_equal_approx(car.t,g.WorldSettings.JUNCTION_STOP_LINE))
	queue.crash_left=0
	for i in 200: tick()
	assert(g.trips==2)
	# The following gap applies across cell boundaries as well as within one segment.
	fixture()
	car=driver([C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1)
	queue=driver([C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],2,1)
	queue.incoming=Vector2i.RIGHT;queue.t=0.1;queue.crash_left=5;g.cars=[car,queue]
	for i in 100:
		tick()
		assert(car.step==0 and 1+queue.t-car.t>=g.traffic.FOLLOWING_GAP-0.00001)
	queue.crash_left=0
	for i in 200: tick()
	assert(g.trips==2)
	# The first vehicle in a green queue gets the grant, regardless of ticket/order.
	fixture();light(1,120,1)
	car=driver([C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],2,1)
	car.t=0.8
	queue=driver([C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1)
	g.cars=[queue,car];tick()
	assert(g.traffic.junctions.has_grant(car,C))
	for i in 250: tick()
	assert(g.trips==2)
	# Two different approaches merging into the same exit keep their order and gap.
	fixture();g.rng.seed=1234
	car=driver([C+Vector2i.LEFT,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1)
	queue=driver([C+Vector2i.UP,C,C+Vector2i.RIGHT,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],2,1)
	car.t=0.95;queue.t=0.95;g.cars=[car,queue]
	for i in 250:
		tick()
		if car.step>=1 and queue.step>=1 and car.step<car.path.size()-1 and queue.step<queue.path.size()-1:
			var distance = absf((car.step+car.t)-(queue.step+queue.t))
			assert(distance>=g.traffic.FOLLOWING_GAP-0.00001)
	assert(g.trips==2)
	# Adjacent signed junctions still drain opposing queues without a circular wait.
	fixture();place_sign(C,"stop",1)
	var adjacent=C+Vector2i.RIGHT
	for p in [adjacent+Vector2i.UP,adjacent+Vector2i.DOWN]:
		g.roads[p]=g.city_road(3,true);g.road_nodes[p]={"kind":3,"axis":true}
	place_sign(adjacent,"stop",3)
	car=driver([C+Vector2i.LEFT,C,adjacent,C+Vector2i.RIGHT*2,C+Vector2i.RIGHT*3],1,1)
	queue=driver([C+Vector2i.RIGHT*2,adjacent,C,C+Vector2i.LEFT,C+Vector2i.LEFT*2,C+Vector2i.LEFT*3],2,0)
	g.cars=[car,queue]
	for i in 400: tick()
	assert(g.trips==2 and g.cars.is_empty(),"Adjacent regulated crossings must not deadlock")
	# Repeated four-way queues clear safely, including large simulation steps.
	for control in ["stop","yield","light"]:
		for dt in [0.02,0.4]:
			fixture()
			if control=="light":
				light(0.35,0.35)
			else:
				g.signage.placed[C]=[]
				for heading in 4: g.signage.placed[C].append({"id":control,"direction":heading})
				g.rebuild_graph()
			var ticket=0
			for heading in 4:
				var direction: Vector2i=g.signage.DIRECTIONS[heading]
				var points: Array=[]
				for i in range(-3,4): points.append(C+direction*i)
				for step in 3:
					ticket+=1
					var vehicle=driver(points,ticket,[3,1,2,0][heading])
					vehicle.step=step;g.cars.append(vehicle)
			for i in int(40.0/dt):
				tick(dt)
				var crossing: Array=[]
				for vehicle in g.cars:
					if g.traffic.position(vehicle)!=C or vehicle.t>=g.WorldSettings.JUNCTION_CLEAR_PROGRESS: continue
					for other in crossing: assert(not g.traffic.junctions.conflicts(vehicle,other,C))
					crossing.append(vehicle)
				if g.cars.is_empty(): break
			assert(g.trips==12 and g.cars.is_empty() and g.incidents.accidents==0,"Regulated four-way queues must clear without conflicts")
	print("PASS: approach signs, directional priority, STOP timing, red stop lines, phase clearance, saved grants, opposing turns, blocked exits and following gaps across cells")
	g.free();quit()
