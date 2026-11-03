extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func put_road(game,p:Vector2i,hp:float=100.0) -> void:
	game.roads[p]={"kind":3,"hp":hp,"closed":false,"work":0.0,"total":1.0,"axis":false,"last_used":game.elapsed}
	game.road_nodes[p]={"kind":3,"axis":false}
func shot(path:String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(path)
func capture() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	root.size=Vector2i(1280,800)
	game.roads.clear()
	game.road_nodes.clear()
	game.cities.clear()
	game.city_cells.clear()
	game.city_connectors.clear()
	game.incidents.reset()
	game.traffic.reset()
	game.terrain.fill(0)
	game.money=80000
	game.elapsed=700
	game.tile=64
	game.zoom_target=64
	game.kind=3
	game.cursor=Vector2i(100,100)
	game.construction_mode="roundabout"
	game.apply_action()
	game.construction_mode="road"
	for p in game.roads:game.roads[p].work=0
	for p in [Vector2i(100,98),Vector2i(100,97),Vector2i(102,100),Vector2i(103,100),Vector2i(100,102),Vector2i(100,103),Vector2i(98,100),Vector2i(97,100)]:put_road(game,p)
	for x in range(105,111):put_road(game,Vector2i(x,99))
	game.incidents.snow_zone(Vector2i(104,98),2)
	game.incidents.ignite(Vector2i(105,99))
	game.incidents.fire[Vector2i(106,99)]=game.elapsed+60
	game.incidents.snow[Vector2i(105,99)]=game.elapsed+120
	game.roads[Vector2i(107,99)].hp=60
	game.roads[Vector2i(108,99)].hp=30
	game.roads[Vector2i(109,99)].hp=8
	game.roads[Vector2i(110,99)].closed=true
	put_road(game,Vector2i(109,101))
	game.roads[Vector2i(109,101)].last_used=game.elapsed-780
	game.cursor=Vector2i(103,100)
	game.install_signal()
	game.panel=""
	game.cursor=Vector2i(105,99)
	game.camera=Vector2(104,100)
	game.notice_time=0
	game.display_money=game.money
	game.rebuild_graph()
	game.queue_redraw()
	await shot("res://tests/incidents-preview.png")
	assert(game.visuals.tooltip_rect.has_area())
	var click=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	click.position=game.visuals.tooltip_rect.position+Vector2(10,10)
	var road_count=game.roads.size()
	game._unhandled_input(click)
	assert(game.roads.size()==road_count,"Clicking information must not build behind the bubble")
	game.cursor=Vector2i(103,100)
	game.panel="signal"
	game.queue_redraw()
	await shot("res://tests/signal-settings.png")
	game.panel="infrastructure"
	game.queue_redraw()
	await shot("res://tests/infrastructure.png")
	game.panel="menu"
	game.queue_redraw()
	await shot("res://tests/menu.png")
	game.free()
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.roads.clear()
	game.road_nodes.clear()
	game.cities.clear()
	game.city_cells.clear()
	game.city_connectors.clear()
	game.cars.clear()
	game.incidents.reset()
	game.traffic.reset()
	game.terrain.fill(0)
	game.incidents.rules.weather_enabled=false
	game.add_city(Vector2i(100,100),"Valverde",1)
	game.add_city(Vector2i(130,100),"Los Olmos",1)
	game.anchor=Vector2i(104,100)
	game.cursor=Vector2i(126,100)
	game.apply_action()
	for i in 400:game._process(0.1)
	game.cursor=Vector2i(115,100)
	game.tool=1
	game.apply_action()
	for i in 900:game._process(0.1)
	game.cursor=Vector2i(104,100)
	game.camera=Vector2(115,100)
	game.tile=32
	game.zoom_target=32
	game.notice_time=0
	game.display_money=game.money
	game.queue_redraw()
	await shot("res://tests/jam-preview.png")
	game.free()
	quit()
