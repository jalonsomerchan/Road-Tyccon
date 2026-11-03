extends SceneTree
var game
func _initialize() -> void: call_deferred("run")
func shot(name: String) -> void:
	if game.graph_dirty: game.rebuild_graph()
	game.queue_redraw()
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/"+name+".png")
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	root.size = Vector2i(1280,800)
	game.notice_time = 0
	game.cursor += Vector2i(3,0)
	game.anchor = game.cursor
	game.cursor += Vector2i(7,3)
	game.camera = Vector2(game.cursor)-Vector2(3,0)
	game.last_pad = true
	await shot("toolbar")
	game.last_pad=false
	await shot("toolbar-keyboard")
	for i in range(1,5):
		game.select_tool(i)
		await shot("toolbar-"+game.TOOLS[i].icon)
	game.ui_action("toolbar:roundabout")
	await shot("toolbar-roundabout")
	assert(game.tool==0 and game.construction_mode=="roundabout")
	game.ui_action("toolbar:roundabout")
	assert(game.construction_mode=="road")
	game.ui_action("toolbar:signal")
	await shot("toolbar-signal")
	assert(game.construction_mode=="signal")
	game.ui_action("toolbar:signal")
	assert(game.construction_mode=="road")
	game.kind=9
	await shot("toolbar-long-name")
	game.kind=0

	game.open_menu()
	await shot("menu-toolbar")
	game.ui_action("cities")
	await shot("cities-toolbar")
	game.back_panel()
	game.ui_action("map")
	for i in 12: game.navigator.update(0.2)
	await shot("map-toolbar")
	game.back_panel()
	game.ui_action("stats")
	await shot("stats-toolbar")
	game.transact(-2400,"construction","Construir carretera · 30 casillas")
	game.transact(-20,"logging","Tala de árboles")
	game.transact(-100,"accidents","Accidente de tráfico")
	game.transact(-50,"demolition","Demolición de carretera")
	game.transact(-200,"repairs","Arreglar vía · 4 casillas")
	game.transact(240,"trips","Viaje completado")
	game.back_panel()
	game.ui_action("accounts")
	await shot("accounts-toolbar")
	game.close_panels()
	game.open_road_selector()
	await shot("catalog-toolbar")
	game.close_panels()
	# Click real hit regions: tools never build behind the dock.
	await shot("toolbar-clicks")
	for i in 5:
		var click=InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
		for hit in game.ui_hits:
			if hit.action=="tool:"+str(i): click.position=hit.rect.get_center();break
		game._unhandled_input(click)
		assert(game.tool==i)
		await shot("toolbar-click-"+str(i))
	var before: Vector2i = game.cursor
	var click=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=Vector2(50,780)
	game._unhandled_input(click)
	assert(game.cursor==before)
	game.select_tool(0);game.anchor=Vector2i(400,400)
	var kept_anchor: Vector2i = game.anchor
	game.ui_action("toolbar:upgrade")
	assert(game.anchor==kept_anchor,"An unavailable action must not cancel a construction plan")
	# The new shortcuts perform their actual actions and reflect availability.
	game.roads.clear();game.road_nodes.clear();game.cities.clear();game.city_cells.clear();game.city_connectors.clear()
	game.traffic.reset();game.cars.clear();game.services.reset();game.incidents.reset();game.terrain.fill(0)
	game.select_tool(0);game.kind=0;game.anchor=Vector2i(300,300);game.cursor=Vector2i(302,300)
	var funds: float = game.money
	game.apply_action()
	assert(game.services.can_undo())
	await shot("toolbar-undo-ready")
	game.ui_action("toolbar:undo")
	assert(game.money==funds and not game.roads.has(game.cursor))
	game.anchor=Vector2i(300,300);game.apply_action()
	for p in game.roads: game.roads[p].work=0;game.roads[p].closed=true
	game.kind=4
	assert(game.visuals.toolbar.can_upgrade())
	await shot("toolbar-upgrade-ready")
	game.ui_action("toolbar:upgrade")
	assert(game.roads[game.cursor].kind==4 and game.roads[game.cursor].work>0)
	game.select_tool(1)
	await shot("toolbar-open")
	for icon in game.visuals.toolbar.ICONS: assert(game.visuals.toolbar.textures[icon]!=null)
	print("PASS: vector toolbar icons, all selected states, long road labels, keyboard/gamepad hints, clickable tools, dock shielding, mode toggles, undo/refund, upgrade availability and open/close icon")
	game.free()
	quit()
