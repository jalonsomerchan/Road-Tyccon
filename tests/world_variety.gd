extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false);g.hide()
	assert(g.cities[0].radius==g.WorldSettings.START_CITY_RADIUS and g.cities[0].radius==4)
	var sizes:Dictionary={};var variants:Dictionary={};var total=0
	for i in range(2,g.cities.size()):
		var city=g.cities[i]
		assert(city.radius==g.CityDesign.initial_radius(city.pos,g.world_seed))
		sizes[city.radius]=true;variants[city.design_variant]=true;total+=city.radius
	assert(sizes.size()==3 and variants.size()==4 and total/float(g.cities.size()-2)>2.5)
	var layouts:Dictionary={}
	var city={"radius":4,"design_style":0,"design_seed":123,"access_dirs":[Vector2i.RIGHT]}
	for variant in 4:
		city.design_variant=variant
		var roads:Array=[]
		for y in range(-4,5):
			for x in range(-4,5):
				if g.CityDesign.is_street(city,Vector2i(x,y)): roads.append(Vector2i(x,y))
		layouts[hash(roads)]=true
	assert(layouts.size()==4,"One architectural style can have four distinct street plans")
	var terrain=g.World.new();terrain.reset(42193)
	terrain.parameters.river_x_half_width=0;terrain.parameters.river_y_half_width=0
	var centers:Array=[]
	for y in range(-3,4):
		for x in range(-3,4):
			var basin=terrain.lake_basin(Vector2i(x,y))
			if basin.is_empty(): continue
			var center=Vector2i(basin.center.round());centers.append(center)
			assert(terrain.sample_cell(center)==1 and terrain.get_cell(center)==1)
			var outside=Vector2i((basin.center+Vector2(basin.radius.x*1.8,0)).round())
			assert(terrain.sample_cell(outside)!=1)
			for offset in [Vector2i(-10,-7),Vector2i(10,7),Vector2i(0,30)]:
				assert(terrain.sample_cell(center+offset)==terrain.get_cell(center+offset))
	assert(centers.size()>10 and terrain.chunks.size()<=terrain.MAX_CACHED_CHUNKS)
	var data=terrain.snapshot();var clone=g.World.new();clone.restore(data)
	for center in centers: assert(clone.sample_cell(center)==1)
	# Lake water enforces the same construction rule as rivers: only bridges can cross it.
	var crossing:Vector2i=centers[0]
	g.explored.reveal(Vector2(crossing),Vector2.ONE)
	g.cursor=crossing;g.anchor=g.NO_CELL;g.kind=0
	var funds:float=g.money
	g.apply_road_operation(0)
	assert(not g.roads.has(crossing) and g.money==funds)
	g.kind=10;g.apply_road_operation(0)
	assert(g.roads.has(crossing) and g.roads[crossing].kind==10 and g.money==funds-g.Catalog.ROADS[10].cost)
	# Legacy explored terrain stays byte-for-byte identical; lakes appear on its frontier.
	var old=g.World.new();old.restore({"seed":42193})
	var known:Dictionary={}
	var preserved:Dictionary={}
	var center:Vector2i=centers[0]
	known[g.Extent.key_for(center)]=true
	for y in range(-20,21):
		for x in range(-20,21):
			var p=center+Vector2i(x,y);preserved[p]=old.sample_cell(p)
	old.enable_frontier_lakes(known)
	for p in preserved: assert(old.sample_cell(p)==preserved[p])
	var new_lakes=0
	for p in centers:
		if not known.has(g.Extent.key_for(p)) and old.sample_cell(p)==1: new_lakes+=1
	assert(new_lakes>5)
	clone.restore(old.snapshot());assert(clone.legacy_dry_regions==known)
	for p in preserved: assert(clone.sample_cell(p)==preserved[p])
	print("PASS: larger varied cities, deterministic radii, four urban variants, irregular independent lakes, chunk/sample agreement at negative coordinates, saved terrain and protected legacy regions with frontier lakes")
	g.free();quit()
