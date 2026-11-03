extends SceneTree
func _initialize() -> void: call_deferred("run")
func press(game, index: int) -> void:
	var event = InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = true
	game._unhandled_input(event)
	if event is InputEventJoypadButton:
		event.pressed=false
		game._unhandled_input(event)
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	assert(game.TOOLS.size()==6)
	assert(game.MENU_ACTIONS==["cities","map","stats","accounts","objectives","network","scenarios","cheats"])
	for i in range(1,5):
		press(game,JOY_BUTTON_RIGHT_SHOULDER)
		assert(game.tool==i and game.panel=="")
	press(game,JOY_BUTTON_RIGHT_SHOULDER)
	assert(game.tool==0 and game.panel=="")
	press(game,JOY_BUTTON_LEFT_SHOULDER)
	assert(game.tool==4 and game.panel=="")
	press(game,JOY_BUTTON_START)
	assert(game.panel=="menu")
	press(game,JOY_BUTTON_B)
	assert(game.tool==4 and game.panel=="")
	game.select_tool(0)
	var old_zoom: float = game.zoom_target
	var old_kind: int = game.kind
	var trigger = InputEventJoypadMotion.new()
	trigger.axis=JOY_AXIS_TRIGGER_RIGHT;trigger.axis_value=1
	game._unhandled_input(trigger);game.deck_input.update(.1)
	assert(game.zoom_target>old_zoom and game.kind==old_kind)
	trigger.axis=JOY_AXIS_TRIGGER_RIGHT;trigger.axis_value=0;game._unhandled_input(trigger)
	trigger.axis=JOY_AXIS_TRIGGER_LEFT;trigger.axis_value=1;game._unhandled_input(trigger);game.deck_input.update(.1)
	assert(is_equal_approx(game.zoom_target,old_zoom))
	trigger.axis_value=0;game._unhandled_input(trigger)
	press(game,JOY_BUTTON_Y)
	assert(game.panel=="catalog")
	press(game,JOY_BUTTON_DPAD_DOWN)
	assert(game.kind==old_kind+1)
	press(game,JOY_BUTTON_A)
	assert(game.panel=="" and game.tool==0)
	# First action selects an endpoint, repeat at same point never spends money.
	game.terrain.fill(0)
	game.cursor = Vector2i(300,300)
	var before: float = game.money
	press(game,JOY_BUTTON_A)
	press(game,JOY_BUTTON_A)
	assert(game.anchor==game.cursor and game.money==before and not game.roads.has(game.cursor))
	game.cursor += Vector2i(4,0)
	press(game,JOY_BUTTON_A)
	assert(game.anchor==game.NO_CELL and game.roads.has(game.cursor))
	assert(game.money==before-5*game.Catalog.ROADS[game.kind].cost)
	for i in 200: game._process(0.1)
	game.incidents.rules.weather_enabled = false
	game.incidents.rules.abandon_enabled = false
	# One close tool toggles state; repair and demolish reject unfinished work.
	game.select_tool(1)
	press(game,JOY_BUTTON_A)
	assert(game.roads[game.cursor].closed)
	press(game,JOY_BUTTON_A)
	assert(not game.roads[game.cursor].closed)
	# A real vehicle on the demolished tile retains its position and destination.
	var pos: Vector2i = game.cursor
	var driver = {"path":PackedVector2Array([Vector2(pos),Vector2(pos+Vector2i.LEFT)]),"step":0,"t":0.0,"age":0.0,"born":game.elapsed,"origin":0,"dest":1,"color":0,"ideal":10.0,"accident_clock":0.0,"crash_left":0.0,"route_revision":game.road_revision,"blocked":false,"ticket":999}
	game.cars = [driver]
	game.select_tool(3)
	before = game.money
	press(game,JOY_BUTTON_A)
	assert(game.money==before-game.Catalog.ROADS[game.kind].cost*0.25)
	assert(game.roads[pos].closed and game.maintenance.jobs[pos].left==5)
	press(game,JOY_BUTTON_A)
	assert(game.maintenance.jobs.size()==1)
	for i in 49: game._process(0.1)
	assert(game.roads.has(pos))
	game._process(0.2)
	assert(not game.roads.has(pos) and game.cars.has(driver))
	assert(game.traffic.position(driver)==pos and driver.dest==1 and driver.blocked)
	game.select_tool(4)
	game.cursor = Vector2i(350,350)
	game.terrain.set_cell(game.cursor,2)
	before = game.money
	press(game,JOY_BUTTON_A)
	assert(game.money==before-20 and game.ground(game.cursor)==2)
	for i in 29: game._process(0.1)
	assert(game.ground(game.cursor)==2)
	game._process(0.2)
	assert(game.ground(game.cursor)==0 and game.maintenance.trees_cut==1)
	# Mid-job save/reload and explicitly demolished access tiles persist.
	var access: Vector2i = game.cities[0].accesses[0].end
	game.cursor = access
	game.select_tool(3)
	press(game,JOY_BUTTON_A)
	game._process(2.0)
	game.save_game(false)
	game.maintenance.reset()
	game.accounts.reset()
	game.load_game()
	assert(is_equal_approx(game.maintenance.jobs[access].left,3))
	game._process(3.1)
	assert(not game.roads.has(access))
	game.ensure_city_accesses()
	assert(not game.roads.has(access))
	game.save_game(false)
	game.load_game()
	assert(not game.roads.has(access))
	assert(game.accounts.totals.has("demolition") and game.accounts.totals.logging==-20)
	assert(is_equal_approx(game.money,game.accounts.opening+game.accounts.income()-game.accounts.expenses()))
	# The interactive map samples terrain without populating chunk caches.
	game.terrain.reset(game.world_seed)
	for i in 100:
		var p = Vector2i(i*157,i*149)
		assert(game.terrain.sample_cell(p)==game.terrain.get_cell(p))
	game.terrain.chunks.clear()
	game.ui_action("map")
	for i in 12: game.navigator.update(0.2)
	assert(game.navigator.texture!=null and game.terrain.chunks.is_empty())
	var target = game.cities[1].accesses[0].end
	assert(game.navigator.to_world(game.navigator.to_screen(Vector2(target)))==target)
	game.navigator.target = target
	press(game,JOY_BUTTON_A)
	assert(game.cursor==target and game.panel=="")
	game.open_menu()
	press(game,JOY_BUTTON_A)
	assert(game.panel=="cities")
	press(game,JOY_BUTTON_DPAD_DOWN)
	press(game,JOY_BUTTON_A)
	assert(game.cursor==target and game.panel=="")
	# Current connection status changes on cuts, historical demand survives.
	game.roads.clear(); game.road_nodes.clear(); game.cities.clear()
	game.city_cells.clear(); game.city_connectors.clear(); game.cars.clear()
	game.traffic.reset(); game.incidents.reset(); game.maintenance.reset()
	game.demolished_access_tiles.clear(); game.terrain.fill(0)
	game.add_city(Vector2i(100,100),"A",1)
	game.add_city(Vector2i(130,100),"B",1)
	game.select_tool(0); game.kind = 0
	game.anchor = Vector2i(104,100); game.cursor = Vector2i(126,100)
	game.apply_action()
	for i in 30: game._process(0.1)
	assert(game.traffic.current_links[0]==[1])
	game.cursor = Vector2i(115,100); game.select_tool(1); game.apply_action()
	game.rebuild_graph()
	assert(game.traffic.current_links[0].is_empty() and 1 in game.cities[0].unlocked)
	var queued: int = game.traffic.queued
	game.spawn_trips()
	assert(game.traffic.queued>=queued)
	var legacy = load("res://scripts/accounts.gd").new()
	legacy.legacy_balance(1000,100,70000,42)
	assert(legacy.totals.legacy==-10900 and legacy.periods.is_empty())
	assert(legacy.opening+legacy.income()-legacy.expenses()==70000)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	print("PASS: icon toolbar order, LB/RB, Y selector, LT/RT zoom, two-endpoint segments, close toggle, exact costs/times, stopped cars, saved jobs/accesses/ledger, bounded terrain map, travel and current connectivity")
	game.free()
	quit()
