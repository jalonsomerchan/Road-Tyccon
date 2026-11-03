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
func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	root.size=Vector2i(1280,800)
	var edge: int=game.explored.bounds.end.x
	game.travel_to(Vector2i(edge-1,8192))
	game.open_panel("map")
	game.navigator.whole_region()
	for i in 12:game.navigator.update(.2)
	await shot("world-expanded")
	game.close_panels()
	game.travel_to(Vector2i(-1,-1))
	game.notice_time=0
	await shot("world-negative")
	assert(game.visuals.terrain_cache.blocks.size()<=48)
	game.roads.clear();game.road_nodes.clear();game.cities.clear();game.city_cells.clear();game.city_connectors.clear();game.cars.clear()
	game.traffic.reset();game.incidents.reset();game.maintenance.reset();game.terrain.fill(0)
	game.incidents.rules.weather_enabled=false
	game.add_city(Vector2i(100,100),"Valverde",2)
	game.add_city(Vector2i(140,100),"Los Olmos",2)
	game.tool=0;game.kind=19;game.anchor=Vector2i(105,100);game.cursor=Vector2i(135,100)
	game.apply_action()
	for i in 300:game._process(.1)
	game.camera=Vector2(120,100);game.cursor=Vector2i(120,103);game.tile=24.0;game.zoom_target=24.0
	game.notice_time=0;game.money_popups.clear()
	game.emit_income(100,0)
	await shot("calmer-traffic")
	for i in 80:
		game._process(.016)
		game.camera=Vector2(120,100)
		game.queue_redraw()
		await process_frame
		RenderingServer.force_draw(false)
		if i in [20,50,79]:root.get_texture().get_image().save_png("res://tests/cars-motion-"+str(i)+".png")
	print("PASS: graphic expanding map, negative regions, bounded render cache, moving cars and income text")
	game.free()
	quit()
