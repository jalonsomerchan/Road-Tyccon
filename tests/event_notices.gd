extends SceneTree
var g
func _initialize() -> void: call_deferred("run")
func press(key: int, pad: bool = true, echo: bool = false) -> void:
	var event
	if pad:
		event=InputEventJoypadButton.new();event.button_index=key
	else:
		g.deck_input.last_face=-1 # Independent keyboard tap, not a Steam Input alias.
		event=InputEventKey.new();event.physical_keycode=key;event.echo=echo
	event.pressed=true
	g._unhandled_input(event)
	if event is InputEventJoypadButton:
		event.pressed=false;g._unhandled_input(event)

func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false)
	g.save_path="res://tests/event_notices_save.bin"
	g.incidents.rules.weather_enabled=false;g.incidents.rules.abandon_enabled=false
	g.speed_index=0
	var fire=Vector2i(700,500)
	var snow=Vector2i(710,510)
	var original: Vector2i = g.cursor
	g.incidents.ignite(fire);g.incidents.snow_zone(snow,2)
	var first_id: int = g.event_notices.pending[0].id
	# A passive arrival never hijacks WASD, construction, B/Escape or another menu.
	press(KEY_A,false)
	assert(g.cursor==original and g.event_notices.pending.size()==2)
	press(KEY_ENTER,false)
	assert(g.anchor==original and g.cursor==original and g.event_notices.pending.size()==2)
	press(KEY_B,false)
	assert(g.anchor==g.NO_CELL and g.event_notices.pending.size()==2)
	press(JOY_BUTTON_A)
	assert(g.anchor==original and g.cursor==original and g.event_notices.pending.size()==2)
	press(JOY_BUTTON_B)
	assert(g.anchor==g.NO_CELL and g.event_notices.pending.size()==2)
	g.open_panel("accounts");press(JOY_BUTTON_B)
	assert(g.panel=="" and g.event_notices.pending.size()==2)
	g.open_menu();press(KEY_ESCAPE,false)
	assert(g.panel=="" and g.event_notices.pending.size()==2)
	# Five real seconds hide the toast even while paused; the inbox persists.
	assert(g.event_notices.toast_until>g.visual_clock)
	g._process(6)
	assert(g.visual_clock>=g.event_notices.toast_until and g.event_notices.pending[0].id==first_id)
	# Explicitly open the inbox with F2, mouse action or the controller menu footer.
	var anchor=original+Vector2i(5,0)
	g.anchor=anchor
	press(KEY_F2,false)
	assert(g.panel=="notices" and g.anchor==anchor)
	g.menu_focus.pick("event:go:"+str(first_id));press(KEY_ENTER,false,true)
	assert(g.panel=="notices" and g.cursor==original,"Echo must not travel")
	var money: float = g.money
	press(KEY_ENTER,false)
	assert(g.cursor==fire and g.camera==Vector2(fire) and g.anchor==anchor and g.money==money)
	assert(g.panel=="" and g.event_notices.pending.size()==2,"Visiting does not archive an incidence")
	# World clicks cannot activate stale inbox actions after it closes.
	g.ui_action("event:dismiss:"+str(first_id));assert(g.event_notices.pending.size()==2)
	g.open_menu();g.menu_focus.pick("event:open");press(JOY_BUTTON_A)
	assert(g.panel=="notices")
	press(JOY_BUTTON_B)
	assert(g.panel=="menu" and g.event_notices.pending.size()==2 and g.anchor==anchor)
	g.ui_action("event:open")
	g.menu_focus.pick("event:dismiss:"+str(first_id));press(JOY_BUTTON_A)
	assert(g.panel=="notices" and g.event_notices.pending.size()==1 and g.cursor==fire)
	assert(g.menu_focus.current.begins_with("event:dismiss:"),"Archiving keeps focus on Archive")
	g.ui_action("event:go:"+str(first_id))
	assert(g.cursor==fire and g.event_notices.pending.size()==1,"Old ids cannot affect another incidence")
	press(JOY_BUTTON_A)
	assert(g.event_notices.pending.is_empty() and g.panel=="notices" and g.menu_focus.current=="close")
	press(KEY_ESCAPE,false);assert(g.panel=="menu")
	g.close_panels()
	# New arrivals group by type/location and never replace the selected destination.
	g.event_notices.push("fire",fire,"Fuego")
	g.event_notices.push("snow",snow,"Nieve")
	g.ui_action("event:open")
	first_id=g.event_notices.pending[0].id
	g.menu_focus.pick("event:go:"+str(first_id))
	g.event_notices.push("accident",snow,"Accidente")
	g.event_notices.push("fire",fire,"Incendio extendido")
	g.menu_focus.sync()
	assert(g.event_notices.pending[0].kind=="accident" and g.event_notices.pending.size()==3)
	assert(g.menu_focus.current=="event:go:"+str(first_id) and g.event_notices.rows()[0].id==first_id)
	assert(g.event_notices.find_notice(first_id).count==2)
	press(JOY_BUTTON_A);assert(g.cursor==fire and g.event_notices.pending.size()==3)
	# Pagination is reachable with keyboard, controller and mouse; archive any row by id.
	g.event_notices.reset()
	for i in 12: g.event_notices.push("snow",snow+Vector2i(i,0),"Nieve")
	g.ui_action("event:open");assert(g.event_notices.rows().size()==5)
	press(JOY_BUTTON_RIGHT_SHOULDER);assert(g.event_notices.page==1)
	var target: Dictionary=g.event_notices.rows()[2]
	g.ui_action("event:dismiss:"+str(target.id))
	assert(g.event_notices.find_notice(target.id).is_empty() and g.event_notices.pending.size()==11)
	g.ui_action("event:next");assert(g.event_notices.page==2 and g.event_notices.rows().size()==1)
	g.menu_focus.pick("event:dismiss:"+str(g.event_notices.rows()[0].id));press(KEY_ENTER,false)
	assert(g.event_notices.page==1 and g.event_notices.rows().size()==5)
	press(JOY_BUTTON_LEFT_SHOULDER);assert(g.event_notices.page==0)
	g.ui_action("event:prev");assert(g.event_notices.page==0)
	press(KEY_F2,false);assert(g.panel=="")
	# Actual accidents enqueue and grouping/archiving never alter the incident itself.
	g.event_notices.reset();g.roads[fire]=g.city_road(0,true);g.roads[fire].hp=5
	g.incidents.fire[fire]=g.elapsed+60;g.incidents.snow[fire]=g.elapsed+120
	var driver={"accident_clock":0.0,"crash_left":0.0}
	var crashed=false
	for i in 20:
		if g.incidents.accident(driver,fire,g.incidents.ACCIDENT_INTERVAL): crashed=true;break
	assert(crashed and g.event_notices.pending[0].kind=="accident" and g.incidents.last_alert==fire)
	g.event_notices.push("accident",fire,"Otro vehículo detenido")
	assert(g.event_notices.pending.size()==1 and g.event_notices.pending[0].count==2)
	var stop_left:float=driver.crash_left
	g.ui_action("event:open");g.ui_action("event:dismiss:"+str(g.event_notices.pending[0].id))
	assert(driver.crash_left==stop_left and g.event_notices.pending.is_empty())
	g.close_panels()
	# Bounded queue, saved inbox, no replayed toast on load, old saves and new-world reset.
	g.event_notices.push("fire",fire,"Fuego");first_id=g.event_notices.pending[0].id
	for i in 40: g.event_notices.push("snow",snow+Vector2i(i,0),"Nieve")
	assert(g.event_notices.pending.size()==g.event_notices.MAX_PENDING and g.event_notices.pending[0].id==first_id)
	g.ui_action("event:open")
	g.event_notices.change_page(1)
	var selected_id: int=g.event_notices.rows()[0].id
	g.menu_focus.pick("event:go:"+str(selected_id))
	g.event_notices.push("snow",snow+Vector2i(100,0),"Más nieve")
	g.menu_focus.sync()
	assert(g.menu_focus.current=="event:go:"+str(selected_id))
	assert(g.event_notices.rows().any(func(notice): return notice.id==selected_id),"Overflow must preserve the focused destination on its visible page")
	g.close_panels()
	var queued: Array = g.event_notices.pending.duplicate(true)
	g.save_game(false);g.event_notices.reset();assert(g.load_game())
	assert(g.event_notices.pending==queued and g.event_notices.toast_id==-1)
	var saved=g.incidents.snapshot();saved.erase("notices");g.incidents.restore(saved)
	assert(g.event_notices.pending.is_empty())
	g.incidents.ignite(fire);g.generate_world();assert(g.event_notices.pending.is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.save_path))
	print("PASS: passive toast expiry, construction/menu controls, explicit inbox, arbitrary stable ids, visit/archive separation, pagination, grouped arrivals, accident state, persistence and reset")
	g.free();quit()
