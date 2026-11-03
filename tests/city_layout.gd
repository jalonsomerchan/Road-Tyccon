extends SceneTree
func _initialize() -> void: call_deferred("run")
func check_plan(g, c: Dictionary) -> void:
	var count=0
	for y in range(-c.radius,c.radius+1):
		for x in range(-c.radius,c.radius+1):
			var p=Vector2i(x,y)
			if not g.CityDesign.is_street(c,p): continue
			count+=1
			assert(not (g.CityDesign.is_street(c,p+Vector2i.RIGHT) and g.CityDesign.is_street(c,p+Vector2i.DOWN) and g.CityDesign.is_street(c,p+Vector2i.ONE)),"No 2×2 asphalt patches or adjacent parallel streets")
	if c.radius>=2: assert(float(count)/pow(2*c.radius+1,2)<=.4,"Urban roads occupy at most 40% of a fresh city")
	assert(g.CityDesign.exit_directions(c).size() in range(2,5))
	assert(c.accesses.size() in range(2,5),"Only 2–4 generated connectors")
func run() -> void:
	var g=load("res://scenes/main.tscn").instantiate()
	root.add_child(g);g.set_process(false)
	g.roads.clear();g.road_nodes.clear();g.cities.clear();g.city_cells.clear();g.city_connectors.clear();g.cars.clear()
	g.traffic.reset();g.incidents.reset();g.maintenance.reset();g.terrain.fill(0)
	g.building_world=true
	for seed in 8:
		for style in 4:
			for radius in range(1,6):
				g.add_city(Vector2i(100+radius*30+style*200,100+seed*30),"Ciudad",radius)
				g.cities.back().design_style=style
				g.cities.back().design_seed=seed
	g.building_world=false
	g.rebuild_city_lookup();g.ensure_city_accesses();g.rebuild_graph()
	for c in g.cities: check_plan(g,c)
	var before=g.roads.duplicate(true)
	g.ensure_city_accesses()
	assert(g.roads==before,"Repeated synchronization must not accumulate roads")
	# Growing and shrinking to the same radius removes obsolete generated roads.
	var c=g.cities[0]
	for radius in [2,3,4,5,4,3,2,1]:
		c.radius=radius;g.rebuild_city_lookup();g.ensure_city_accesses();g.rebuild_graph()
		check_plan(g,c)
	assert(g.roads==before,"A growth/shrink cycle leaves no old road bands or extra stubs")
	# Reproduce the old three-cell-wide cross and its twelve exterior stubs.
	g.roads.clear();g.road_nodes.clear();g.cities.clear();g.city_cells.clear();g.city_connectors.clear()
	g.add_city(Vector2i(100,100),"Los Olmos",3)
	c=g.cities[0];c.design_style=3;c.design_seed=2;c.erase("road_plan_version")
	g.roads.clear();g.road_nodes.clear();c.accesses=[]
	for y in range(-3,4):
		for x in range(-3,4):
			if abs(x)>1 and abs(y)>1:continue
			var p=c.pos+Vector2i(x,y)
			g.roads[p]=g.city_road(20,true);g.roads[p].urban_city=0
	for d in g.DIRS:
		for offset in range(-1,2):
			var gate=c.pos+d*4+Vector2i(-d.y,d.x)*offset
			c.accesses.append({"gate":gate,"end":gate+d*2,"dir":d})
			for step in 3:g.roads[gate+d*step]=g.city_road(20,d.x!=0)
	var old_count=g.roads.size()
	# A player connection to an offset old exit must survive migration.
	var connection=Vector2i(107,101)
	g.roads[connection]=g.city_road(0,true)
	var old_tile=Vector2i(94,99)
	g.cars=[{"path":PackedVector2Array([Vector2(old_tile)]),"step":0,"t":0.0,"dest":0,"ticket":91,"route_revision":-1}]
	g.ensure_city_accesses();g.rebuild_graph()
	assert(g.roads.size()<old_count*.7,"Migration removes the old dense auto-generated road mesh")
	assert(g.roads.has(connection))
	assert(not g.graph.get_point_path(g.point_id(connection),g.point_id(c.pos)).is_empty(),"Player connection retains a route into the city")
	assert(g.roads.has(g.traffic.position(g.cars[0])) and g.cars[0].ticket==91)
	for a in c.accesses:assert(g.city_connectors[a.gate]==0)
	before=g.roads.duplicate(true)
	g.ensure_city_accesses()
	assert(g.roads==before,"Migrated roads are stable on repeat synchronization")
	g.cars.clear()
	g.save_path="res://tests/city_layout_save.bin"
	g.save_game(false);g.load_game()
	assert(g.roads==before,"Saving/loading must not restore the discarded asphalt bands")
	assert(not g.graph.get_point_path(g.point_id(connection),g.point_id(c.pos)).is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.save_path))
	print("PASS: 160 seeded city plans, at most 40% roads, no 2×2 asphalt patches, 2–4 exits, stable growth/shrink, legacy cleanup, preserved player routes and relocated cars")
	g.free();quit()
