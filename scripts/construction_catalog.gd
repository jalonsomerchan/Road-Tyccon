extends RefCounted
## Un solo modelo para las tarjetas, el foco de mando, la paginación y la ficha técnica.
const TABS = ["Disponibles","Caminos","Carreteras","Ciudad","Puentes","Tráfico"]
const GROUPS = [[],[0,1,2,16,17,18],[3,4,5,6,7,8,9,21,22,23],[19,20],[10,11,12,13,14,15],[]]
const PAGE_SIZE = 6
var g
var tab = 0
var page = 0
var selected = "road:0"
var base_kind = 0

func _init(game) -> void: g=game

func road_id(id: String) -> int: return int(id.get_slice(":",1))
func allowed(id: String) -> bool: return not id.begins_with("road:") or g.gameplay.unlocked(road_id(id))
func selected_action() -> String: return "catalog:item:"+selected
func card_rect(index: int) -> Rect2: return Rect2(156+index%2*316,240+int(index/2)*114,304,100)
func tab_rect(index: int) -> Rect2: return Rect2(156+index*162,154,152,42)

func entries() -> Array:
	var result:Array=[]
	if tab==0 or tab==5: result=["signal","roundabout"]
	if tab==5: return result
	var kinds:Array=range(g.Catalog.ROADS.size()) if tab==0 else GROUPS[tab].duplicate()
	kinds.sort_custom(func(a,b):
		if g.gameplay.unlocked(a)!=g.gameplay.unlocked(b): return g.gameplay.unlocked(a)
		return g.Catalog.ROADS[a].cost<g.Catalog.ROADS[b].cost)
	for kind in kinds:
		if tab==0 and not g.gameplay.unlocked(kind): continue
		result.append("road:"+str(kind))
	return result

func visible_entries() -> Array:
	var all=entries()
	page=clampi(page,0,maxi(0,int((all.size()-1)/PAGE_SIZE)))
	return all.slice(page*PAGE_SIZE,mini((page+1)*PAGE_SIZE,all.size()))

func open() -> void:
	base_kind=g.kind if not g.Catalog.ROADS[g.kind].get("bridge",false) and g.gameplay.unlocked(g.kind) else 0
	selected="road:"+str(g.kind) if g.construction_mode=="road" else g.construction_mode
	tab=5 if selected in ["signal","roundabout"] else 0
	page=0
	var index=entries().find(selected)
	if index>=0: page=int(index/PAGE_SIZE)
	else: selected=entries()[0]

func model() -> Array:
	var items:Array=[]
	var visible=visible_entries()
	for i in visible.size(): items.append(g.menu_focus.entry("catalog:item:"+visible[i],card_rect(i)))
	for i in TABS.size(): items.append(g.menu_focus.entry("catalog:tab:"+str(i),tab_rect(i)))
	items.append(g.menu_focus.entry("catalog:prev",Rect2(156,590,142,42),page>0))
	items.append(g.menu_focus.entry("catalog:next",Rect2(630,590,146,42),(page+1)*PAGE_SIZE<entries().size()))
	items.append(g.menu_focus.entry("catalog:apply",Rect2(812,588,296,50),allowed(selected)))
	if selected=="roundabout": items.append(g.menu_focus.entry("catalog:base",Rect2(812,532,296,40)))
	return items

func change_tab(amount: int) -> void:
	choose_tab(posmod(tab+amount,TABS.size()))

func choose_tab(index: int) -> void:
	tab=clampi(index,0,TABS.size()-1);page=0
	selected=entries()[0]
	g.menu_focus.sync(selected_action());g.queue_redraw()

func change_page(amount: int) -> void:
	var last=maxi(0,int((entries().size()-1)/PAGE_SIZE))
	var next=clampi(page+amount,0,last)
	if next==page: return
	page=next;selected=visible_entries()[0]
	g.menu_focus.sync(selected_action());g.queue_redraw()

func preview(id: String) -> void:
	if not entries().has(id): return
	selected=id;g.queue_redraw()

func cycle_base(amount: int = 1) -> void:
	for offset in range(1,g.Catalog.ROADS.size()+1):
		var candidate=posmod(base_kind+offset*amount,g.Catalog.ROADS.size())
		if g.gameplay.unlocked(candidate) and not g.Catalog.ROADS[candidate].get("bridge",false):
			base_kind=candidate;g.queue_redraw();return

