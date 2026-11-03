extends SceneTree
var g
func _initialize() -> void: call_deferred("run")
func press(button: int) -> void:
	var event=InputEventJoypadButton.new();event.button_index=button;event.pressed=true
	g._unhandled_input(event)
	if event is InputEventJoypadButton:
		event.pressed=false
		g._unhandled_input(event)
func key(code: int) -> void:
	var event=InputEventKey.new();event.physical_keycode=code;event.pressed=true
	g._unhandled_input(event)
func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false)
	g.incidents.rules.weather_enabled=false;g.incidents.rules.abandon_enabled=false
	g.save_path="res://tests/steam_deck_save.bin"
	var cursor: Vector2i = g.cursor
	var funds: float = g.money
	for i in 12: press(JOY_BUTTON_B)
	assert(g.panel=="" and g.cursor==cursor and g.money==funds,"Idle B must never open a menu or perform an action")
	key(KEY_ESCAPE);key(KEY_B)
	var mouse=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_RIGHT;mouse.pressed=true
	g._unhandled_input(mouse);assert(g.panel=="")
	for i in 50:
		press(JOY_BUTTON_RIGHT_SHOULDER)
		assert(g.panel=="" and g.tool in range(5))
	for i in 50:
		press(JOY_BUTTON_LEFT_SHOULDER)
		assert(g.panel=="" and g.tool in range(5))
	for i in 12: key(KEY_TAB);key(KEY_Q);assert(g.panel=="" and g.tool in range(5))
	# B cancels only the active operation, without changing location or spending funds.
	g.anchor=cursor+Vector2i(5,0);g.construction_mode="roundabout"
	press(JOY_BUTTON_B);assert(g.anchor==g.NO_CELL and g.construction_mode=="roundabout" and g.panel=="")
	press(JOY_BUTTON_B);assert(g.construction_mode=="road" and g.panel=="")
	press(JOY_BUTTON_B);assert(g.panel=="" and g.money==funds and g.cursor==cursor)
	# Only the dedicated Menu button opens the main menu during ordinary play.
	g.select_tool(2);press(JOY_BUTTON_START);assert(g.panel=="menu")
	for button in [JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_UP]:
		press(button);assert(g.panel=="menu")
	g.menu_focus.pick("cities");press(JOY_BUTTON_A);assert(g.panel=="cities")
	press(JOY_BUTTON_RIGHT_SHOULDER);assert(g.panel=="cities" and g.city_list_index==6)
	press(JOY_BUTTON_B);assert(g.panel=="menu")
	press(JOY_BUTTON_B);assert(g.panel=="" and g.tool==2)
	press(JOY_BUTTON_B);assert(g.panel=="")
	press(JOY_BUTTON_START);press(JOY_BUTTON_START);assert(g.panel=="" and g.tool==2)
	# View controls the map, and B closes it rather than opening another screen.
	press(JOY_BUTTON_BACK);assert(g.panel=="map")
	press(JOY_BUTTON_LEFT_SHOULDER);assert(g.panel=="map")
	press(JOY_BUTTON_BACK);assert(g.panel=="")
	press(JOY_BUTTON_BACK);press(JOY_BUTTON_B);assert(g.panel=="")
	press(JOY_BUTTON_BACK);press(JOY_BUTTON_START);assert(g.panel=="menu")
	press(JOY_BUTTON_START);assert(g.panel=="")
	# L3 is always pause/resume, including inside menus, and restores the prior speed.
	var zoom: float = g.zoom_target
	g.speed_index=3;press(JOY_BUTTON_LEFT_STICK);assert(g.speed_index==0 and g.panel=="")
	g.save_game(false);g.pause_speed_index=1;assert(g.load_game())
	press(JOY_BUTTON_LEFT_STICK);assert(g.speed_index==3 and g.zoom_target==zoom)
	press(JOY_BUTTON_START);press(JOY_BUTTON_LEFT_STICK)
	assert(g.panel=="menu" and g.speed_index==0 and not g.cheats.is_open())
	press(JOY_BUTTON_LEFT_STICK);assert(g.speed_index==3 and g.panel=="menu")
	# The console remains reachable with A through an explicit menu selection.
	g.menu_focus.pick("cheats");press(JOY_BUTTON_A);assert(g.cheats.is_open())
	var back=InputEventJoypadButton.new();back.button_index=JOY_BUTTON_B;back.pressed=true
	g.cheats._input(back);back.pressed=false;g._unhandled_input(back);assert(not g.cheats.is_open() and g.panel=="menu")
	press(JOY_BUTTON_B);assert(g.panel=="")
	# Y consistently opens the catalog; bumpers stay within its columns.
	for tool in range(5):
		g.select_tool(tool);press(JOY_BUTTON_Y);assert(g.panel=="catalog" and g.tool==0)
		press(JOY_BUTTON_RIGHT_SHOULDER);assert(g.panel=="catalog")
		press(JOY_BUTTON_B);assert(g.panel=="")
	g.open_panel("network");g.gameplay_ui.tab=0
	press(JOY_BUTTON_RIGHT_SHOULDER);assert(g.panel=="network" and g.gameplay_ui.tab==1)
	press(JOY_BUTTON_LEFT_SHOULDER);assert(g.gameplay_ui.tab==0)
	press(JOY_BUTTON_B);assert(g.panel=="")
	g.open_panel("accounts");var filter: int = g.account_filter
	press(JOY_BUTTON_RIGHT_SHOULDER);assert(g.panel=="accounts" and g.account_filter==(filter+1)%3)
	press(JOY_BUTTON_B)
	# Right-stick drift cannot consume the menu-navigation repeat timer.
	press(JOY_BUTTON_START);var selection: int = g.menu_index;g.ui_move_clock=0
	var axis=InputEventJoypadMotion.new();axis.axis=JOY_AXIS_RIGHT_X;axis.axis_value=.9
	g._unhandled_input(axis);assert(g.menu_index==selection and g.ui_move_clock==0)
	press(JOY_BUTTON_START)
	for button in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_RIGHT_STICK]:
		press(button);assert(g.panel=="")
	# Event B still dismisses only the notice, preserving the current menu.
	g.open_menu();g.incidents.ignite(g.cursor);press(JOY_BUTTON_B)
	assert(g.panel=="menu" and g.event_notices.pending.is_empty())
	press(JOY_BUTTON_B);assert(g.panel=="")
	key(KEY_F10);assert(g.panel=="menu");key(KEY_F10);assert(g.panel=="")
	key(KEY_6);assert(g.panel=="menu");key(KEY_ESCAPE);assert(g.panel=="")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.save_path))
	print("PASS: idle B/cancel-only controls, 100 bumper presses without menus, dedicated Menu/View, panel-scoped bumpers, L3 pause/resume and persistence, explicit cheats, catalog from every tool, stick filtering and event dismissal")
	g.free();quit()
