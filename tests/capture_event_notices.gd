extends SceneTree
var g
func _initialize() -> void: call_deferred("run")
func frame() -> void:
	g.queue_redraw();await process_frame;await process_frame
func shot(name: String) -> void:
	await frame()
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/event-"+name+".png")
func click(action: String) -> void:
	for hit in g.ui_hits:
		if hit.action!=action: continue
		var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
		event.position=hit.rect.get_center();g._unhandled_input(event)
		return
	assert(false,"Rendered action missing: "+action)
func tap(code: int) -> void:
	var event=InputEventKey.new();event.physical_keycode=code;event.pressed=true
	Input.parse_input_event(event);await frame()
	event.pressed=false;Input.parse_input_event(event);await frame()
func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false)
	root.size=Vector2i(1280,800);g.speed_index=0
	g.incidents.rules.weather_enabled=false;g.incidents.rules.abandon_enabled=false
	var at: Vector2i = g.cursor
	g.incidents.ignite(at)
	await shot("fire")
	g.incidents.snow_zone(at+Vector2i(12,0),3)
	# Native A moves the world as usual while a card is present.
	var key=InputEventKey.new();key.physical_keycode=KEY_A;key.pressed=true
	Input.parse_input_event(key);await frame();g._process(.1)
	assert(g.cursor==at+Vector2i.LEFT and g.event_notices.pending.size()==2)
	key.pressed=false;Input.parse_input_event(key);await frame()
	await tap(KEY_ENTER);assert(g.anchor==g.cursor and g.event_notices.pending.size()==2)
	g.open_menu();await shot("menu")
	assert(g.ui_hits.any(func(hit): return hit.action=="event:open"))
	await tap(KEY_ESCAPE);assert(g.panel=="" and g.event_notices.pending.size()==2)
	g._process(6);await shot("collapsed")
	assert(g.ui_hits[-1].action=="event:open")
	# Real rendered bell opens the inbox; archive cannot click through into the world.
	var anchor: Vector2i=g.anchor
	click("event:open");await shot("inbox")
	assert(g.panel=="notices" and g.anchor==anchor)
	var first_id: int=g.event_notices.pending[0].id
	click("event:dismiss:"+str(first_id));await shot("snow")
	assert(g.panel=="notices" and g.event_notices.pending.size()==1 and g.anchor==anchor)
	g.close_panels();g.event_notices.push("accident",at,"Vehículo detenido 15 s · Coste 100 €")
	await shot("accident")
	click("event:open");await frame()
	var accident_id: int=g.event_notices.pending[0].id
	click("event:go:"+str(accident_id));await frame()
	assert(g.panel=="" and g.cursor==at and g.event_notices.pending.size()==2 and g.anchor==anchor)
	for i in 10: g.event_notices.push("snow",at+Vector2i(i,20),"Nieve en la zona · Riesgo de accidentes +30 %")
	g.ui_action("event:open");g.last_pad=true;g.menu_focus.sync();await shot("inbox-full")
	click("event:next");await shot("inbox-page2")
	assert(g.event_notices.page==1)
	g.event_notices.reset();g.menu_focus.sync();await shot("inbox-empty")
	print("PASS: rendered passive cards, native WASD/construction/Escape, collapsed bell, mouse inbox/archive/travel, pagination, controller focus and empty state")
	g.free();quit()
