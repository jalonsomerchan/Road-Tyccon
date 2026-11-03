extends RefCounted
## Avisos persistentes: una acción afecta únicamente al evento que se está mostrando.
const MAX_PENDING = 32
const TITLES = {"fire":"INCENDIO DETECTADO", "snow":"ZONA NEVADA", "accident":"ACCIDENTE DE TRÁFICO"}
var g
var pending: Array = []
var sequence = 0
var suppress_a = false

func _init(game) -> void:
	g = game

func reset() -> void:
	pending.clear()
	sequence = 0
	suppress_a = false

func push(kind: String, position: Vector2i, description: String) -> void:
	if not TITLES.has(kind) or not g.inside(position): return
	# Agrupar sucesos repetidos en la misma casilla sin cambiar el destino del aviso.
	if not pending.is_empty():
		var last = pending.back()
		if last.kind==kind and last.pos==position:
			last.count+=1
			last.description=description
			return
	sequence+=1
	# El aviso visible permanece estable incluso durante una acumulación de accidentes.
	if pending.size()>=MAX_PENDING: pending.remove_at(1)
	pending.append({"id":sequence,"kind":kind,"pos":position,"description":description,"count":1,"at":g.elapsed})

func respond(id: int, go: bool) -> void:
	if pending.is_empty() or pending[0].id!=id: return
	var notice = pending.pop_front()
	if go:
		g.travel_to(notice.pos)
		g.tell(TITLES[notice.kind].capitalize()+" · "+str(notice.pos.x)+", "+str(notice.pos.y))
	g.queue_redraw()

func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key = event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key==KEY_A and not event.pressed: suppress_a=false
		if pending.is_empty() or not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return false
		if key in [KEY_A,KEY_ENTER,KEY_KP_ENTER,KEY_B,KEY_ESCAPE]:
			if not event.echo:
				g.last_pad=false
				if key==KEY_A: suppress_a=true
				respond(pending[0].id,key in [KEY_A,KEY_ENTER,KEY_KP_ENTER])
			return true
	if event is InputEventJoypadButton and event.pressed and not pending.is_empty():
		if event.button_index in [JOY_BUTTON_A,JOY_BUTTON_B]:
			g.last_pad=true
			respond(pending[0].id,event.button_index==JOY_BUTTON_A)
			return true
	return false

func action(value: String) -> void:
	var command = value.get_slice(":",1)
	if command in ["go","dismiss"]: respond(int(value.get_slice(":",2)),command=="go")

func draw(visuals) -> void:
	if pending.is_empty() or g.at_title or (g.cheats!=null and g.cheats.is_open()): return
	var notice = pending[0]
	var area = Rect2(790,116,470,158)
	var accent = Color("efbe70") if notice.kind=="fire" else (Color("ff9383") if notice.kind=="accident" else Color("97dbea"))
	visuals.card(area,Color("19342e"))
	visuals.rect(Rect2(area.position,Vector2(4,area.size.y)),accent)
	g.ui_hits.append({"rect":area,"action":"event:block:"+str(notice.id)})
	visuals.text(Vector2(810,148),TITLES[notice.kind],20,accent)
	if pending.size()>1: visuals.text(Vector2(1145,146),"+%d avisos"%(pending.size()-1),13,visuals.MUTED)
	visuals.text(Vector2(810,176),notice.description.substr(0,54),14,visuals.PAPER)
	visuals.text(Vector2(810,198),"Casilla %d, %d%s"%[notice.pos.x,notice.pos.y," · %d sucesos"%notice.count if notice.count>1 else ""],13,visuals.MUTED)
	visuals.button(Rect2(810,215,208,40),"A / Enter · Ir","event:go:"+str(notice.id),true)
	visuals.button(Rect2(1030,215,210,40),"B / Esc · Descartar","event:dismiss:"+str(notice.id))

func snapshot() -> Dictionary:
	return {"pending":pending.duplicate(true),"sequence":sequence}

func restore(data: Dictionary) -> void:
	reset()
	pending=data.get("pending",[]).duplicate(true)
	sequence=data.get("sequence",0)
