extends RefCounted
## Iconografía vectorial compartida y barra de herramientas a escala de la interfaz.
const ICONS = ["road","close","open","repair","demolish","tree","menu","roundabout","signal","upgrade","undo","catalog","map","play","pause","zoom_in","zoom_out","goals","network","chevron_down"]
const RECT = Rect2(48,690,1184,98)
const ACCENTS = ["d3e69b","e6bd78","a7d9c0","eeab93","b4d3ad"]
var g
var visuals_ref: WeakRef
var v:
	get: return visuals_ref.get_ref()
var textures: Dictionary = {}
var styles: Dictionary = {}
var hover_hint = ""

func _init(game, visuals) -> void:
	g=game
	visuals_ref=weakref(visuals)
	for name in ICONS: textures[name]=load("res://assets/ui/icons/"+name+".svg")

func box(area: Rect2, color: Color, border: Color = Color.TRANSPARENT, radius: int = 7) -> void:
	var key = color.to_html()+border.to_html()+str(radius)
	if not styles.has(key):
		var style=StyleBoxFlat.new()
		style.bg_color=color
		style.border_color=border
		style.set_border_width_all(1 if border.a>0 else 0)
		style.set_corner_radius_all(radius)
		styles[key]=style
	v.canvas.draw_style_box(styles[key],area)

func icon(name: String, center: Vector2, color: Color, size: float = 30) -> void:
	if textures.has(name) and textures[name]!=null:
		v.canvas.draw_texture_rect(textures[name],Rect2(center-Vector2.ONE*size/2,Vector2.ONE*size),false,color)

func centered(area: Rect2, baseline: float, label: String, size: int, color: Color) -> void:
	var width=g.font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	v.text(Vector2(area.get_center().x-width/2,baseline),label,size,color)

func fit(label: String, width: float, size: int) -> String:
	if g.font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x<=width: return label
	var short=label
	while not short.is_empty() and g.font.get_string_size(short+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,size).x>width: short=short.left(-1)
	return short+"…"

func hovered(area: Rect2) -> bool:
	return not g.last_pad and g.panel=="" and area.has_point(g.get_local_mouse_position())

func tile(area: Rect2, name: String, label: String, action: String, active: bool, accent: Color, shortcut: String = "", enabled: bool = true, hint: String = "", small: bool = false) -> void:
	var over=hovered(area)
	var fill=accent if active else Color("213a34")
	var ink=v.INK if active else (accent if enabled else Color("70817a"))
	if over and not active: fill=Color("2b493e")
	box(area,fill,accent if active else Color("365348"))
	if active: box(Rect2(area.position+Vector2(21,area.size.y-5),Vector2(area.size.x-42,3)),v.INK,Color.TRANSPARENT,1)
	icon(name,Vector2(area.get_center().x,area.position.y+25),ink,25 if small else 30)
	centered(area,area.position.y+55,label,11 if small else 13,v.INK if active else (v.PAPER if enabled else Color("85998c")))
	if not shortcut.is_empty():
		var badge=Rect2(area.end.x-19,area.position.y+5,14,14)
		box(badge,Color(0.08,0.18,0.13,0.16) if active else Color("152c26"),Color.TRANSPARENT,3)
		centered(badge,badge.position.y+11,shortcut,9,v.INK if active else v.MUTED)
	g.ui_hits.append({"rect":area,"action":action})
	if over: hover_hint=hint

func can_upgrade() -> bool:
	if not g.roads.has(g.cursor) or not g.gameplay.unlocked(g.kind): return false
	var road=g.roads[g.cursor]
	var target=g.Catalog.ROADS[g.kind]
	var current=g.Catalog.ROADS[road.kind]
	return road.closed and road.work<=0 and not g.services.service_jobs.has(g.cursor) and target.cost>current.cost and target.get("bridge",false)==current.get("bridge",false)

func hint() -> String:
	if not g.event_notices.pending.is_empty(): return "Aviso de evento · A / Enter ir al lugar · B / Esc descartar"
	var confirm="A" if g.last_pad else "Enter"
	match g.TOOLS[g.tool].id:
		"build_road":
			if g.construction_mode=="roundabout": return confirm+" colocar rotonda · 3 × 3 casillas · B / Esc cancelar"
			if g.construction_mode=="signal": return confirm+" instalar o configurar semáforo · B / Esc cancelar"
			return confirm+(" fijar inicio" if g.anchor==g.NO_CELL else " construir tramo")+" · "+("X" if g.last_pad else "R")+" cambiar trazado · Y catálogo"
		"close_route": return confirm+" cerrar / abrir la vía seleccionada"
		"repair_route": return confirm+" reparar · "+("X" if g.last_pad else "U")+" mejorar al tipo elegido · Cierra la vía antes"
		"demolish_route": return confirm+" destruir la vía · Coste: 25 % de construcción · 5 s de obra"
		"fell_trees": return confirm+" talar árboles · 20 € por casilla · 3 s de obra"
	return "☰ menú · View mapa · L3 pausa · B cerrar, volver o cancelar" if g.last_pad else "6 / F10 menú · B / Esc cerrar, volver o cancelar"

