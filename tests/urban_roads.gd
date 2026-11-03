extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.roads.clear();game.road_nodes.clear();game.cities.clear();game.city_cells.clear();game.city_connectors.clear()
	game.traffic.reset();game.cars.clear();game.incidents.reset();game.terrain.fill(0)
	game.incidents.rules.weather_enabled=false
	game.incidents.rules.abandon_enabled=false
	game.building_world=true
	for style in 4:
		for radius in range(1,6):
			game.add_city(Vector2i(100+radius*30,100+style*30),"Barrio",radius)
			game.cities.back().design_style=style
	game.building_world=false
	game.rebuild_city_lookup();game.ensure_city_accesses();game.rebuild_graph()
	var buildings=0
	for i in game.cities.size():
		var city=game.cities[i]
		for y in range(-city.radius,city.radius+1):
			for x in range(-city.radius,city.radius+1):
				var p=city.pos+Vector2i(x,y)
				var plan=game.CityDesign.cell(city,Vector2i(x,y))
				if plan.role=="street":
					assert(game.roads[p].kind in [19,20])
					assert(not game.graph.get_point_path(game.point_id(p),game.point_id(city.pos)).is_empty(),"Every urban street reaches the city centre")
				else:
					assert(not game.graph.has_point(game.point_id(p)),"Buildings and parks are not drivable")
				if plan.role in ["building","civic"]:
					buildings+=1
					var adjacent=false
					for d in game.DIRS:
						if game.roads.has(p+d) and game.roads[p+d].kind in [19,20]: adjacent=true
					assert(adjacent,"Every building has an orthogonally adjacent residential street or avenue")
		for access in city.accesses:
			assert(game.city_connectors[access.gate]==i)
			assert(game.roads.has(access.gate-access.dir))
			assert(game.edge_allowed(access.gate,access.gate-access.dir))
			assert(game.incidents.protected_access(access.end))
	assert(buildings>50)
	# A player-built street exit is discovered from the actual road network.
	var city=game.cities[0]
	var edge=city.pos+Vector2i(1,1)
	var gate=edge+Vector2i.RIGHT
	game.roads[edge]=game.city_road(19,true)
	game.roads[gate]=game.city_road(0,true)
	game.rebuild_graph()
	assert(game.city_connectors[gate]==0)
	# Closing a real city street prevents traffic through it.
	var target=city.pos
	game.roads[target].closed=true;game.rebuild_graph()
	assert(not game.graph.has_point(game.point_id(target)))
	game.roads[target].closed=false;game.rebuild_graph()
	assert(game.graph.has_point(game.point_id(target)))
	# Connect two towns: all driven cells, including inside towns, are roads.
	var start=game.cities[0].pos
	var dest=game.cities[5].pos
	for y in range(start.y,dest.y+1):
		var p=Vector2i(start.x,y)
		if not game.roads.has(p):game.roads[p]=game.city_road(19,false)
	game.rebuild_graph();game.spawn_trips()
	var saw_urban=false
	for tick in 400:
		game.elapsed+=.1;game.update_cars(.1)
		for car in game.cars:
			var p=game.traffic.position(car)
			assert(game.roads.has(p))
			if game.city_at(p)>=0:saw_urban=true
	assert(game.trips>0 and saw_urban)
	# Old saves with a car on an old decorative building move it onto a street.
	var old=game.cities[1].pos+Vector2i(1,1)
	game.traffic.restore({"vehicles":[{"pos":old,"dest":0,"origin":1,"ticket":999,"born":0.0,"ideal":10.0,"age":0.0,"color":2,"accident_clock":0.0}]})
	assert(game.roads.has(game.traffic.position(game.cars[0])) and game.cars[0].dest==0 and game.cars[0].ticket==999)
	# Save/reload preserves roads, connector registry and deliberate demolition.
	game.save_path="res://tests/urban_save.bin"
	var destroyed=game.cities[1].pos+Vector2i(1,0)
	game.cursor=destroyed;game.maintenance.demolition(destroyed);game.maintenance.update(5.1)
	assert(not game.roads.has(destroyed))
	game.save_game(false);game.load_game()
	assert(not game.roads.has(destroyed))
	assert(game.city_connectors.has(gate))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	print("PASS: 20 urban plans, buildings beside real streets, connected road graph, every exit is a connector, closures, urban traffic, legacy vehicle migration and persistent demolition")
	game.free();quit()
