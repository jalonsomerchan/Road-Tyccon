extends CanvasLayer
## Consola local de códigos cerrados: nunca interpreta código ni comandos del sistema.
const CODES = [
	["moremoney","Añade 100.000 €"],
	["fire","Incendio en la casilla seleccionada"],
	["snow","Nieve alrededor de la selección"],
	["sun","Quita nieve e incendios"],
	["repair","Repara al instante la vía seleccionada"],
	["fast","Velocidad máxima al cerrar"],
	["normal","Velocidad ×1 al cerrar"],
	["pause","Deja la partida en pausa"],
	["reveal","Descubre 5×5 regiones cercanas"]
]
var g
var cover: ColorRect
var field: LineEdit
var feedback: Label
var coordinates: Label
var buttons: Array[Button] = []
var close_button: Button
var selection = 0
var stick_clock = 0.0

func _init(game) -> void:
	g = game
	layer = 20

func box(color: Color, border: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	return style

func _ready() -> void:
	cover = ColorRect.new()
	cover.color = Color(0.02,0.06,0.05,.86)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(cover)
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left=-440;panel.offset_right=440
	panel.offset_top=-330;panel.offset_bottom=330
	var surface = box(Color("172c2c"),Color("647b64"))
	surface.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel",surface)
	cover.add_child(panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	panel.add_child(column)
	var heading = HBoxContainer.new()
	column.add_child(heading)
	var title = Label.new()
	title.text="Trucos"
	title.add_theme_font_size_override("font_size",28)
	title.add_theme_color_override("font_color",Color("d3e69b"))
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	close_button=Button.new()
	close_button.text="Cerrar · Esc / B"
	close_button.pressed.connect(close)
	heading.add_child(close_button)
	coordinates=Label.new()
	coordinates.add_theme_color_override("font_color",Color("a0b4a4"))
	column.add_child(coordinates)
	field=LineEdit.new()
	field.placeholder_text="Escribe un código y pulsa Enter…"
	field.max_length=64
	field.clear_button_enabled=true
	field.custom_minimum_size=Vector2(0,48)
	field.add_theme_font_size_override("font_size",22)
	field.add_theme_stylebox_override("normal",box(Color("243e36"),Color("47605a")))
	field.add_theme_stylebox_override("focus",box(Color("243e36"),Color("d3e69b")))
	field.text_submitted.connect(submit)
	column.add_child(field)
	feedback=Label.new()
	feedback.text="Escribe un código o elige uno de la lista."
	feedback.custom_minimum_size=Vector2(0,44)
	feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size",16)
	column.add_child(feedback)
	var grid=GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",8)
	column.add_child(grid)
	for i in CODES.size():
		var button=Button.new()
		button.text=CODES[i][0]+"\n"+CODES[i][1]
		button.custom_minimum_size=Vector2(400,56)
		button.add_theme_font_size_override("font_size",15)
		button.add_theme_stylebox_override("normal",box(Color("263d38"),Color("47605a")))
		button.add_theme_stylebox_override("focus",box(Color("3c5541"),Color("d3e69b")))
		button.pressed.connect(select_code.bind(i))
		buttons.append(button)
		grid.add_child(button)
	var hint=Label.new()
	hint.text="F8 abre / cierra · Cruceta elegir · A ejecutar · Steam + X abre el teclado"
	hint.add_theme_font_size_override("font_size",14)
	hint.add_theme_color_override("font_color",Color("a0b4a4"))
	column.add_child(hint)
	cover.hide()

func is_open() -> bool:
	return cover!=null and cover.visible

func open() -> void:
	if g.at_title or not g.session_active: return
	coordinates.text="Casilla "+str(g.cursor.x)+", "+str(g.cursor.y)+" · La simulación se detiene mientras escribes."
	feedback.text="Escribe un código o elige uno de la lista."
	feedback.modulate=Color.WHITE
	field.text=""
	cover.show()
	if g.last_pad:
		selection=clampi(selection,0,buttons.size()-1)
		buttons[selection].grab_focus()
	else: field.grab_focus()

func close() -> void:
	var focused=get_viewport().gui_get_focus_owner()
	if focused!=null: focused.release_focus()
	cover.hide()
	g.queue_redraw()

func _input(event: InputEvent) -> void:
	if is_open() and g.deck_input.duplicate_alias(event):
		get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.pressed and not event.echo:
		var key=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key==KEY_F8 and not g.at_title:
			g.last_pad=false
			if is_open(): close()
			else: open()
			get_viewport().set_input_as_handled()
			return
		if is_open() and key==KEY_ESCAPE:
			close();get_viewport().set_input_as_handled();return
	if not is_open(): return
	if g.deck_input.handle(event): get_viewport().set_input_as_handled()

func pad_button(button: int) -> void:
	match button:
		JOY_BUTTON_B,JOY_BUTTON_START: close()
		JOY_BUTTON_A:
			if close_button.has_focus(): close()
			elif field.has_focus() and not field.text.strip_edges().is_empty(): submit(field.text)
			else: select_code(selection)
		JOY_BUTTON_Y: field.grab_focus()

func move_selection(amount: int) -> void:
	selection=clampi(selection+amount,0,buttons.size())
	if selection==buttons.size(): close_button.grab_focus()
	else: buttons[selection].grab_focus()

func select_code(index: int) -> void:
	selection=index
	field.text=CODES[index][0]
	submit(field.text)

func submit(value: String) -> void:
	var result=execute(value)
	feedback.text=result.message
	feedback.modulate=Color("d3e69b") if result.ok else Color("f3aa95")
	if not g.last_pad:
		field.grab_focus()
		field.select_all()
	g.queue_redraw()

func execute(value: String) -> Dictionary:
	if g.at_title or not g.session_active: return {"ok":false,"message":"Inicia o carga una partida primero."}
	var code=value.strip_edges().to_lower()
	var message=""
	match code:
		"moremoney":
			g.transact(100000.0,"cheats","Truco moremoney")
			message="+100.000 € · Saldo: "+g.accounts.format_money(g.money)
		"fire":
			g.incidents.ignite(g.cursor)
			message="Incendio en "+str(g.cursor)+". Se extenderá al reanudar."
		"snow":
			g.incidents.snow_zone(g.cursor,int(g.incidents.rules.snow_radius))
			message="Zona nevada alrededor de "+str(g.cursor)+"."
		"sun":
			g.incidents.fire.clear();g.incidents.snow.clear();g.incidents.zones.clear()
			g.graph_dirty=true
			g.incidents.last_alert=g.NO_CELL
			g.incidents.weather_clock=0
			message="Nieve e incendios despejados."
		"repair":
			var cells=g.route_cells(g.cursor)
			var count=0
			for p in cells:
				if g.roads.has(p) and g.roads[p].get("demolishing",false):return {"ok":false,"message":"No se puede reparar una vía en demolición."}
			for p in cells:
				if not g.roads.has(p):continue
				g.roads[p].hp=100.0;g.roads[p].work=0.0;g.roads[p].last_used=g.elapsed
				count+=1
			if count==0:return {"ok":false,"message":"Selecciona una casilla con carretera o rotonda."}
			g.graph_dirty=true
			message="Vía reparada al instante · "+str(count)+" casillas."
		"fast":g.speed_index=g.SPEEDS.size()-1;message="Velocidad máxima al cerrar la consola."
		"normal":g.speed_index=1;message="Velocidad ×1 al cerrar la consola."
		"pause":g.speed_index=0;message="La partida quedará en pausa al cerrar."
		"reveal":
			var before=g.explored.regions.size()
			var key=g.Extent.key_for(g.cursor)
			for y in range(-2,3):
				for x in range(-2,3):
					var at=(key+Vector2i(x,y))*g.Extent.REGION+Vector2i.ONE*(g.Extent.REGION/2)
					g.explore_around(Vector2(at))
			message="Descubiertas "+str(g.explored.regions.size()-before)+" regiones cercanas."
		"help":message="Códigos: moremoney, fire, snow, sun, repair, fast, normal, pause y reveal."
		_:return {"ok":false,"message":"Código desconocido. Consulta la lista o escribe help."}
	if code!="help" and not g.gameplay.scenario_id.is_empty(): g.gameplay.scenario_cheated=true
	return {"ok":true,"message":message}
