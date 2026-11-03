extends SceneTree
var g
func _initialize() -> void: call_deferred("run")
func press(key: int, pad: bool = true, echo: bool = false) -> void:
	var event
	if pad:
		event=InputEventJoypadButton.new();event.button_index=key
	else:
		event=InputEventKey.new();event.physical_keycode=key;event.echo=echo
	event.pressed=true
	g._unhandled_input(event)
	if event is InputEventJoypadButton:
		event.pressed=false;g._unhandled_input(event)

func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false)
	g.save_path="res://tests/event_notices_save.bin"
	g.incidents.rules.weather_enabled=false;g.incidents.rules.abandon_enabled=false
	var fire=Vector2i(700,500)
	var snow=Vector2i(710,510)
	var original: Vector2i = g.cursor
	var anchor=Vector2i(600,500)
	g.anchor=anchor
	g.incidents.ignite(fire);g.incidents.snow_zone(snow,2)
	assert(g.event_notices.pending.size()==2 and g.event_notices.pending[0].kind=="fire")
	var first_id: int = g.event_notices.pending[0].id
	# Unlike short informational messages, event notices survive elapsed real time.
	g.speed_index=0;g._process(20)
	assert(g.event_notices.pending[0].id==first_id)
	var money: float = g.money
	press(JOY_BUTTON_A)
	assert(g.cursor==fire and g.camera==Vector2(fire) and g.anchor==anchor and g.money==money)
	assert(g.event_notices.pending.size()==1 and g.event_notices.pending[0].kind=="snow")
	g.open_panel("accounts")
	press(JOY_BUTTON_B)
	assert(g.panel=="accounts" and g.cursor==fire and g.anchor==anchor and g.incidents.snow.has(snow))
	assert(g.event_notices.pending.is_empty())
	# B returns to its usual behavior once the event queue is empty.
	press(JOY_BUTTON_B);assert(g.panel=="")
	# A/Enter and B/Esc work on keyboard; key repeats cannot consume another notice.
	g.incidents.ignite(fire);g.incidents.snow_zone(snow,2)
	press(KEY_A,false)
	assert(g.cursor==fire and g.event_notices.suppress_a and g.event_notices.pending.size()==1)
	press(KEY_A,false,true);assert(g.event_notices.pending.size()==1)
	var release=InputEventKey.new();release.physical_keycode=KEY_A;release.pressed=false
	g._unhandled_input(release);assert(not g.event_notices.suppress_a)
	g.open_menu();press(KEY_ESCAPE,false)
	assert(g.panel=="menu" and g.event_notices.pending.is_empty())
	g.incidents.snow_zone(snow,2);press(KEY_ENTER,false)
	assert(g.cursor==snow and g.panel=="" and g.anchor==anchor)
	g.incidents.ignite(fire);press(KEY_B,false)
	assert(g.cursor==snow and g.event_notices.pending.is_empty())
	# Stale mouse targets do not dismiss or visit a later notice.
	g.incidents.ignite(fire);g.incidents.snow_zone(snow,2)
	first_id=g.event_notices.pending[0].id
	g.ui_action("event:dismiss:"+str(first_id))
	g.ui_action("event:go:"+str(first_id))
	assert(g.cursor==snow and g.event_notices.pending.size()==1)
	g.ui_action("event:go:"+str(g.event_notices.pending[0].id))
	assert(g.cursor==snow and g.event_notices.pending.is_empty())
	# Actual accidents enqueue an actionable event and update the last-event locator.
	g.event_notices.reset();g.roads[fire]=g.city_road(0,true);g.roads[fire].hp=5
	g.incidents.fire[fire]=g.elapsed+60;g.incidents.snow[fire]=g.elapsed+120
	var driver={"accident_clock":0.0,"crash_left":0.0}
	var crashed=false
	for i in 20:
		if g.incidents.accident(driver,fire,g.incidents.ACCIDENT_INTERVAL): crashed=true;break
	assert(crashed and g.event_notices.pending[0].kind=="accident" and g.incidents.last_alert==fire)
	g.event_notices.push("accident",fire,"Otro vehículo detenido")
	assert(g.event_notices.pending.size()==1 and g.event_notices.pending[0].count==2)
	press(JOY_BUTTON_A);assert(g.cursor==fire and g.event_notices.pending.is_empty())
	# Real accidents appear immediately even when weather notices are still waiting.
	g.incidents.ignite(fire);g.incidents.snow_zone(snow,2)
	var weather_id:int=g.event_notices.pending[0].id
	crashed=false;driver.crash_left=0
	for i in 20:
		if g.incidents.accident(driver,fire,g.incidents.ACCIDENT_INTERVAL): crashed=true;break
	assert(crashed and g.event_notices.pending[0].kind=="accident")
	assert(g.event_notices.pending.size()==3 and g.event_notices.pending[1].id==weather_id)
	var accident_id:int=g.event_notices.pending[0].id
	g.event_notices.push("accident",snow,"Segundo accidente")
	g.event_notices.push("fire",snow,"Nuevo incendio")
	g.event_notices.push("accident",fire,"Dos vehículos implicados")
	assert(g.event_notices.pending[0].id==accident_id and g.event_notices.pending[0].count==2)
	assert(g.event_notices.pending.size()==5,"Repeated accidents group even when another event arrived in between")
	var stop_left:float=driver.crash_left
	press(JOY_BUTTON_B)
	assert(driver.crash_left==stop_left and g.event_notices.pending[0].id==weather_id)
	assert(g.event_notices.pending[0].kind=="fire","Dismissing a crash retains the previous weather alert")
	g.event_notices.reset()
	# Limit the queue while preserving the currently visible event and its id.
	g.incidents.ignite(fire);first_id=g.event_notices.pending[0].id
	for i in 40: g.event_notices.push("snow",snow+Vector2i(i,0),"Nieve")
	assert(g.event_notices.pending.size()==g.event_notices.MAX_PENDING and g.event_notices.pending[0].id==first_id)
	var queued: Array = g.event_notices.pending.duplicate(true)
	g.save_game(false);g.event_notices.reset();assert(g.load_game())
	assert(g.event_notices.pending==queued)
	var saved=g.incidents.snapshot();saved.erase("notices");g.incidents.restore(saved)
	assert(g.event_notices.pending.is_empty(),"Old incident snapshots load without notifications")
	g.incidents.ignite(fire);g.generate_world();assert(g.event_notices.pending.is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.save_path))
	print("PASS: fire/snow/accident notices, A travel, B dismiss, menu and construction input priority, keyboard repeats/releases, mouse ids, grouped events, stable bounded queue, persistence, legacy saves and new-world reset")
	g.free();quit()
