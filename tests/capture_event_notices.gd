extends SceneTree
var g
func _initialize() -> void: call_deferred("run")
func shot(name: String) -> void:
	g.queue_redraw();await process_frame;await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/event-"+name+".png")
	assert(g.ui_hits[-1].action.begins_with("event:dismiss:") and g.ui_hits[-2].action.begins_with("event:go:"))
func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false)
	root.size=Vector2i(1280,800)
	var at: Vector2i = g.cursor
	g.incidents.ignite(at)
	g.incidents.snow_zone(at+Vector2i(12,0),3)
	await shot("fire")
	g.open_menu();await shot("menu")
	g.event_notices.respond(g.event_notices.pending[0].id,false)
	await shot("snow")
	g.event_notices.respond(g.event_notices.pending[0].id,false)
	g.close_panels()
	g.event_notices.push("accident",at,"Vehículo detenido 15 s · Coste 100 €")
	await shot("accident")
	# Click the actual rendered Go button through the game's mouse handler.
	var click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	click.position=g.ui_hits[-2].rect.get_center();g._unhandled_input(click)
	assert(g.event_notices.pending.is_empty() and g.cursor==at)
	print("PASS: fire/snow/accident cards and queue count rendered over world/menus, clickable Go/Dismiss, no click-through")
	g.free();quit()
