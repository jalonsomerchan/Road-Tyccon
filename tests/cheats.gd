extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	var console=game.cheats
	assert(not console.is_open())
	var key=InputEventKey.new()
	key.pressed=true;key.physical_keycode=KEY_F8
	console._input(key)
	assert(console.is_open() and console.field.has_focus())
	var before=game.money
	var elapsed=game.elapsed
	var cursor=game.cursor
	game._process(20)
	assert(game.elapsed==elapsed and game.cursor==cursor,"The dialog pauses simulation and movement")
	key.physical_keycode=KEY_M
	game._unhandled_input(key)
	assert(game.panel=="","Typing cheat letters must not trigger game shortcuts")
	assert(console.execute(" MOREMONEY ").ok)
	assert(game.money==before+100000 and game.accounts.totals.cheats==100000 and game.earned==0 and game.trips==0)
	console.field.text_submitted.emit("moremoney")
	assert(game.money==before+200000)
	assert(not console.execute("invalid code").ok and game.money==before+200000)
	assert(console.execute("fire").ok and game.incidents.fire.has(cursor))
	assert(console.execute("snow").ok and game.incidents.snow.has(cursor))
	assert(game.incidents.zones.size()>0)
	assert(console.execute("sun").ok and game.incidents.fire.is_empty() and game.incidents.snow.is_empty() and game.incidents.zones.is_empty())
	game.roads[cursor].hp=10.0;game.roads[cursor].closed=true;game.roads[cursor].work=3
	assert(console.execute("repair").ok and game.roads[cursor].hp==100 and game.roads[cursor].work==0 and game.roads[cursor].closed)
	game.roads[cursor].demolishing=true
	assert(not console.execute("repair").ok)
	game.roads[cursor].erase("demolishing")
	game.cursor=Vector2i(99999,99999)
	assert(not console.execute("repair").ok)
	game.cursor=cursor
	assert(console.execute("fast").ok and game.speed_index==game.SPEEDS.size()-1)
	assert(console.execute("normal").ok and game.speed_index==1)
	assert(console.execute("pause").ok and game.speed_index==0)
	console.close();game._process(.1)
	assert(game.elapsed==elapsed)
	assert(console.execute("normal").ok)
	var regions=game.explored.regions.size()
	assert(console.execute("reveal").ok and game.explored.regions.size()>regions)
	assert(game.cursor==cursor and game.cities.size()>game.INITIAL_CITY_COUNT)
	assert(console.execute("help").ok)
	game.open_menu()
	var button=InputEventJoypadButton.new()
	button.pressed=true;button.button_index=JOY_BUTTON_LEFT_STICK
	game._unhandled_input(button)
	assert(console.is_open())
	console.selection=0
	button.button_index=JOY_BUTTON_DPAD_DOWN;console._input(button)
	assert(console.selection==2)
	button.button_index=JOY_BUTTON_A;console._input(button)
	assert(game.incidents.snow.has(cursor))
	button.button_index=JOY_BUTTON_B;console._input(button)
	assert(not console.is_open() and game.panel=="menu")
	game.at_title=true
	console.open()
	assert(not console.is_open() and not console.execute("moremoney").ok)
	print("PASS: F8 editable console, blocked gameplay input, paused simulation, +100000€ ledger, fire/snow at selection, cleanup, instant repair, speed cheats, reveal, invalid codes and gamepad controls")
	game.free()
	quit()