func draw() -> void:
	hover_hint=""
	box(Rect2(RECT.position+Vector2(0,4),RECT.size),Color(0.02,0.06,0.04,0.5),Color.TRANSPARENT,11)
	box(RECT,Color("142c26"),Color("43604b"),11)
	g.ui_hits.append({"rect":RECT,"action":"toolbar:block"})
	var labels=["Construir","Cerrar","Reparar","Destruir","Talar"]
	var descriptions=["Construir carreteras · Elige dos extremos para trazar la vía","Cerrar / abrir vías · Prepara el tramo antes de hacer obras","Reparar carreteras · Restaura su conservación y seguridad","Destruir la vía seleccionada · Coste del 25 % y 5 s de obra","Talar árboles · Despeja terreno por 20 € la casilla"]
	for i in 5:
		var name: String = g.TOOLS[i].icon
		var label: String = labels[i]
		if i==1 and g.roads.has(g.cursor) and g.roads[g.cursor].closed: name="open";label="Abrir"
		tile(Rect2(60+i*86,700,80,66),name,label,"tool:"+str(i),g.tool==i,Color(ACCENTS[i]),"" if g.last_pad else str(i+1),true,descriptions[i])
	v.rect(Rect2(498,708,1,50),Color("365348"))
	var selector=Rect2(512,700,308,66)
	var selected=g.panel=="catalog"
	box(selector,Color("2b493e") if hovered(selector) or selected else Color("213a34"),v.GREEN if selected else Color("365348"))
	box(Rect2(520,708,50,50),Color("142c26"),Color("365348"),5)
	if g.construction_mode=="roundabout":
		var image=v.road_conditions[g.kind].roundabout
		if image!=null: v.canvas.draw_texture_rect(image,Rect2(525,713,40,40),false)
	else: v.sprite("roads",g.kind,Rect2(525,713,40,40))
	v.text(Vector2(582,717),"TIPO DE VÍA · Y",10,v.MUTED)
	v.text(Vector2(582,738),fit(g.Catalog.ROADS[g.kind].name,196,14),14,v.PAPER)
	v.text(Vector2(582,755),str(g.Catalog.ROADS[g.kind].lanes)+" carriles · "+g.cash(g.Catalog.ROADS[g.kind].cost)+" / casilla",11,v.MUTED)
	icon("chevron_down",Vector2(801,734),v.GREEN,15)
	g.ui_hits.append({"rect":selector,"action":"catalog"})
	if hovered(selector): hover_hint="Catálogo de carreteras y puentes · Y / V abrir · Flechas o cruceta elegir"
	tile(Rect2(834,700,54,66),"roundabout","Rotonda","toolbar:roundabout",g.tool==0 and g.construction_mode=="roundabout",v.GREEN,"" if g.last_pad else "O",true,"Rotonda de 3 × 3 casillas · Usa el tipo de vía elegido",true)
	tile(Rect2(896,700,54,66),"signal","Semáf.","toolbar:signal",g.tool==0 and g.construction_mode=="signal",v.GREEN,"" if g.last_pad else "T",true,"Semáforo · Colocar y configurar sobre una carretera",true)
	tile(Rect2(958,700,54,66),"upgrade","Mejorar","toolbar:upgrade",false,Color("a7d9c0"),("X" if g.tool==2 else "") if g.last_pad else "U",can_upgrade(),"Mejorar · Cierra la vía y selecciona una categoría superior en el catálogo",true)
	tile(Rect2(1020,700,54,66),"undo","Deshacer","toolbar:undo",false,Color("a7d9c0"),"" if g.last_pad else "Z",g.services.can_undo(),"Deshacer · Ctrl+Z · Antes de 60 s y del primer uso de la construcción",true)
	v.rect(Rect2(1086,708,1,50),Color("365348"))
	tile(Rect2(1100,700,116,66),"menu","Menú","menu",g.tool==5,v.GREEN,"☰" if g.last_pad else "6",true,"Menú de la región · Ciudades, objetivos, servicios y contabilidad")
	var note=hint() if not g.event_notices.pending.is_empty() else (hover_hint if not hover_hint.is_empty() else hint())
	var keys="LB/RB herramientas · View mapa · ☰ menú" if g.last_pad else "1–5 herramientas · 6 menú"
	var width=g.font.get_string_size(keys,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
	v.text(Vector2(62,780),fit(note,minf(900,1130-width),12),12,v.MUTED)
	v.text(Vector2(1216-width,780),keys,12,Color("c4d5aa"))

func action(value: String) -> void:
	match value.get_slice(":",1):
		"roundabout":
			if g.tool==0 and g.construction_mode=="roundabout": g.construction_mode="road"
			else: g.select_tool(0);g.construction_mode="roundabout"
			g.anchor=g.NO_CELL
		"signal":
			if g.tool==0 and g.construction_mode=="signal": g.construction_mode="road"
			else: g.select_tool(0);g.construction_mode="signal"
			g.anchor=g.NO_CELL
		"upgrade":
			if can_upgrade(): g.upgrade_current()
			else: g.tell("Para mejorar, cierra la vía y selecciona una categoría superior en el catálogo.")
		"undo": g.services.undo_build()
