extends SceneTree
var g
func _initialize() -> void: call_deferred("run")

func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false);g.hide()
	g.rebuild_graph();g.incidents.rules.weather_enabled=false
	g.visuals.terrain_cache=load("res://scripts/terrain_render_cache.gd").new(g)
	g.visuals.terrain_cache.index_roads();g.visuals.prepare_road_layout()
	# Discovery queues work; it never creates hundreds of cities in the input/draw path.
	var initial=g.cities.size()
	var target=Vector2(g.explored.bounds.end+Vector2i(32,32))
	g.explore_around(target,true)
	assert(g.cities.size()==initial and not g.world_stream.jobs.is_empty())
	var queued=g.world_stream.snapshot()
	g.world_stream.update(0)
	assert(g.world_stream.snapshot()==queued)
	g.world_stream.update(1500)
	assert(g.cities.size()>initial and not g.graph_dirty)
	# Pending work survives saving, so an explored region never loses its towns.
	g.save_path="/tmp/road-stream-%d.save"%OS.get_process_id()
	queued=g.world_stream.snapshot();var count=g.cities.size()
	g.save_game(false);assert(g.load_game())
	assert(g.cities.size()==count and g.world_stream.snapshot()==queued)
	g.visuals.terrain_cache.index_roads();g.visuals.prepare_road_layout()
	while not g.world_stream.jobs.is_empty(): g.world_stream.update(20000)
	assert(g.cities.size()>initial and not g.graph_dirty)
	for i in range(initial,g.cities.size()):
		var c=g.cities[i]
		assert(not c.accesses.is_empty() and g.graph.has_point(g.point_id(c.pos)))
		assert(g.traffic.current_links[i].is_empty())
		for j in range(i): assert(Vector2(c.pos).distance_to(Vector2(g.cities[j].pos))>=g.MIN_CITY_DISTANCE)
	# The cheap append path produces the same real streets and graph as a complete sync.
	var streets: Dictionary={}
	var edges: Dictionary={}
	for p in g.roads:
		streets[p]=g.roads[p].kind
		if g.graph.has_point(g.point_id(p)): edges[p]=g.graph.get_point_connections(g.point_id(p)).size()
	var cached_roads=g.visuals.terrain_cache.road_stamps.duplicate()
	var cached_cities=g.visuals.terrain_cache.city_stamps.duplicate()
	var shapes=g.visuals.node_shapes.duplicate(true)
	g.ensure_city_accesses();g.rebuild_graph()
	g.visuals.terrain_cache.index_roads();g.visuals.prepare_road_layout()
	assert(cached_roads==g.visuals.terrain_cache.road_stamps and cached_cities==g.visuals.terrain_cache.city_stamps)
	assert(shapes==g.visuals.node_shapes)
	assert(streets.size()==g.roads.size())
	for p in streets:
		assert(g.roads[p].kind==streets[p] and g.graph.get_point_connections(g.point_id(p)).size()==edges[p])
	DirAccess.remove_absolute(g.save_path)
	# Regional panning, overlays and graph changes reuse terrain, without filling detailed chunks.
	g.tile=.5;g.zoom_target=.5;g.camera=target
	var overview=g.visuals.overview
	var chunks=g.terrain.chunks.size()
	overview.update(1000000)
	assert(overview.texture!=null and overview.pending.is_empty())
	var built=overview.builds
	overview.update(1000000);assert(overview.builds==built)
	g.road_revision+=1;g.gameplay.overlay="condition";overview.update(1000000)
	assert(overview.builds==built and g.terrain.chunks.size()==chunks)
	var old_camera=g.camera
	g.camera+=Vector2(256,0);overview.update(1000000)
	assert(overview.builds-built<=10,"Panning only builds the new column, not the entire map")
	g.camera=old_camera;built=overview.builds;overview.update(1000000)
	assert(overview.builds==built)
	var edit=Vector2i(g.camera)
	g.terrain.set_cell(edit,1);overview.update(1000000)
	assert(overview.builds>built and overview.builds-built<=4,"Terrain edits invalidate only nearby mosaics")
	for x in range(1,8):
		g.explored.reveal(target+Vector2(x*2048,0),Vector2(1500,1000))
		g.camera=target+Vector2(x*2048,0);overview.update(1000000)
		assert(overview.tiles.size()<=overview.MAX_TILES)
	# Regional motion advances every frame and covers the same screen distance at every zoom.
	g.terrain.fill(0);g.world_stream.reset();g.speed_index=0;g.panel="";g.last_pad=false
	g.deck_input.stick=Vector2i.RIGHT
	var distances:Array=[]
	for zoom in [.5,2.0]:
		g.tile=zoom;g.zoom_target=zoom;g.cursor=Vector2i(8192,8192);g.camera=Vector2(g.cursor)
		g.regional_cursor_cell=g.NO_CELL;g.move_held=0
		var previous=g.cursor
		for i in 30:
			g._process(1.0/60)
			assert(g.cursor.x>previous.x,"Low zoom must not wait for key-repeat ticks")
			previous=g.cursor
		distances.append((g.cursor.x-8192)*zoom)
	assert(absf(distances[0]-distances[1])<=2 and distances[0]>130)
	g.deck_input.stick=Vector2i.ZERO
	# Spatial traffic indexing still enforces physical spacing along a congested segment.
	g.roads.clear();g.road_nodes.clear();g.city_cells.clear();g.city_connectors.clear();g.traffic.reset();g.incidents.reset();g.cars.clear()
	g.cities=[{"pos":Vector2i(100,100),"profile":0,"accesses":[],"name":"A","access_dirs":[Vector2i.RIGHT]},{"pos":Vector2i(104,100),"profile":0,"accesses":[],"name":"B","access_dirs":[Vector2i.LEFT]}]
	var path=PackedVector2Array()
	for x in range(100,105):
		var p=Vector2i(x,100);path.append(Vector2(p));g.roads[p]=g.city_road(3,true);g.road_nodes[p]={"kind":3,"axis":true}
	g.rebuild_graph()
	for i in 2:
		g.cars.append({"path":path,"step":0,"t":.8 if i==0 else 0.0,"ticket":i+1,"born":0,"origin":0,"dest":1,"ideal":5,"accident_clock":0,"crash_left":0,"route_revision":g.road_revision})
	g.cars[0].crash_left=10
	for i in 50: g.traffic.update(.02)
	assert(g.cars[1].step==0 and g.cars[1].t<=.8-g.traffic.FOLLOWING_GAP+.00001)
	print("PASS: budgeted discovery, resumable generation, incremental streets/graph equivalence, regional mosaic reuse/local edits/bounded memory, smooth zoom-independent motion and indexed traffic gaps")
	g.free();quit()
