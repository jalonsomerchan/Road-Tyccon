extends RefCounted
## Tarjetas informativas sin foco; las incidencias solo se atienden desde su panel.
const MAX_PENDING = 32
const PAGE_SIZE = 5
const TOAST_SECONDS = 5.0
const TITLES = {"fire":"INCENDIO DETECTADO", "snow":"ZONA NEVADA", "accident":"ACCIDENTE DE TRÁFICO"}
const BELL = Rect2(1084,68,176,32)
var g
var pending: Array = []
var sequence = 0
var toast_id = -1
var toast_until = 0.0
var page = 0
# El orden abierto no cambia cuando llegan sucesos: el foco conserva su destino.
var listed_ids: Array = []

func _init(game) -> void:
	g = game

func reset() -> void:
	pending.clear()
	sequence = 0
	toast_id = -1
	toast_until = 0.0
	page = 0
	listed_ids.clear()

func find_notice(id: int) -> Dictionary:
	for notice in pending:
		if notice.id==id: return notice
	return {}

func push(kind: String, position: Vector2i, description: String) -> void:
	if not TITLES.has(kind) or not g.inside(position): return
	for notice in pending:
		if notice.kind==kind and notice.pos==position:
			notice.count+=1
			notice.description=description
			g.queue_redraw()
			return
	sequence+=1
	if pending.size()>=MAX_PENDING:
		# No reemplazar la incidencia que está seleccionada en el panel.
		var index = 1
		if g.panel=="notices" and int(g.menu_focus.current.get_slice(":",2))==pending[index].id: index=2
		listed_ids.erase(pending[index].id)
		pending.remove_at(index)
	var notice={"id":sequence,"kind":kind,"pos":position,"description":description,"count":1,"at":g.elapsed}
	if kind=="accident" and not pending.is_empty() and pending[0].kind!="accident": pending.push_front(notice)
	else: pending.append(notice)
	if g.panel=="notices":
		listed_ids.append(notice.id)
		var selected=listed_ids.find(int(g.menu_focus.current.get_slice(":",2)))
		if selected>=0: page=int(selected/PAGE_SIZE)
	toast_id=notice.id
	toast_until=g.visual_clock+TOAST_SECONDS
	g.queue_redraw()

func respond(id: int, go: bool) -> void:
	var notice=find_notice(id)
	if notice.is_empty(): return
	if toast_id==id: toast_id=-1
	if go:
		# Visitar no archiva: la incidencia sigue disponible hasta descartarla.
		g.travel_to(notice.pos)
		g.tell(TITLES[notice.kind].capitalize()+" · "+str(notice.pos.x)+", "+str(notice.pos.y))
	else:
		pending.erase(notice)
		listed_ids.erase(id)
		page=clampi(page,0,page_count()-1)
	g.queue_redraw()

func open() -> void:
	listed_ids.clear()
	for accidents_first in [true,false]:
		for notice in pending:
			if (notice.kind=="accident")==accidents_first: listed_ids.append(notice.id)
	page=0
	toast_id=-1

func toggle() -> void:
	if g.panel=="notices": g.back_panel()
	else: g.open_panel("notices")

func page_count() -> int:
	return maxi(1,ceili(float(listed_ids.size())/PAGE_SIZE))

func rows() -> Array:
	var result: Array = []
	for i in range(page*PAGE_SIZE,mini((page+1)*PAGE_SIZE,listed_ids.size())):
		var notice=find_notice(listed_ids[i])
		if not notice.is_empty(): result.append(notice)
	return result

func change_page(direction: int) -> void:
	page=clampi(page+direction,0,page_count()-1)
	g.menu_focus.sync("event:go:"+str(listed_ids[page*PAGE_SIZE]) if not listed_ids.is_empty() else "close")
	g.queue_redraw()

func model() -> Array:
	var result: Array = []
	var visible=rows()
	for i in visible.size():
		var id=str(visible[i].id)
		result.append(g.menu_focus.entry("event:go:"+id,Rect2(850,204+i*76,94,38)))
		result.append(g.menu_focus.entry("event:dismiss:"+id,Rect2(956,204+i*76,162,38)))
	if not listed_ids.is_empty():
		result.append(g.menu_focus.entry("event:prev",Rect2(160,604,166,38),page>0))
		result.append(g.menu_focus.entry("event:next",Rect2(340,604,166,38),page+1<page_count()))
	return result

func action(value: String) -> void:
	var command = value.get_slice(":",1)
	match command:
		"open": toggle()
		"prev": change_page(-1)
		"next": change_page(1)
		"go","dismiss":
			if g.panel!="notices": return
			var id=int(value.get_slice(":",2))
			var index=listed_ids.find(id)
			if index<0: return
			respond(id,command=="go")
			if command=="dismiss":
				var preferred="close" if listed_ids.is_empty() else "event:dismiss:"+str(listed_ids[mini(index,listed_ids.size()-1)])
				g.menu_focus.sync(preferred)

