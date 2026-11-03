extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	root.size=Vector2i(1280,800)
	game.roads.clear();game.road_nodes.clear();game.cities.clear();game.city_cells.clear();game.city_connectors.clear();game.cars.clear()
	game.incidents.reset();game.traffic.reset();game.terrain.fill(0)
	var cells: Dictionary = {}
	for x in range(96,105):cells[Vector2i(x,100)]=true
	for y in range(96,100):cells[Vector2i(100,y)]=true
	for x in range(108,117):cells[Vector2i(x,100)]=true
	for y in range(96,105):cells[Vector2i(112,y)]=true
	for y in range(103,106):cells[Vector2i(103,y)]=true
	for x in range(104,107):cells[Vector2i(x,105)]=true
	for p in cells:
		game.roads[p]={"kind":19,"hp":100.0,"closed":false,"work":0.0,"total":1.0,"axis":true,"last_used":game.elapsed}
		game.road_nodes[p]={"kind":19,"axis":true}
	game.rebuild_graph()
	game.camera=Vector2(106,100.5);game.cursor=Vector2i(106,104)
	game.tile=48.0;game.zoom_target=48.0;game.kind=19;game.notice_time=0
	game.queue_redraw()
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/residential-centered.png")
	game.free()
	quit()
