extends SceneTree
var g
func _initialize() -> void: call_deferred("run")
func frame() -> void:
	g.queue_redraw();await process_frame;await process_frame
func event_button(index: int, pressed: bool) -> void:
	var event=InputEventJoypadButton.new();event.device=0;event.button_index=index;event.pressed=pressed
	Input.parse_input_event(event)
	await frame()
func tap(index: int) -> void:
	await event_button(index,true);await event_button(index,false)
func axis(index: int, value: float) -> void:
	var event=InputEventJoypadMotion.new();event.device=0;event.axis=index;event.axis_value=value
	Input.parse_input_event(event);await frame()
func fresh_menu() -> void:
	g.close_panels();g.menu_focus.sync();await tap(JOY_BUTTON_START)
	assert(g.panel=="menu" and g.menu_focus.current=="cities")
func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false)
	g.save_path="res://tests/menu_runtime_save.bin";g.title_has_save=false
	g.menu_focus.sync("title:new")
	# Native _input events, without calling the game's handlers directly.
	await axis(JOY_AXIS_LEFT_Y,.18);assert(g.menu_focus.current=="title:new")
	await axis(JOY_AXIS_LEFT_Y,.85);assert(g.menu_focus.current=="title:quit")
	for i in 2: g.deck_input.update(.04)
	assert(g.menu_focus.current=="title:quit","No event+frame double movement")
	await axis(JOY_AXIS_LEFT_Y,0)
	await tap(JOY_BUTTON_DPAD_UP);assert(g.menu_focus.current=="title:new")
	await tap(JOY_BUTTON_DPAD_UP);assert(g.menu_focus.current=="play:mode")
	var mode: String = g.selected_mode
	await tap(JOY_BUTTON_A);assert(g.selected_mode!=mode)
	await tap(JOY_BUTTON_DPAD_DOWN);assert(g.menu_focus.current=="title:new")
	await tap(JOY_BUTTON_A);assert(not g.at_title and g.session_active)
	g.speed_index=0;g.incidents.rules.weather_enabled=false
	var place: Vector2i = g.cursor
	var move_alias=InputEventKey.new();move_alias.physical_keycode=KEY_A;move_alias.pressed=true
	Input.parse_input_event(move_alias);await frame();g._process(.1)
	assert(g.cursor==place and not g.deck_input.keyboard_down(KEY_A),"Emulated A must not also move the world cursor")
	move_alias.pressed=false;Input.parse_input_event(move_alias);await frame()
	g.save_game(false)
	# An A held across opening a confirmation cannot also confirm the next screen.
	g.at_title=true;g.title_has_save=true;g.title_index=0;g.menu_focus.sync("title:new")
	await event_button(JOY_BUTTON_A,true)
	assert(g.title_confirm_new and g.menu_focus.current=="title_cancel")
	var alias=InputEventKey.new();alias.physical_keycode=KEY_ENTER;alias.pressed=true
	Input.parse_input_event(alias);await frame()
	assert(g.title_confirm_new,"Steam Input's emulated Enter must not activate a second screen")
	var click_alias=InputEventMouseButton.new();click_alias.button_index=MOUSE_BUTTON_LEFT;click_alias.pressed=true;click_alias.position=Vector2(150,540)
	Input.parse_input_event(click_alias);await frame()
	assert(g.title_confirm_new,"An emulated click must not cancel the new-game confirmation")
	await event_button(JOY_BUTTON_A,true);assert(g.title_confirm_new)
	await tap(JOY_BUTTON_DPAD_LEFT);assert(g.title_confirm_accept)
	await event_button(JOY_BUTTON_A,true);assert(g.at_title and g.title_confirm_new)
	await event_button(JOY_BUTTON_A,false);await tap(JOY_BUTTON_A)
	assert(not g.at_title and not g.title_confirm_new)
	g.speed_index=0;g.incidents.rules.weather_enabled=false
	# Main grid: every item is reached by physical directional taps and activated.
	for i in g.MENU_ACTIONS.size():
		await fresh_menu()
		for row in int(i/2): await tap(JOY_BUTTON_DPAD_DOWN)
		if i%2: await tap(JOY_BUTTON_DPAD_RIGHT)
		assert(g.menu_focus.current==g.MENU_ACTIONS[i])
		await tap(JOY_BUTTON_A)
		if g.MENU_ACTIONS[i]=="cheats":
			assert(g.cheats.is_open())
			g.cheats.selection=0;g.cheats.buttons[0].grab_focus()
			var money: float = g.money
			await event_button(JOY_BUTTON_A,true)
			assert(g.money==money+100000,"A executes exactly once, before native GUI acceptance")
			await event_button(JOY_BUTTON_A,true)
			assert(g.money==money+100000,"Held A must not repeat the command")
			await event_button(JOY_BUTTON_A,false)
			var count: int = g.cheats.selection
			await tap(JOY_BUTTON_DPAD_DOWN);assert(g.cheats.selection==mini(count+2,g.cheats.buttons.size()))
			await tap(JOY_BUTTON_B);assert(not g.cheats.is_open())
		else: assert(g.panel==g.MENU_ACTIONS[i])
		await tap(JOY_BUTTON_B)
	await fresh_menu();await tap(JOY_BUTTON_A);assert(g.panel=="cities")
	await event_button(JOY_BUTTON_B,true);assert(g.panel=="menu")
	var cancel_alias=InputEventKey.new();cancel_alias.physical_keycode=KEY_ESCAPE;cancel_alias.pressed=true
	Input.parse_input_event(cancel_alias);await frame()
	assert(g.panel=="menu","One B must not also close the parent via emulated Escape")
	await event_button(JOY_BUTTON_B,false)
	await fresh_menu()
	var menu_alias=InputEventKey.new();menu_alias.physical_keycode=KEY_ESCAPE;menu_alias.pressed=true
	Input.parse_input_event(menu_alias);await frame()
	assert(g.panel=="menu","Native Menu plus emulated Escape must leave the menu open")
	menu_alias.pressed=false;Input.parse_input_event(menu_alias);await frame()
	await fresh_menu();await tap(JOY_BUTTON_DPAD_RIGHT)
	assert(g.menu_focus.current=="map")
	var arrow_alias=InputEventKey.new();arrow_alias.physical_keycode=KEY_RIGHT;arrow_alias.pressed=true
	Input.parse_input_event(arrow_alias);await frame()
	assert(g.menu_focus.current=="map","D-pad plus emulated arrow must navigate only once")
	arrow_alias.pressed=false;Input.parse_input_event(arrow_alias);await frame()
	# Passive/virtual mouse movement cannot steal the selected menu item.
	await fresh_menu();await tap(JOY_BUTTON_DPAD_DOWN)
	var selected: String = g.menu_focus.current
	var mouse=InputEventMouseMotion.new();mouse.position=Vector2(180,200);mouse.relative=Vector2(1,1)
	Input.parse_input_event(mouse);await frame()
	assert(g.last_pad and g.menu_focus.current==selected)
	# The stick repeats after a delay, does not wrap at the last row, and stops on release.
	g.menu_focus.pick("cities");await axis(JOY_AXIS_LEFT_Y,.9)
	assert(g.menu_focus.current=="stats")
	g.deck_input.update(.1);assert(g.menu_focus.current=="stats")
	g.deck_input.update(.25);assert(g.menu_focus.current=="objectives")
	await axis(JOY_AXIS_LEFT_Y,0);selected=g.menu_focus.current
	g.deck_input.update(1);assert(g.menu_focus.current==selected)
	# Footer actions and panels are active even before their first render.
	for action in ["save","load","help","speed","close"]:
		await fresh_menu();g.menu_focus.pick(action)
		assert(g.menu_focus.current==action)
		await tap(JOY_BUTTON_A)
		if action=="help": assert(g.panel=="help")
	for tab in 3:
		g.close_panels();g.gameplay_ui.tab=tab;g.open_panel("network")
		var entries=g.menu_focus.model()
		for item in entries:
			g.menu_focus.pick(item.action)
			assert(g.menu_focus.current==item.action)
		g.menu_focus.pick("play:tab:"+str(tab))
		await tap(JOY_BUTTON_RIGHT_SHOULDER)
		assert(g.gameplay_ui.tab==(tab+1)%3 and g.panel=="network")
		await tap(JOY_BUTTON_B)
	# Catalog, lists, information, help, infrastructure, signals, objectives and scenarios.
	g.close_panels();g.open_road_selector();g.construction_catalog.choose_tab(5)
	g.menu_focus.pick("catalog:item:roundabout");await tap(JOY_BUTTON_A)
	assert(g.construction_mode=="roundabout" and g.panel=="")
	g.open_road_selector();g.construction_catalog.choose_tab(2)
	g.menu_focus.pick("catalog:item:road:3");await tap(JOY_BUTTON_A);assert(g.panel=="" and g.kind==3 and g.construction_mode=="road")
	for panel in ["cities","accounts","stats","info","help","infrastructure","objectives","scenarios"]:
		g.close_panels();g.open_panel(panel)
		assert(not g.menu_focus.current.is_empty())
		await tap(JOY_BUTTON_B);assert(g.panel=="")
	g.roads[g.cursor]=g.city_road(3,true);g.install_signal();g.menu_focus.sync()
	var before: float = g.incidents.signals[g.cursor].ns
	await tap(JOY_BUTTON_DPAD_RIGHT);assert(g.incidents.signals[g.cursor].ns>before)
	await tap(JOY_BUTTON_DPAD_DOWN);await tap(JOY_BUTTON_DPAD_DOWN)
	await event_button(JOY_BUTTON_DPAD_RIGHT,true);g.deck_input.update(.5)
	assert(g.incidents.signals[g.cursor].enabled)
	await event_button(JOY_BUTTON_DPAD_RIGHT,false);await tap(JOY_BUTTON_DPAD_LEFT)
	assert(not g.incidents.signals[g.cursor].enabled)
	await tap(JOY_BUTTON_A);assert(g.incidents.signals[g.cursor].enabled)
	await tap(JOY_BUTTON_B)
	g.open_panel("scenarios");g.menu_focus.pick("play:scenario:budget");await tap(JOY_BUTTON_A)
	assert(g.menu_focus.current=="play:cancel_scenario")
	await tap(JOY_BUTTON_B);assert(g.panel=="scenarios" and g.gameplay_ui.pending_scenario.is_empty())
	await tap(JOY_BUTTON_B);assert(g.panel=="")
	# Minimum camera zoom survives saves and spans 256 times the former minimum area.
	g.set_zoom(0);assert(g.zoom_target==.5)
	g.tile=g.zoom_target;g.save_game(false);g.tile=32;assert(g.load_game())
	assert(g.tile==.5 and g.zoom_target==.5 and pow(8/g.tile,2)==256)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.save_path))
	print("PASS: native event dispatch, title/mode/confirmation, held A edge, stick drift/repeat/release, every main menu action, footer, all network tabs, remaining menus, signal adjustment, scenario cancel, and saved 256× regional camera coverage")
	g.free();quit()