func accent(notice: Dictionary) -> Color:
	return Color("efbe70") if notice.kind=="fire" else (Color("ff9383") if notice.kind=="accident" else Color("97dbea"))

func draw(visuals) -> void:
	if g.at_title or (g.cheats!=null and g.cheats.is_open()): return
	visuals.button(BELL,"", "event:open",g.panel=="notices")
	var ink=visuals.INK if g.panel=="notices" else visuals.PAPER
	# Campana vectorial para que no dependa de fuentes con emojis.
	var at=BELL.position+Vector2(20,16)
	visuals.canvas.draw_arc(at-Vector2(0,3),7,PI,TAU,12,ink,1.5,true)
	visuals.canvas.draw_polyline(PackedVector2Array([at+Vector2(-7,-3),at+Vector2(-7,5),at+Vector2(-10,7),at+Vector2(10,7),at+Vector2(7,5),at+Vector2(7,-3)]),ink,1.5,true)
	visuals.canvas.draw_circle(at+Vector2(0,10),2,ink)
	visuals.text(BELL.position+Vector2(37,22),("Avisos %d"%pending.size())+("" if g.last_pad else " · F2"),14,ink)
	if g.panel!="" or g.visual_clock>=toast_until: return
	var notice=find_notice(toast_id)
	if notice.is_empty(): return
	var area=Rect2(858,116,402,110)
	visuals.card(area,Color("19342e"))
	visuals.rect(Rect2(area.position,Vector2(4,area.size.y)),accent(notice))
	visuals.text(area.position+Vector2(16,28),TITLES[notice.kind],17,accent(notice))
	visuals.text(area.position+Vector2(16,52),visuals.toolbar.fit(notice.description,370,13),13,visuals.PAPER)
	visuals.text(area.position+Vector2(16,75),"Casilla %d, %d · Guardado en Avisos"%[notice.pos.x,notice.pos.y],13,visuals.MUTED)
	visuals.text(area.position+Vector2(16,96),"Menú → Avisos para consultar" if g.last_pad else "Sigue construyendo · F2 para consultar",12,visuals.MUTED)
	visuals.rect(Rect2(area.position+Vector2(0,108),Vector2(area.size.x*clampf((toast_until-g.visual_clock)/TOAST_SECONDS,0,1),2)),accent(notice))
	# La tarjeta no registra acciones ni captura clics o teclas.

func draw_panel(visuals) -> void:
	visuals.text(Vector2(160,170),"%d incidencias pendientes · Ir conserva el aviso; Archivar lo retira de esta lista."%pending.size(),14,visuals.MUTED)
	if pending.is_empty():
		visuals.text(Vector2(160,258),"No hay avisos pendientes",25,visuals.GREEN)
		visuals.text(Vector2(160,294),"Los nuevos sucesos aparecerán brevemente y quedarán guardados aquí.",17,visuals.MUTED)
	var visible=rows()
	for i in visible.size():
		var notice=visible[i]
		var at=Vector2(160,194+i*76)
		visuals.card(Rect2(at,Vector2(958,66)),Color("243c35"))
		visuals.rect(Rect2(at,Vector2(3,66)),accent(notice))
		visuals.text(at+Vector2(15,23),TITLES[notice.kind]+(" · ×%d"%notice.count if notice.count>1 else ""),16,accent(notice))
		visuals.text(at+Vector2(15,46),visuals.toolbar.fit(notice.description,475,13),13,visuals.PAPER)
		visuals.text(at+Vector2(508,37),"%d, %d"%[notice.pos.x,notice.pos.y],14,visuals.MUTED)
		visuals.button(Rect2(850,204+i*76,94,38),"Ir →","event:go:"+str(notice.id))
		visuals.button(Rect2(956,204+i*76,162,38),"Archivar","event:dismiss:"+str(notice.id))
	if not listed_ids.is_empty():
		visuals.button(Rect2(160,604,166,38),"← Anterior","event:prev")
		visuals.button(Rect2(340,604,166,38),"Siguiente →","event:next")
		visuals.text(Vector2(535,629),"Página %d / %d"%[page+1,page_count()],15,visuals.MUTED)
	visuals.text(Vector2(160,675),"Flechas / stick elegir · Enter / A activar · LB/RB páginas · B / Esc volver",14,visuals.MUTED)

func snapshot() -> Dictionary:
	return {"pending":pending.duplicate(true),"sequence":sequence}

func restore(data: Dictionary) -> void:
	reset()
	pending=data.get("pending",[]).duplicate(true)
	sequence=data.get("sequence",0)
	if g.panel=="notices": open()
