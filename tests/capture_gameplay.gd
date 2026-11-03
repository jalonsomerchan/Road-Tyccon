extends SceneTree
var g
func _initialize() -> void: call_deferred("run")
func shot(name: String) -> void:
	g.queue_redraw()
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/gameplay-"+name+".png")
func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false)
	root.size=Vector2i(1280,800)
	await shot("title")
	g.start_new_session()
	g.anchor=g.cities[0].accesses[0].end;g.cursor=g.cities[1].accesses[0].end;g.kind=3;g.apply_road_operation(0)
	g.incidents.rules.weather_enabled=false
	for i in 700: g._process(.1)
	g.cursor=g.cities[0].accesses[0].end+Vector2i(8,0);g.camera=Vector2(g.cursor)
	g.services.select_segment(g.cursor);g.gameplay.overlay="traffic"
	await shot("world")
	g.open_menu();await shot("menu")
	g.open_panel("objectives");await shot("objectives")
	# Test keyboard/controller focus against the actual rendered action list.
	g.gameplay_ui.focus_index=0;g.panel_accept()
	assert(g.gameplay.reputation==20 and g.gameplay.tier==1)
	g.panel_move(0,1);assert(g.gameplay_ui.focus_index==1)
	g.open_panel("network");g.gameplay_ui.tab=0;await shot("services")
	g.gameplay_ui.tab=1;g.gameplay.select_car_at(g.cursor);await shot("traffic")
	g.gameplay_ui.tab=2;await shot("economy")
	g.open_panel("scenarios");await shot("scenarios")
	g.gameplay_ui.action("play:scenario:winter");await shot("scenario-confirm")
	g.open_panel("catalog");await shot("catalog")
	g.open_panel("cities");await shot("cities")
	g.open_panel("accounts");await shot("accounts")
	print("PASS: title/mode selector, objectives and controller focus, expanded menu, world overlays, services, car inspection, economy, scenario confirmation, locked catalog, profiles and ledger rendered")
	g.free();quit()