func confirm(id: String = "") -> void:
	if not id.is_empty(): preview(id)
	if not allowed(selected):
		g.tell("Disponible al alcanzar el nivel %d"%g.gameplay.road_tier(road_id(selected)));return
	g.anchor=g.NO_CELL
	if selected.begins_with("road:"):
		g.kind=road_id(selected);g.construction_mode="road"
	else:
		g.construction_mode=selected
		if selected=="roundabout": g.kind=base_kind
	g.select_tool(0)
	g.tell("Semáforo seleccionado · A sobre una carretera para colocarlo" if selected=="signal" else ("Rotonda seleccionada · A para colocar · 3 × 3 casillas" if selected=="roundabout" else "Vía seleccionada · A fija el inicio del tramo"))

func action(value: String) -> void:
	var command=value.get_slice(":",1)
	match command:
		"tab": choose_tab(int(value.get_slice(":",2)))
		"item":
			preview(value.trim_prefix("catalog:item:"));g.menu_focus.pick(selected_action())
		"prev": change_page(-1)
		"next": change_page(1)
		"apply": confirm()
		"base": cycle_base()

func lines(v, text: String, at: Vector2, width: float, size: int, color: Color, maximum: int = 2) -> void:
	var line=""
	var row=0
	for word in text.split(" "):
		var next=word if line.is_empty() else line+" "+word
		if g.font.get_string_size(next,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x>width and not line.is_empty():
			v.text(at+Vector2(0,row*(size+4)),line,size,color);row+=1;line=word
			if row>=maximum: return
		else: line=next
	if row<maximum: v.text(at+Vector2(0,row*(size+4)),line,size,color)

func name(id: String) -> String:
	return g.Catalog.ROADS[road_id(id)].name if id.begins_with("road:") else ("Rotonda" if id=="roundabout" else "Semáforo")

func picture(v, id: String, area: Rect2) -> void:
	v.toolbar.box(area,Color("102a25"),Color("38574b"),8)
	if id.begins_with("road:"): v.sprite("roads",road_id(id),area.grow(-5))
	elif id=="roundabout":
		var texture=v.road_conditions[base_kind].roundabout
		if texture!=null: v.canvas.draw_texture_rect(texture,area.grow(-5),false)
		v.toolbar.icon("roundabout",area.get_center(),Color("f2edda"),area.size.x*.48)
	else:
		v.toolbar.icon("signal",area.get_center(),v.PAPER,area.size.x*.7)
		v.canvas.draw_circle(area.position+Vector2(area.size.x*.5,area.size.y*.35),area.size.x*.065,Color("f18e7c"))
		v.canvas.draw_circle(area.position+Vector2(area.size.x*.5,area.size.y*.55),area.size.x*.065,v.GREEN)

func draw(v) -> void:
	for i in TABS.size(): v.button(tab_rect(i),TABS[i],"catalog:tab:"+str(i),tab==i)
	var visible=visible_entries()
	var all=entries()
	var available=0
	for id in all:
		if allowed(id): available+=1
	v.text(Vector2(156,222),"%s · %d disponibles"%[TABS[tab],available],16,v.GREEN)
	v.text(Vector2(810,222),"FICHA DE CONSTRUCCIÓN",12,v.MUTED)
	for i in visible.size():
		var id:String=visible[i]
		var area=card_rect(i)
		var action_id="catalog:item:"+id
		var chosen=selected==id
		var enabled=allowed(id)
		v.toolbar.box(area,Color("2d493b") if chosen else Color("203932"),v.GREEN if chosen else Color("38574b"),8)
		picture(v,id,Rect2(area.position+Vector2(10,12),Vector2(62,62)))
		lines(v,name(id),area.position+Vector2(84,26),208,16,v.PAPER if enabled else v.MUTED)
		var caption="Gratis · Control del cruce" if id=="signal" else (g.cash(g.Catalog.ROADS[base_kind].cost*9)+" · 3 × 3 casillas" if id=="roundabout" else str(int(g.Catalog.ROADS[road_id(id)].speed*15))+" km/h · "+g.cash(g.Catalog.ROADS[road_id(id)].cost)+"/cas.")
		v.text(area.position+Vector2(84,79),caption if enabled else "BLOQUEADA · Nivel %d"%g.gameplay.road_tier(road_id(id)),12,v.GREEN if enabled else Color("d3a56e"))
		g.ui_hits.append({"rect":area,"action":action_id})
		if g.menu_focus.focused(action_id,area): v.canvas.draw_rect(area.grow(3),Color("8de1f2"),false,2)
	if tab==5:
		v.toolbar.box(Rect2(156,366,620,202),Color("142c26"),Color("38574b"),8)
		v.text(Vector2(178,396),"DEL CATÁLOGO AL MAPA",12,v.GREEN)
		var steps=["1. Pulsa A para elegir el semáforo.","2. Sitúate sobre una carretera y pulsa A para instalarlo.","3. Pulsa A sobre él para configurar tiempos y encendido."] if selected=="signal" else ["1. Cambia el material con X; confirma la rotonda con A.","2. Busca una zona libre de 3 × 3 casillas y pulsa A.","3. Conecta sus accesos a tus carreteras al terminar la obra."]
		for i in steps.size(): v.text(Vector2(178,436+i*39),steps[i],15,v.PAPER)
	v.button(Rect2(156,590,142,42),"‹ Anterior","catalog:prev")
	v.text(Vector2(358,617),"%d / %d"%[page+1,maxi(1,int(ceil(all.size()/float(PAGE_SIZE))))],16,v.MUTED)
	v.button(Rect2(630,590,146,42),"Siguiente ›","catalog:next")
	draw_details(v)
	v.text(Vector2(156,674),"LB/RB pestañas · LT/RT páginas · Cruceta elegir · A confirmar · B volver" if g.last_pad else "Q/Tab pestañas · RePág/AvPág páginas · Flechas elegir · Enter confirmar · B/Esc volver",13,v.MUTED)

func metric(v, at: Vector2, label: String, value: String) -> void:
	v.toolbar.box(Rect2(at,Vector2(140,52)),Color("203932"),Color.TRANSPARENT,5)
	v.text(at+Vector2(9,17),label,10,v.MUTED)
	v.text(at+Vector2(9,39),value,16,v.PAPER)

func draw_details(v) -> void:
	v.toolbar.box(Rect2(796,234,328,410),Color("142c26"),Color("38574b"),9)
	picture(v,selected,Rect2(812,250,96,96))
	lines(v,name(selected),Vector2(922,276),184,19,v.PAPER,3)
	var road = selected.begins_with("road:")
	var spec = g.Catalog.ROADS[road_id(selected)] if road else g.Catalog.ROADS[base_kind]
	var description=""
	var cost=""
	if road:
		var kind=road_id(selected)
		description="Cruza ríos y lagos. Se puede prolongar como cualquier vía." if spec.get("bridge",false) else ("Para viajes largos y tráfico abundante." if spec.lanes>=4 else ("Acceso económico a poblaciones y zonas rurales." if kind in GROUPS[1] else "Conecta ciudades y distribuye el tráfico de tu red."))
		cost=g.cash(spec.cost)+" / casilla"
		metric(v,Vector2(812,410),"VELOCIDAD",str(int(spec.speed*15))+" km/h")
		metric(v,Vector2(968,410),"CAPACIDAD",str(spec.cap)+" coches/cas.")
		metric(v,Vector2(812,470),"CARRILES",str(spec.lanes))
		metric(v,Vector2(968,470),"OBRA",str(spec.time)+" s/cas.")
		v.text(Vector2(812,549),"Reparar: "+("%.2f €"%(spec.cost*g.WorldSettings.REPAIR_COST_RATIO))+"/cas.",12,v.MUTED)
		v.text(Vector2(812,571),"Conservación: %.2f €/min por casilla"%(spec.cost*.0008),11,v.MUTED)
	elif selected=="roundabout":
		description="Circulación en un solo sentido. Conecta sus cuatro brazos a la red. Necesita una zona libre de 3 × 3."
		cost=g.cash(spec.cost*9)+" / rotonda"
		metric(v,Vector2(812,410),"OCUPACIÓN","3 × 3 casillas")
		metric(v,Vector2(968,410),"CARRILES",str(spec.lanes))
		metric(v,Vector2(812,470),"OBRA",str(spec.time)+" s")
		metric(v,Vector2(968,470),"COSTE TOTAL",g.cash(spec.cost*9))
		v.button(Rect2(812,532,296,40),"X · "+v.toolbar.fit(spec.name,242,14),"catalog:base")
	else:
		description="Colócalo sobre una carretera. Regula el cruce y evita la parada extra para ceder el paso mientras está activo."
		cost="Instalación gratuita"
		metric(v,Vector2(812,410),"OCUPACIÓN","1 casilla")
		metric(v,Vector2(968,410),"DIRECCIONES","N/S · E/O")
		metric(v,Vector2(812,470),"VERDE N/S",str(g.WorldSettings.SIGNAL_NS_GREEN)+" s")
		metric(v,Vector2(968,470),"VERDE E/O",str(g.WorldSettings.SIGNAL_EW_GREEN)+" s")
		v.text(Vector2(812,549),"A sobre un semáforo permite configurarlo.",11,v.MUTED)
	lines(v,description,Vector2(812,371),296,13,v.MUTED,3)
	var label="Elegir · "+cost if allowed(selected) else "Se desbloquea en el nivel %d"%g.gameplay.road_tier(road_id(selected))
	v.button(Rect2(812,588,296,50),label,"catalog:apply",allowed(selected))
