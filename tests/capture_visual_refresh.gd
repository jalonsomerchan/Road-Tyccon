extends SceneTree
var game
func _initialize() -> void: call_deferred("run")
func shot(name: String) -> void:
	game.queue_redraw()
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/"+name+".png")
func clear_world() -> void:
	game.roads.clear();game.road_nodes.clear();game.cities.clear();game.city_cells.clear();game.city_connectors.clear();game.cars.clear()
	game.incidents.reset();game.traffic.reset();game.maintenance.reset();game.demolished_access_tiles.clear()
	game.terrain.fill(0)
	game.notice_time = 0
	game.hover_cell = game.NO_CELL
func road(p: Vector2i,kind: int) -> void:
	game.roads[p] = {"kind":kind,"hp":100.0,"closed":false,"work":0.0,"total":1.0,"axis":true,"last_used":game.elapsed}
	game.road_nodes[p] = {"kind":kind,"axis":true}
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	root.size = Vector2i(1280,800)
	clear_world()
	for x in range(95,106): road(Vector2i(x,100),4)
	for y in range(100,105): road(Vector2i(100,y),4)
	game.rebuild_graph()
	game.camera = Vector2(100,101)
	game.cursor = Vector2i(106,105)
	game.tile = 72.0;game.zoom_target=72.0
	await shot("junction-v5")
	clear_world()
	for x in range(95,106): road(Vector2i(x,100),7)
	for y in range(96,105): road(Vector2i(100,y),7)
	game.rebuild_graph()
	game.camera = Vector2(100,100)
	await shot("junction-multilane-v5")
	clear_world()
	game.building_world=true
	var names = ["Villa del Sol","Los Abedules","Mirador","La Fundición"]
	for i in 4:
		game.add_city(Vector2i(100+(i%2)*19,100+int(i/2)*19),names[i],4)
		game.cities[i].design_style = i
	game.building_world=false
	game.rebuild_city_lookup();game.ensure_city_accesses()
	game.rebuild_graph()
	game.camera = Vector2(109.5,109.5)
	game.cursor = Vector2i(109,109)
	game.tile=18.0;game.zoom_target=18.0
	await shot("city-styles-v2")
	game.camera = Vector2(game.cities[0].pos)
	game.cursor = game.cities[0].accesses[0].end+Vector2i(1,2)
	game.tile=48.0;game.zoom_target=48.0
	await shot("city-detail-v2")
	# Real cars on a connected starter route, using all eight body sprites.
	clear_world()
	game.add_city(Vector2i(100,100),"Valverde",2)
	game.add_city(Vector2i(140,100),"Los Olmos",2)
	game.kind=3;game.tool=0;game.anchor=Vector2i(105,100);game.cursor=Vector2i(135,100)
	game.apply_action()
	game.incidents.rules.weather_enabled=false
	for i in 300:game._process(.1)
	game.notice_time=0;game.camera=Vector2(120,100);game.cursor=Vector2i(120,104)
	game.tile=24.0;game.zoom_target=24.0
	game.money_popups.clear()
	game.income_pulse=0
	await shot("starter-cities-v2")
	game.free()
	quit()
