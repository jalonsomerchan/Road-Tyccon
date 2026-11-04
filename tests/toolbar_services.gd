extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var g=load("res://scenes/main.tscn").instantiate()
	root.add_child(g);g.set_process(false)
	g.select_tool(6)
	g.deck_input.button(JOY_BUTTON_RIGHT_SHOULDER)
	assert(g.TOOLS[g.tool].id=="upgrade_road")
	g.deck_input.button(JOY_BUTTON_RIGHT_SHOULDER)
	assert(g.TOOLS[g.tool].id=="open_services")
	g.deck_input.button(JOY_BUTTON_A)
	assert(g.panel=="network" and g.gameplay_ui.tab==0)
	g.deck_input.button(JOY_BUTTON_B)
	assert(g.panel=="" and g.TOOLS[g.tool].id=="open_services")
	g.deck_input.button(JOY_BUTTON_RIGHT_SHOULDER)
	assert(g.TOOLS[g.tool].id=="build_road")
	g.construction_mode="sign:stop"
	var heading=g.signage.heading
	g.deck_input.button(JOY_BUTTON_X)
	assert(g.signage.heading==(heading+1)%4)
	g.construction_mode="signal"
	var horizontal=g.horizontal
	g.deck_input.button(JOY_BUTTON_X)
	assert(g.horizontal==horizontal and g.notice.contains("ambos ejes"))
	g.open_menu();assert(g.TOOLS[g.tool].id=="menu")
	g.close_panels()
	print("PASS: Deck cycles through upgrade and services; X rotates signs; signals cover both axes")
	quit()
