extends SceneTree
var g
func _initialize() -> void: call_deferred("run")
func button(index:int,down:bool) -> void:
	var event=InputEventJoypadButton.new();event.device=0;event.button_index=index;event.pressed=down
	Input.parse_input_event(event);await process_frame;await process_frame
func tap(index:int) -> void:
	await button(index,true);await button(index,false)
func axis(index:int,value:float) -> void:
	var event=InputEventJoypadMotion.new();event.device=0;event.axis=index;event.axis_value=value
	Input.parse_input_event(event);await process_frame;await process_frame
func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false)
	g.gameplay.mode="progression";g.gameplay.tier=0;g.kind=0;g.construction_mode="road"
	g.event_notices.reset()
	await tap(JOY_BUTTON_Y)
	assert(g.panel=="catalog" and g.construction_catalog.tab==0)
	for id in g.construction_catalog.entries(): assert(g.construction_catalog.allowed(id))
	assert(g.construction_catalog.entries().slice(0,2)==["signal","roundabout"])
	# Native D-pad/A selects the signal directly, then A installs it on a real street.
	await tap(JOY_BUTTON_DPAD_UP)
	assert(g.construction_catalog.selected=="signal" and g.kind==0)
	await tap(JOY_BUTTON_A)
	assert(g.panel=="" and g.construction_mode=="signal")
	await tap(JOY_BUTTON_A)
	assert(g.panel=="signal" and g.incidents.signals.has(g.cursor))
	await tap(JOY_BUTTON_B)
	assert(g.panel=="")
	# Roundabouts have their own selection and material control, with no road-card detour.
	await tap(JOY_BUTTON_Y);assert(g.construction_catalog.tab==5)
	await tap(JOY_BUTTON_DPAD_RIGHT);assert(g.construction_catalog.selected=="roundabout")
	await tap(JOY_BUTTON_X);assert(g.construction_catalog.base_kind==3 and g.kind==0)
	await tap(JOY_BUTTON_A);assert(g.construction_mode=="roundabout" and g.kind==3 and g.panel=="")
	g.terrain.fill(0);g.cursor=Vector2i(300,300)
	var funds:float=g.money
	await tap(JOY_BUTTON_A)
	assert(g.incidents.roundabouts.has(g.cursor) and g.money==funds-g.Catalog.ROADS[3].cost*9)
	# Locked roads can be inspected, but A cannot choose them or change the tool.
	await tap(JOY_BUTTON_Y);await tap(JOY_BUTTON_LEFT_SHOULDER)
	assert(g.construction_catalog.tab==4 and g.panel=="catalog")
	await tap(JOY_BUTTON_DPAD_RIGHT)
	assert(g.construction_catalog.selected=="road:11" and not g.construction_catalog.allowed("road:11"))
	await tap(JOY_BUTTON_A);assert(g.panel=="catalog" and g.kind==3)
	await tap(JOY_BUTTON_B);assert(g.panel=="" and g.construction_mode=="roundabout")
	# Every category sorts usable roads first, and no road disappears between categories.
	g.open_road_selector()
	var kinds:Dictionary={}
	for tab in range(1,5):
		g.construction_catalog.choose_tab(tab)
		var locked=false
		for id in g.construction_catalog.entries():
			if not g.construction_catalog.allowed(id): locked=true
			else: assert(not locked)
			assert(not kinds.has(id));kinds[id]=true
	assert(kinds.size()==24)
	# Trigger pages use a press/release latch; holding one never runs through the list.
	g.close_panels();g.gameplay.mode="free";g.kind=0;g.construction_mode="road"
	await tap(JOY_BUTTON_Y)
	await axis(JOY_AXIS_TRIGGER_RIGHT,1);assert(g.construction_catalog.page==1)
	await axis(JOY_AXIS_TRIGGER_RIGHT,.9);assert(g.construction_catalog.page==1)
	await axis(JOY_AXIS_TRIGGER_RIGHT,.4);await axis(JOY_AXIS_TRIGGER_RIGHT,.9);assert(g.construction_catalog.page==1)
	await axis(JOY_AXIS_TRIGGER_RIGHT,0);await axis(JOY_AXIS_TRIGGER_RIGHT,1);assert(g.construction_catalog.page==2)
	await axis(JOY_AXIS_TRIGGER_RIGHT,0);await axis(JOY_AXIS_TRIGGER_LEFT,1);assert(g.construction_catalog.page==1)
	await axis(JOY_AXIS_TRIGGER_LEFT,0)
	await tap(JOY_BUTTON_B);assert(g.kind==0 and g.construction_mode=="road")
	# Mouse preview and cancel keep the previously chosen type intact.
	g.open_road_selector();g.construction_catalog.choose_tab(1);g.last_pad=false
	g.ui_action("catalog:item:road:16")
	assert(g.construction_catalog.selected=="road:16" and g.kind==0 and g.panel=="catalog")
	g.cancel_or_back();assert(g.kind==0)
	print("PASS: six catalog tabs, unlocked-first order, 24 road types, native Deck signal/roundabout placement, material choice, locked previews, trigger latching and cancellation without changing the selected road")
	g.free();quit()
