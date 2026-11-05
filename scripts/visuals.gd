extends RefCounted
## Presentación: los sprites, la interfaz y los efectos no alteran la simulación.
var g
var canvas
var toolbar
var overview
var terrain_cache
var scenery_atlas: Texture2D
var scenery_atlas_size = Vector2.ONE
var atlas_white_uv = Vector2.ZERO
var sheets: Dictionary = {}
const Connections = preload("res://scripts/road_connections.gd")
const RoundaboutArt = preload("res://scripts/roundabout_art.gd")
const MAX_ROUNDABOUT_VARIANTS = 12
var road_variants: Array = []
var road_conditions: Array = []
var roundabout_variants: Dictionary = {}
var environment: Dictionary = {}
var tooltip_rect = Rect2()
var visible_car_tickets: Array = []
var minimap_texture: ImageTexture
var minimap_stamp: Array = []
var minimap_next_update = 0
var minimap_low = Vector2.ZERO
var minimap_span = 1024.0
var road_layout_revision = -1
var junctions: Array = []
var junction_coverage: Dictionary = {}
var node_shapes: Dictionary = {}
const INK = Color("172c2c")
const PAPER = Color("f2edda")
const MUTED = Color("a0b4a4")
const GREEN = Color("d3e69b")
const WORLD = Rect2(0, 84, 1280, 604)
const PAVEMENT_TILE = 12

func _init(game) -> void:
	g = game
	canvas = game
	# Los índices de parcelas y estructuras urbanas siguen apuntando a sus sprites.
	var used_frames = {"terrain":[0,2,5,10,PAVEMENT_TILE], "props":[6,7,8,15]}
	for family in used_frames:
		var frames: Array = []
		frames.resize(16)
		for i in used_frames[family]:
			var path = "res://assets/sprites/%s/sprite-%d.png" % [family, i + 1]
			frames[i] = load(path)
		sheets[family] = frames
	var nature_frames = {"trees":["tree",4], "mountains":["mountain",3], "scrub":["scrub",2]}
	for family in nature_frames:
		var spec: Array = nature_frames[family]
		sheets[family] = []
		for i in spec[1]:
			sheets[family].append(load("res://assets/sprites/nature/%s-%d.png" % [spec[0],i+1]))
	var straight_frames: Array = []
	for slug in Connections.SLUGS:
		var variants: Dictionary = {}
		for shape in Connections.SHAPES:
			var path = "res://assets/sprites/roads-v5/%s/%s.png" % [slug, shape]
			variants[shape] = load(path) if ResourceLoader.exists(path) else null
		road_variants.append(variants)
		straight_frames.append(variants.straight)
	sheets["roads"] = straight_frames
	sheets["buildings"] = []
	for name in g.CityDesign.BUILDINGS:
		var folder = "city-v2" if name=="park" else "city-v3"
		sheets.buildings.append(load("res://assets/sprites/%s/%s.png" % [folder,name]))
	sheets["vehicles"] = []
	for i in 8: sheets.vehicles.append(load("res://assets/sprites/vehicles-v2/car-"+str(i+1)+".png"))
	sheets["city_streets"] = []
	for mask in 16:
		var shape = Connections.shape_for(mask)
		var pixels: Image = road_variants[19][shape.shape].get_image().duplicate()
		if pixels.is_compressed(): pixels.decompress()
		for turn in shape.turns: pixels.rotate_90(CLOCKWISE)
		sheets.city_streets.append(ImageTexture.create_from_image(pixels))
	batch_scenery_atlas()
	for slug in Connections.SLUGS:
		var states: Dictionary = {}
		for state in g.incidents.STATES:
			var path = "res://assets/sprites/road-conditions/%s/%s.png" % [slug, state]
			states[state] = load(path) if ResourceLoader.exists(path) else null
		road_conditions.append(states)
	for name in ["fire", "snow"]:
		environment[name] = []
		for i in 4:
			var path = "res://assets/sprites/environment/%s/frame-%d.png" % [name, i + 1]
			environment[name].append(load(path) if ResourceLoader.exists(path) else null)

	toolbar=preload("res://scripts/toolbar.gd").new(g,self)
	overview=preload("res://scripts/region_overview.gd").new(g)

func batch_scenery_atlas() -> void:
	# Una textura compartida permite a Godot agrupar miles de sprites sin cambiar de textura.
	var families = ["terrain","props","trees","mountains","scrub","buildings","city_streets"]
	var large_sources: Array = []
	var small_sources: Array = []
	for family in families:
		for i in sheets[family].size():
			var source = sheets[family][i]
			if source == null: continue
			var pixels: Image = source.get_image()
			if pixels.is_compressed(): pixels.decompress()
			pixels.convert(Image.FORMAT_RGBA8)
			var entry = {"family":family,"index":i,"pixels":pixels}
			if pixels.get_size() == Vector2i(32,32): small_sources.append(entry)
			else: large_sources.append(entry)
	var small_slots = ceili(float(small_sources.size())/4.0)
	var white_index = large_sources.size()+small_slots
	const COLUMNS = 8
	scenery_atlas_size = Vector2(COLUMNS*64,ceili(float(white_index+1)/COLUMNS)*64)
	var atlas_image = Image.create(int(scenery_atlas_size.x),int(scenery_atlas_size.y),false,Image.FORMAT_RGBA8)
	var regions: Array = []
	for i in large_sources.size():
		var entry: Dictionary = large_sources[i]
		var at = Vector2i(i%COLUMNS,i/COLUMNS)*64
		atlas_image.blit_rect(entry.pixels,Rect2i(0,0,64,64),at)
		regions.append({"family":entry.family,"index":entry.index,"at":at,"size":Vector2i(64,64)})
	for i in small_sources.size():
		var entry: Dictionary = small_sources[i]
		var slot = large_sources.size()+int(i/4)
		var at = Vector2i(slot%COLUMNS,slot/COLUMNS)*64+Vector2i(i%2,i%4/2)*32
		atlas_image.blit_rect(entry.pixels,Rect2i(0,0,32,32),at)
		regions.append({"family":entry.family,"index":entry.index,"at":at,"size":Vector2i(32,32)})
	var white_at = Vector2i(white_index%COLUMNS,white_index/COLUMNS)*64
	atlas_image.fill_rect(Rect2i(white_at,Vector2i(64,64)),Color.WHITE)
	atlas_white_uv = (Vector2(white_at)+Vector2(32.5,32.5))/scenery_atlas_size
	var atlas = ImageTexture.create_from_image(atlas_image)
	scenery_atlas = atlas
	for region in regions:
		var frame = AtlasTexture.new()
		frame.atlas = atlas
		frame.region = Rect2(Vector2(region.at),Vector2(region.size))
		frame.filter_clip = true
		sheets[region.family][region.index] = frame

func rect(area: Rect2, color: Color) -> void:
	canvas.draw_rect(area, color)

func text(at: Vector2, value: String, size: int = 16, color: Color = PAPER) -> void:
	canvas.draw_string(g.font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func card(area: Rect2, color: Color = INK) -> void:
	rect(Rect2(area.position + Vector2(0, 4), area.size), Color(0.02, 0.05, 0.04, 0.3))
	rect(area, color)
	rect(Rect2(area.position, Vector2(area.size.x, 1)), Color("47605a"))

func button(area: Rect2, value: String, action: String, active: bool = false) -> void:
	var enabled=g.menu_focus.available(action)
	rect(area,(GREEN if active else Color("263d38")) if enabled else Color("1b302b"))
	text(area.position+Vector2(12,area.size.y/2+6),value,16,(INK if active else PAPER) if enabled else MUTED)
	g.ui_hits.append({"rect":area,"action":action})
	if enabled and g.menu_focus.focused(action,area): canvas.draw_rect(area.grow(3),Color("8de1f2"),false,2)

func sprite(family: String, index: int, area: Rect2, rotation: float = 0.0, tint: Color = Color.WHITE) -> void:
	var texture = sheets[family][index]
	if texture == null: return
	if rotation == 0:
		canvas.draw_texture_rect(texture, area, false, tint)
	else:
		canvas.draw_set_transform(area.get_center(), rotation)
		canvas.draw_texture_rect(texture, Rect2(-area.size / 2, area.size), false, tint)
		canvas.draw_set_transform(Vector2.ZERO)

func draw() -> void:
	g.ui_hits.clear()
	g.menu_focus.sync()
	if g.at_title:
		tooltip_rect = Rect2()
		draw_title()
		return
	if terrain_cache == null: terrain_cache = preload("res://scripts/terrain_render_cache.gd").new(g)
	if g.tile<overview.DETAIL_THRESHOLD:
		terrain_cache.set_visible(false)
		overview.draw(self)
	else:
		terrain_cache.set_visible(true)
		terrain_cache.prepare()
		draw_jobs()
		draw_environment()
		g.gameplay_ui.draw_world(self)
		draw_cars()
		draw_signage()
		draw_cities()
		draw_city_accesses()
		draw_selection()
		draw_income()
	draw_hud()
	g.gameplay_ui.draw_hud(self)
	if g.show_minimap and g.tile>=overview.DETAIL_THRESHOLD: draw_minimap()
	if g.panel != "":
		tooltip_rect = Rect2()
		draw_panel()
	elif g.tile>=overview.DETAIL_THRESHOLD: draw_tooltip()
	else: tooltip_rect=Rect2()
	g.event_notices.draw(self)

func draw_title() -> void:
	draw_title_map()
	# Superficie opaca y tranquila para mantener el menú legible sobre el mapa vivo.
	rect(Rect2(0, 0, 520, 800), Color(0.055, 0.10, 0.09, 0.94))
	rect(Rect2(519, 0, 1, 800), Color("47605a", 0.55))
	rect(Rect2(66, 344, 54, 5), GREEN)
	text(Vector2(66, 412), "ENTRE", 46, PAPER)
	text(Vector2(66, 468), "CIUDADES", 56, GREEN)
	text(Vector2(67, 495), "Cada conexión transforma tu región.", 16, MUTED)
	button(Rect2(66,286,400,40),g.gameplay_ui.mode_label()+" · X","play:mode")
	var labels = ["Nueva partida","Cargar partida","Salir"]
	for i in 3:
		var area = Rect2(66, 520 + i * 55, 316, 44)
		if i==1 and not g.title_has_save:
			rect(area, Color(0.10, 0.19, 0.18, 0.84))
			text(area.position + Vector2(18, 29), labels[i], 18, Color("62796d"))
		else:
			button(area, "", "title:" + ["new", "load", "quit"][i], g.title_index == i)
			var color = INK if g.title_index==i else PAPER
			text(area.position + Vector2(18, 29), labels[i], 18, color)
			if g.title_index == i: text(area.position + Vector2(286, 30), "→", 21, color)
	var detail = "Nueva región · Presupuesto: "+g.cash(g.gameplay_ui.starting_money())
	if g.title_index==1: detail = "Recupera tu región, sus carreteras y sus viajes."
	elif g.title_index==2: detail = "Hasta la próxima conexión."
	if not g.title_has_save and g.title_index==0: detail = "Empieza con "+g.cash(g.gameplay_ui.starting_money())
	text(Vector2(66, 694), detail, 13, MUTED)
	if g.title_message != "": text(Vector2(66, 720), g.title_message, 13, Color("efac95"))
	elif not g.title_has_save: text(Vector2(66, 720), "Todavía no hay una partida guardada.", 13, MUTED)
	text(Vector2(66, 755), "↑ ↓ / stick elegir · Enter / A aceptar", 13, PAPER)
	if g.title_confirm_new:
		g.ui_hits.clear()
		rect(Rect2(0,0,1280,800),Color(0.03,0.08,0.06,0.86))
		card(Rect2(300,254,680,286))
		text(Vector2(334,303),"¿Empezar una nueva región?",26,GREEN)
		text(Vector2(334,353),"Tu guardado actual se reemplazará cuando guardes",18,PAPER)
		text(Vector2(334,382),"la nueva partida o se active el autoguardado.",18,PAPER)
		button(Rect2(334,426,290,52),"Crear partida","title_confirm",g.title_confirm_accept)
		button(Rect2(642,426,302,52),"Volver · B","title_cancel",not g.title_confirm_accept)
		text(Vector2(334,515),"← → elegir · A / Enter aceptar · B / Esc volver",14,MUTED)

func draw_title_map() -> void:
	# Mosaico de terreno con los sprites del juego: bosque, río, caminos y poblaciones.
	var origin = Vector2(0, -16)
	var cell = 64.0
	for y in 13:
		for x in 20:
			var variation = posmod(x * 3 + y * 7, 11)
			sprite("terrain", 2 if variation == 0 else 0, Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * cell))
	# Un río ancho y suavemente cambiante atraviesa la región; la carretera lo cruza por un puente.
	var river_columns: Array[int] = []
	for y in 13:
		var center = 12 + roundi(sin(y * 0.48) * 1.4)
		river_columns.append(center)
		for x in range(center - 1, center + 2):
			sprite("terrain", 5, Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * cell))
	# Cumbres y arboledas con la misma paleta que el mapa jugable.
	for y in 13:
		for x in 20:
			var p = Vector2i(x, y)
			var river = river_columns[y]
			if abs(x - river) <= 1 or y == 7 or (x >= 9 and x <= 13 and y >= 4 and y <= 10): continue
			if (x * 17 + y * 31) % 19 == 0:
				sprite("mountains", posmod(x + y, 3), Rect2(origin + Vector2(p) * cell, Vector2.ONE * cell))
			elif (x * 13 + y * 23) % 5 <= 1:
				var tree = posmod(x * 7 + y * 11, 4)
				var size = cell * (0.86 + float(posmod(x + y * 3, 4)) * 0.06)
				sprite("trees", tree, Rect2(origin + Vector2(p) * cell + (Vector2.ONE * cell - Vector2.ONE * size) / 2, Vector2.ONE * size))
	# Pequeños barrios a ambos lados del río.
	var buildings = [
		Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(4, 3),
		Vector2i(3, 4), Vector2i(4, 4), Vector2i(15, 2), Vector2i(16, 2), Vector2i(17, 2),
		Vector2i(15, 3), Vector2i(17, 3), Vector2i(16, 4), Vector2i(17, 4),
		Vector2i(14, 9), Vector2i(15, 9), Vector2i(17, 9), Vector2i(18, 9),
		Vector2i(15, 10), Vector2i(17, 10), Vector2i(18, 10)
	]
	for i in buildings.size():
		var p: Vector2i = buildings[i]
		var area = Rect2(origin + Vector2(p) * cell, Vector2.ONE * cell)
		var urban = p.x>=14
		var count: int = g.CityDesign.URBAN_BUILDINGS.size() if urban else g.CityDesign.HOUSES.size()
		var index: int = posmod(i*3+p.x,count)+(g.CityDesign.FIRST_URBAN if urban else 0)
		sprite("terrain",PAVEMENT_TILE,area)
		sprite("buildings",index,area.grow(-cell*(0.025 if urban else 0.095)))
	var network: Dictionary = {}
	for x in range(0, 20): network[Vector2i(x, 7)] = true
	for y in range(4, 8): network[Vector2i(5, y)] = true
	for y in range(7, 11): network[Vector2i(16, y)] = true
	for p in network:
		var shape = Connections.shape_for(Connections.mask_for(p, network, {}), true)
		var bridge = p.y == 7 and abs(p.x - river_columns[p.y]) <= 1
		draw_connection(12 if bridge else 4, shape.shape, Rect2(origin + Vector2(p) * cell, Vector2.ONE * cell), shape.turns)
	# Tráfico de muestra que da vida al paisaje sin empezar la simulación.
	for i in 4:
		var x = fposmod(2.0 + i * 4.7 + g.visual_clock * (0.12 + i * 0.012), 20.0)
		var at = origin + Vector2(x, 7.5) * cell
		sprite("vehicles", i, Rect2(at - Vector2(15, 15), Vector2(30, 30)), PI / 2)

func draw_roads() -> void:
	prepare_road_layout()
	var visible: Array = []
	var viewport = Rect2(-g.tile,-g.tile,1280+g.tile*2,800+g.tile*2)
	for p in terrain_cache.visible_roads:
		if not g.roads.has(p): continue
		var area = tile_area(p)
		if viewport.intersects(area):
			visible.append({"p":p,"area":area})
			draw_road(p,area)
	draw_roundabouts()
	for junction in junctions:
		var size = junction.width * g.tile
		var area = Rect2(g.screen(Vector2(junction.pos)) - Vector2.ONE * size / 2, Vector2.ONE * size)
		if area.intersects(Rect2(-g.tile, -g.tile, 1280 + g.tile * 2, 800 + g.tile * 2)):
			draw_connection(junction.kind, junction.shape, area, junction.turns)
	for item in visible: draw_road_status(item.p,item.area)

func tile_area(p: Vector2i) -> Rect2:
	return Rect2(g.screen(Vector2(p)) - Vector2.ONE * g.tile / 2, Vector2.ONE * g.tile)

func draw_connection(kind: int, shape: String, area: Rect2, turns: int) -> void:
	draw_rotated_texture(road_variants[kind][shape],area,turns)

func draw_rotated_texture(texture: Texture2D, area: Rect2, turns: int, alpha: float = 1.0) -> void:
	if texture == null: return
	var tint = Color(1,1,1,alpha)
	if turns == 0:
		canvas.draw_texture_rect(texture, area, false, tint)
	else:
		canvas.draw_set_transform(area.get_center(), turns * PI / 2)
		canvas.draw_texture_rect(texture, Rect2(-area.size / 2, area.size), false, tint)
		canvas.draw_set_transform(Vector2.ZERO)

func prepare_road_layout() -> void:
	if road_layout_revision == g.road_revision: return
	road_layout_revision = g.road_revision
	junctions.clear()
	junction_coverage.clear()
	node_shapes.clear()
	for p in g.roads:
		node_shapes[p] = road_shape(p)

func road_shape(p: Vector2i) -> Dictionary:
	var axis: bool = g.roads[p].axis
	var mask = 0
	for i in Connections.DIRECTIONS.size():
		if g.surface_link(p,p+Connections.DIRECTIONS[i]): mask |= 1 << i
	return Connections.shape_for(mask,axis)

func draw_bridge_decks() -> void:
	var viewport = Rect2(-g.tile,-g.tile,1280+g.tile*2,800+g.tile*2)
	for p in g.bridge_decks:
		var area = tile_area(p)
		if not viewport.intersects(area): continue
		var span: Vector4i = g.bridge_decks[p]
		var from: Dictionary = g.roads.get(Vector2i(span.x,span.y),{})
		var to: Dictionary = g.roads.get(Vector2i(span.z,span.w),{})
		if from.is_empty() or to.is_empty() or not g.bridge_spans.has(span): continue
		var along_x = span.x!=span.z
		var shadow = Vector2(0,g.tile*0.12) if along_x else Vector2(g.tile*0.12,0)
		var deck_width = (0.38 if g.Catalog.ROADS[from.kind].lanes==1 else 1.0)*g.tile
		var inset = Vector2(0,(g.tile-deck_width)*0.5) if along_x else Vector2((g.tile-deck_width)*0.5,0)
		rect(Rect2(area.position+inset-shadow,area.size-2*inset+2*shadow),Color(0.10,0.13,0.12,0.42))
		draw_connection(from.kind,"straight",area,1 if along_x else 0)
		if g.bridge_spans[span]>0 or from.work>0 or to.work>0 or from.closed or to.closed:
			rect(Rect2(area.position+inset,area.size-2*inset),Color(0.95,0.58,0.23,0.28))

func road_texture(p: Vector2i, shape: String) -> Texture2D:
	var kind: int = g.roads[p].kind
	var state = g.incidents.visual_state(p)
	if shape == "straight" and state != "" and road_conditions[kind][state] != null:
		return road_conditions[kind][state]
	return road_variants[kind][shape]

func draw_road(p: Vector2i, area: Rect2) -> void:
	if g.incidents.roundabout_cells.has(p): return
	var r = g.roads[p]
	var shape = node_shapes.get(p, Connections.shape_for(0, r.axis))
	var texture = road_texture(p,shape.shape)
	var alpha = 1.0 if texture==road_variants[r.kind][shape.shape] else 1.0-g.incidents.fade(p)
	draw_rotated_texture(texture,area,shape.turns,alpha)

func draw_road_status(p: Vector2i, area: Rect2) -> void:
	var r = g.roads[p]
	var angle = PI / 2 if r.axis else 0.0
	if r.hp < 65:
		canvas.draw_polyline(PackedVector2Array([area.position + area.size * 0.25, area.get_center(), area.position + area.size * Vector2(0.3, 0.8)]), Color("283b37"), maxf(1, g.tile * 0.04))
	if r.closed or r.work > 0:
		var working = r.work > 0
		var color = Color("f6bb61") if working else Color("ff6b61")
		rect(area, Color(0.95, 0.48 if working else 0.13, 0.15, 0.26))
		canvas.draw_rect(area.grow(-1), color, false, maxf(1, g.tile * 0.06))
		if working:
			for stripe in 3:
				var x = area.position.x + g.tile * stripe / 3.0
				canvas.draw_line(Vector2(x, area.position.y + g.tile * 0.16), Vector2(x + g.tile * 0.28, area.position.y + g.tile * 0.44), color, maxf(1, g.tile * 0.06))
			rect(Rect2(area.position + Vector2(2, g.tile - 5), Vector2((g.tile - 4) * (1.0 - r.work / r.total), 3)), GREEN)
		else:
			canvas.draw_line(area.position + area.size * 0.22, area.position + area.size * 0.78, Color("ffb1a0"), maxf(2, g.tile * 0.09))
			canvas.draw_line(area.position + area.size * Vector2(0.78, 0.22), area.position + area.size * Vector2(0.22, 0.78), Color("ffb1a0"), maxf(2, g.tile * 0.09))
			sprite("props", 15, Rect2(area.position + Vector2(0, g.tile * 0.25), Vector2(g.tile, g.tile * 0.55)), angle)
			var pulse = 0.6 + sin(g.visual_clock * 7) * 0.35
			canvas.draw_circle(area.position + Vector2(g.tile * 0.15, g.tile * 0.18), maxf(2, g.tile * 0.07), Color(1, 0.1, 0.08, pulse))

func car_position(car: Dictionary) -> Vector2:
	var start: Vector2 = car.path[car.step]
	var end: Vector2 = car.path[mini(car.step + 1, car.path.size() - 1)]
	var direction = (end - start).normalized()
	var lane = Vector2(-direction.y, direction.x) * 0.18
	var pos = start.lerp(end, clampf(car.t, 0, 1)) + lane
	var a = Vector2i(start)
	var b = Vector2i(end)
	if g.incidents.roundabout_cells.has(a):
		var center: Vector2i = g.incidents.roundabout_cells[a]
		if g.incidents.roundabout_cells.get(b, g.NO_CELL) == center:
			var from = (start - Vector2(center)).angle()
			var to = (end - Vector2(center)).angle()
			pos = Vector2(center) + Vector2.from_angle(lerp_angle(from,to,clampf(car.t,0,1))) * 0.82
	if car.get("blocked", false):
		var ticket: int = car.get("ticket", 0)
		pos += Vector2(ticket % 3 - 1, int(ticket / 3) % 3 - 1) * 0.09
	return g.screen(pos)

func car_direction(car: Dictionary) -> Vector2:
	var start: Vector2 = car.path[car.step]
	var end: Vector2 = car.path[mini(car.step+1,car.path.size()-1)]
	var a = Vector2i(start)
	var b = Vector2i(end)
	if a!=b and g.incidents.roundabout_cells.has(a):
		var center: Vector2i = g.incidents.roundabout_cells[a]
		if g.incidents.roundabout_cells.get(b,g.NO_CELL)==center:
			var from = (start-Vector2(center)).angle()
			var to = (end-Vector2(center)).angle()
			var angle = lerp_angle(from,to,clampf(car.t,0,1))
			return Vector2(-sin(angle),cos(angle))*signf(angle_difference(from,to))
	return (end-start).normalized() if start!=end else Vector2(car.get("heading",Vector2.UP))

func car_draw_list() -> Array:
	var result: Array = []
	var occupied: Dictionary = {}
	var ordered: Array = g.cars.duplicate()
	ordered.sort_custom(func(a,b): return a.get("ticket",0)<b.get("ticket",0))
	var size = maxf(5,g.tile*0.72)
	for car in ordered:
		if car.t<0: continue
		var pos = car_position(car)
		if not Rect2(-30,-30,1340,860).has_point(pos): continue
		var direction = car_direction(car)
		var angle = direction.angle()+PI/2
		var shape = Vector2(size*.52,size*.94)
		var bounds_size = Vector2(absf(cos(angle))*shape.x+absf(sin(angle))*shape.y,absf(sin(angle))*shape.x+absf(cos(angle))*shape.y)
		var bounds = Rect2(pos-bounds_size/2,bounds_size)
		var start = Vector2i(car.path[car.step])
		var next = Vector2i(car.path[mini(car.step+1,car.path.size()-1)])
		var elevated = next in g.bridge_links.get(start,[])
		var cell = Vector2i((pos/size).floor())
		var key = Vector3i(cell.x,cell.y,int(elevated))
		var clear = true
		for dy in range(-1,2):
			for dx in range(-1,2):
				for other in occupied.get(key+Vector3i(dx,dy,0),[]):
					if bounds.intersects(other): clear=false; break
		if not clear: continue
		if not occupied.has(key): occupied[key]=[]
		occupied[key].append(bounds)
		result.append({"car":car,"pos":pos,"direction":direction,"angle":angle,"size":size,"bounds":bounds,"elevated":elevated,"sprite":posmod(car.get("sprite_id",car.get("color",0)),8)})
	return result

func draw_cars() -> void:
	visible_car_tickets.clear()
	var elevated: Array = []
	for item in car_draw_list():
		if item.elevated: elevated.append(item)
		else: draw_car(item)
	draw_bridge_decks()
	for item in elevated: draw_car(item)

func draw_car(item: Dictionary) -> void:
	var car = item.car
	var pos: Vector2 = item.pos
	var size: float = item.size
	visible_car_tickets.append(car.get("ticket",0))
	sprite("vehicles",item.sprite,Rect2(pos-Vector2.ONE*size/2,Vector2.ONE*size),item.angle)
	if car.get("blocked",false):
		canvas.draw_circle(pos+Vector2(-3,-3),2,Color("ff554b"))
		canvas.draw_circle(pos+Vector2(3,-3),2,Color("ff554b"))
	if car.get("crash_left",0.0)>0:
		canvas.draw_circle(pos+Vector2(0,-10),7,Color("9f3b32"))
		text(pos+Vector2(-2,-5),"!",15,Color("fff0ce"))

func draw_cities() -> void:
	for c in g.cities:
		var at = g.screen(Vector2(c.pos)) - Vector2(0, (c.radius + 0.7) * g.tile + 16)
		if not Rect2(-100, 85, 1480, 590).has_point(at): continue
		var width = g.font.get_string_size(c.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 26
		card(Rect2(at - Vector2(width / 2, 21), Vector2(width, 30)), Color("2c4034"))
		text(at + Vector2(-width / 2 + 13, 0), c.name, 17, Color("f8efd0"))

func visible_preview_cells() -> Array:
	if g.anchor==g.NO_CELL: return [g.cursor]
	# Intersectar las dos rectas con la cámara evita recorrer un tramo de miles de casillas.
	var half = Vector2(660,420)/g.tile
	var low = Vector2i((g.camera-half).floor())
	var high = Vector2i((g.camera+half).ceil())
	var corner = Vector2i(g.cursor.x,g.anchor.y) if g.horizontal else Vector2i(g.anchor.x,g.cursor.y)
	var cells: Dictionary = {}
	for leg in [[g.anchor,corner],[corner,g.cursor]]:
		var start: Vector2i = leg[0]
		var end: Vector2i = leg[1]
		if start.x==end.x:
			if start.x<low.x or start.x>high.x: continue
			for y in range(maxi(low.y,mini(start.y,end.y)),mini(high.y,maxi(start.y,end.y))+1): cells[Vector2i(start.x,y)] = true
		else:
			if start.y<low.y or start.y>high.y: continue
			for x in range(maxi(low.x,mini(start.x,end.x)),mini(high.x,maxi(start.x,end.x))+1): cells[Vector2i(x,start.y)] = true
	return cells.keys()

func draw_selection() -> void:
	var preview = visible_preview_cells()
	if g.construction_mode == "roundabout" and g.tool == 0:
		preview.clear()
		for y in range(-1,2):
			for x in range(-1,2): preview.append(g.cursor + Vector2i(x,y))
	for p in preview:
		var at = g.screen(Vector2(p)) - Vector2.ONE * g.tile / 2
		if not g.inside(p): continue
		var invalid = g.ground(p) in [3, 4] or (g.ground(p) == 1 and not g.Catalog.ROADS[g.kind].get("bridge", false))
		var color = Color("fa9580") if invalid and g.tool < 2 else GREEN
		if g.anchor!=g.NO_CELL or (g.construction_mode == "roundabout" and g.tool == 0):
			rect(Rect2(at, Vector2.ONE * g.tile), Color(color, 0.22))
			canvas.draw_rect(Rect2(at, Vector2.ONE * g.tile), Color(color, 0.65), false, 1)
	var area = Rect2(g.screen(Vector2(g.cursor)) - Vector2.ONE * g.tile / 2, Vector2.ONE * g.tile)
	var color = Color("ff8b7c") if g.TOOLS[g.tool].id in ["close_route","demolish_route"] else GREEN
	canvas.draw_rect(area.grow(2), Color("223c2f"), false, 4)
	canvas.draw_rect(area.grow(2), color, false, 2)
	if g.tool==0 and g.construction_mode.begins_with("sign:"):
		var direction = Vector2(g.RoadSigns.DIRECTIONS[g.signage.heading])
		var at = area.get_center()
		var tip = at+direction*g.tile*0.34
		canvas.draw_line(at-direction*g.tile*0.23,tip,GREEN,maxf(2.0,g.tile*0.06),true)
		canvas.draw_colored_polygon(PackedVector2Array([tip,tip+direction.rotated(2.5)*g.tile*0.21,tip+direction.rotated(-2.5)*g.tile*0.21]),GREEN)
	if g.anchor!=g.NO_CELL:
		var distance: Vector2i = (g.cursor-g.anchor).abs()
		var count = distance.x+distance.y+1
		var tag = area.position + Vector2(g.tile + 10, -8)
		card(Rect2(tag, Vector2(190, 32)))
		text(tag + Vector2(10, 22), str(count) + " secciones" if g.TOOLS[g.tool].id == "repair_route" else str(count) + " secciones · " + g.cash(count * g.Catalog.ROADS[g.kind].cost), 14, GREEN)

func draw_income() -> void:
	var stacks: Dictionary = {}
	for index in range(g.money_popups.size() - 1, -1, -1):
		var pop = g.money_popups[index]
		var row: int = stacks.get(pop.pos, 0)
		stacks[pop.pos] = row + 1
		var t = pop.age
		var at = g.screen(pop.pos) + Vector2(-20, -g.tile * 0.9 - t * 16 - row * 26)
		var alpha = clampf((2.2 - t) / 0.55, 0, 1)
		var value = ("+" if pop.amount >= 0 else "") + g.cash(pop.amount)
		if row < 4:
			text(at + Vector2(1, 2), value, 19, Color(0.05, 0.15, 0.09, alpha))
			text(at, value, 19, Color(0.91, 1, 0.6, alpha) if pop.amount >= 0 else Color(1, 0.45, 0.35, alpha))

func draw_hud() -> void:
	# Barra superior ligera: tesorería, ritmo y accesos de navegación.
	rect(Rect2(0, 0, 1280, 60), INK)
	rect(Rect2(0, 59, 1280, 1), Color("47605a"))
	canvas.draw_circle(Vector2(42, 30), 12 + g.income_pulse * 2, GREEN)
	text(Vector2(37, 36), "€", 17, INK)
	text(Vector2(68, 23), "TESORERÍA", 10, MUTED)
	text(Vector2(68, 46), g.cash(g.display_money), 22, Color("ff9383") if g.display_money > g.money + 1 else GREEN.lerp(Color.WHITE, g.income_pulse * 0.65))
	# Separadores y botones compactos, siempre conectados a sus acciones actuales.
	rect(Rect2(874, 13, 1, 34), Color("47605a"))
	icon_button(Rect2(891,12,96,36),"Pausa" if g.speed_index==0 else str(g.SPEEDS[g.speed_index])+"×","speed","play" if g.speed_index==0 else "pause",g.speed_index==0)
	icon_button(Rect2(1000,12,132,36),"Mapa · M","map","map")
	icon_button(Rect2(1144,12,116,36),"Menú","menu","menu",g.panel=="menu")
	toolbar.draw()
	card(Rect2(1216,324,44,140))
	button(Rect2(1218,326,40,40),"","zoom_in")
	draw_tool_icon("zoom_in",Vector2(1238,346),PAPER,22)
	text(Vector2(1220,395),("%.1f%%"%(g.zoom_target/32*100) if g.zoom_target<4 else str(int(g.zoom_target/32*100))+"%"),12,MUTED)
	button(Rect2(1218,416,40,40),"","zoom_out")
	draw_tool_icon("zoom_out",Vector2(1238,436),PAPER,22)
	if g.notice_time > 0:
		var width = minf(940, g.font.get_string_size(g.notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 32)
		card(Rect2(20, 72, width, 34), Color("243e34"))
		text(Vector2(36, 95), g.notice, 15, Color("f0edcf"))

func draw_minimap() -> void:
	card(Rect2(20, 492, 184, 184))
	var stamp:Array=[g.world_seed,g.terrain.generation,g.explored.revision,g.road_revision]
	if minimap_texture==null or (stamp!=minimap_stamp and Time.get_ticks_msec()>=minimap_next_update):
		minimap_stamp=stamp;minimap_next_update=Time.get_ticks_msec()+500
		minimap_low=Vector2(g.explored.bounds.position)
		minimap_span=maxf(600,maxf(g.explored.bounds.size.x,g.explored.bounds.size.y))
		var image=Image.create(166,166,false,Image.FORMAT_RGBA8)
		for p in g.roads:
			var at=Vector2i(((Vector2(p)-minimap_low)/minimap_span*165).floor())
			if Rect2i(0,0,166,166).has_point(at): image.set_pixelv(at,GREEN)
		for c in g.cities:
			var at=Vector2i(((Vector2(c.pos)-minimap_low)/minimap_span*165).floor())
			image.fill_rect(Rect2i(at-Vector2i.ONE,Vector2i(3,3)).intersection(Rect2i(0,0,166,166)),Color("f6dd9f"))
		if minimap_texture==null: minimap_texture=ImageTexture.create_from_image(image)
		else: minimap_texture.update(image)
	canvas.draw_texture_rect(minimap_texture,Rect2(29,501,166,166),false)
	var current=Vector2(29,501)+(g.camera-minimap_low)/minimap_span*165
	canvas.draw_rect(Rect2(current-Vector2(640,400)/g.tile/minimap_span*165,Vector2(1280,800)/g.tile/minimap_span*165),GREEN,false,1)
	text(Vector2(32, 515), "REGIÓN CONOCIDA · M", 10, MUTED)

func draw_tool_icon(icon: String, at: Vector2, color: Color, size: float = 30) -> void:
	toolbar.icon(icon,at,color,size)

func icon_button(area: Rect2, label: String, action: String, icon: String, active: bool = false) -> void:
	button(area,"",action,active)
	var color=INK if active else PAPER
	draw_tool_icon(icon,area.position+Vector2(21,area.size.y/2),color,20)
	text(area.position+Vector2(39,area.size.y/2+6),label,15,color)

func draw_jobs() -> void:
	for p in g.services.service_jobs:
		var job = g.services.service_jobs[p]
		var area = tile_area(p)
		if not area.intersects(WORLD): continue
		canvas.draw_rect(area.grow(-1),Color("efbe70"),false,2)
		rect(Rect2(area.position+Vector2(0,area.size.y-4),Vector2(area.size.x,4)),INK)
		rect(Rect2(area.position+Vector2(0,area.size.y-4),Vector2(area.size.x*(1-job.left/maxf(0.001,job.total)),4)),Color("efbe70"))
	for p in g.maintenance.jobs:
		var job = g.maintenance.jobs[p]
		var area = tile_area(p)
		if not area.intersects(WORLD): continue
		canvas.draw_rect(area,Color("efbe70"),false,2)
		if job.type == "logging": draw_tool_icon("tree",area.get_center(),Color("efbe70"))
		rect(Rect2(area.position+Vector2(0,area.size.y-4),Vector2(area.size.x,4)),INK)
		rect(Rect2(area.position+Vector2(0,area.size.y-4),Vector2(area.size.x*(1-job.left/maxf(0.001,job.total)),4)),Color("efbe70"))

func draw_panel() -> void:
	g.ui_hits.clear()
	rect(Rect2(0,0,1280,800),Color(0.03,0.08,0.06,0.86))
	card(Rect2(128,92,1024,614))
	var titles = {"notices":"Avisos e incidencias", "catalog":"Construye tu red", "menu":"Tu región", "cities":"Ciudades", "map":"Mapa de la región", "stats":"Estadísticas", "accounts":"Contabilidad", "info":"Tu selección", "help":"Cómo jugar", "infrastructure":"Rotondas y semáforos", "signal":"Configurar semáforo","objectives":"Objetivos y progresión","network":"Gestión de la red","scenarios":"Escenarios y récords"}
	text(Vector2(156,132),titles.get(g.panel,"Entre Ciudades"),25,GREEN)
	button(Rect2(1015,105,110,36),"Volver B","close")
	match g.panel:
		"menu":
			var descriptions = ["Conexiones, habitantes y viajes", "Explora y desplázate por la región", "Evolución de tu red y del tráfico", "Ingresos, gastos y movimientos", "Contratos, reputación y desbloqueos", "Tráfico, mantenimiento y emergencias", "Retos de 15–30 min y récords locales", "Consola de pruebas y ajustes rápidos"]
			for i in g.MENU_LABELS.size():
				var area = Rect2(166+(i%2)*486,164+int(i/2)*104,462,92)
				button(area,"",g.MENU_ACTIONS[i],g.menu_index==i)
				var color = INK if g.menu_index==i else PAPER
				text(area.position+Vector2(18,35),g.MENU_LABELS[i],23,color)
				text(area.position+Vector2(18,66),descriptions[i],14,color)
			button(Rect2(166,592,180,40),"Guardar · X","save")
			button(Rect2(360,592,180,40),"Cargar","load")
			button(Rect2(554,592,180,40),"Ayuda · Y" if g.last_pad else "Ayuda · H","help")
			button(Rect2(748,592,180,40),"Velocidad · "+str(g.SPEEDS[g.speed_index])+"×","speed")
			button(Rect2(942,592,180,40),"Avisos · %d"%g.event_notices.pending.size(),"event:open")
			text(Vector2(166,675),"Cruceta / stick elegir · A activar · X guardar · Y ayuda · B volver · ☰ cerrar · L3 pausa",14,MUTED)
		"objectives","network","scenarios": g.gameplay_ui.draw_panel(self)
		"notices": g.event_notices.draw_panel(self)
		"catalog": draw_catalog()
		"cities": draw_city_list()
		"map": draw_region_map()
		"stats": draw_stats()
		"accounts": draw_accounts()
		"info": draw_info()
		"signal": draw_signal_panel()
		"infrastructure": draw_infrastructure()
		_: draw_help()

func draw_city_list() -> void:
	var start = int(g.city_list_index/6)*6
	text(Vector2(164,169),"ESTADO ACTUAL · Las colas conservan su destino aunque se corte la conexión",13,MUTED)
	for i in range(start,mini(start+6,g.cities.size())):
		var city = g.cities[i]
		var at = Vector2(160,187+(i-start)*67)
		button(Rect2(at,Vector2(958,61)),"","city_select:"+str(i),i==g.city_list_index)
		var color = INK if i==g.city_list_index else PAPER
		var connected = not g.traffic.current_links.get(i,[]).is_empty()
		canvas.draw_circle(at+Vector2(18,20),4,Color("45785a") if connected else Color("b5795c"))
		text(at+Vector2(32,25),city.name+" · "+g.gameplay.PROFILES[g.gameplay.profile(city)],19,color)
		text(at+Vector2(530,25),"Conectada" if connected else "Sin conexión",15,color)
		text(at+Vector2(16,49),str(city.pop)+" hab. · "+str(city.received)+" viajes recibidos · "+str(city.accesses.size())+" accesos · "+str(g.traffic.city_queue(i))+" coches en cola",14,color)
		button(Rect2(at+Vector2(843,10),Vector2(100,39)),"Ir →","city_go:"+str(i))
	button(Rect2(160,608,166,38),"← Anterior · X","cities_prev")
	button(Rect2(340,608,166,38),"Siguiente · Y →","cities_next")
	text(Vector2(535,633),"Página "+str(int(start/6)+1)+" / "+str(maxi(1,int(ceil(g.cities.size()/6.0)))),15,MUTED)
	text(Vector2(160,675),"↑ ↓ seleccionar · A / Enter ir a la ciudad · B / Esc volver",14,MUTED)

func draw_region_map() -> void:
	var nav = g.navigator
	var area: Rect2 = nav.RECT
	rect(area,Color("132926"))
	if nav.texture != null:
		var intersection: Rect2 = nav.view().intersection(nav.image_view)
		if intersection.has_area():
			var dest = Rect2(nav.to_screen(intersection.position),intersection.size/nav.view().size*area.size)
			var source = Rect2((intersection.position-nav.image_view.position)/nav.image_view.size*Vector2(nav.IMAGE_SIZE),intersection.size/nav.image_view.size*Vector2(nav.IMAGE_SIZE))
			canvas.draw_texture_rect_region(nav.texture,dest,source)
	for pixel in nav.map_road_pixels(): rect(Rect2(Vector2(pixel),Vector2(2,2)),Color("d68d76") if nav.road_pixels[pixel] else GREEN)
	var occupied_labels: Array[Rect2] = []
	for i in g.cities.size():
		var city = g.cities[i]
		var at = nav.to_screen(Vector2(city.pos))
		if not area.grow(-8).has_point(at): continue
		canvas.draw_circle(at,6,INK)
		canvas.draw_circle(at,3,GREEN if not g.traffic.current_links.get(i,[]).is_empty() else Color("edbd88"))
		var label_at = at+Vector2(9,-9)
		var label_size = g.font.get_string_size(city.name,HORIZONTAL_ALIGNMENT_LEFT,-1,13)
		var label_box = Rect2(label_at-Vector2(2,13),label_size+Vector2(6,5))
		var clear = area.encloses(label_box)
		for previous in occupied_labels:
			if previous.intersects(label_box): clear = false; break
		if clear:
			occupied_labels.append(label_box)
			text(label_at,city.name,13,PAPER)
	var viewport = Rect2(nav.to_screen(g.camera-Vector2(640,400)/g.tile),Vector2(1280,800)/g.tile/nav.view().size*area.size).intersection(area)
	if viewport.has_area(): canvas.draw_rect(viewport,PAPER,false,1)
	var target = nav.to_screen(Vector2(nav.target))
	if area.grow(-8).has_point(target):
		canvas.draw_line(target-Vector2(10,0),target+Vector2(10,0),GREEN,2)
		canvas.draw_line(target-Vector2(0,10),target+Vector2(0,10),GREEN,2)
	text(Vector2(972,182),"DESTINO",12,MUTED)
	text(Vector2(972,212),str(nav.target.x)+", "+str(nav.target.y),17,GREEN)
	button(Rect2(970,236,156,42),"Ir aquí · A","map_go")
	button(Rect2(970,304,156,40),"Conocido · X","map_known")
	button(Rect2(970,354,156,40),"Todo · Y","map_all")
	button(Rect2(970,424,72,40),"+","zoom_in")
	button(Rect2(1054,424,72,40),"−","zoom_out")
	text(Vector2(972,505),str(g.explored.bounds.size.x)+" × "+str(g.explored.bounds.size.y),14,MUTED)
	text(Vector2(972,530),"Mapa en expansión",14,MUTED)
	if nav.dirty: text(Vector2(165,637),"Dibujando terreno…",12,PAPER)
	text(Vector2(156,675),"Stick / WASD mover · LT / RT zoom · Clic seleccionar, doble clic ir · B volver",14,MUTED)

func draw_stats() -> void:
	var connected = 0
	var population = 0
	var blocked = 0
	for i in g.cities.size():
		population += g.cities[i].pop
		if not g.traffic.current_links.get(i,[]).is_empty(): connected += 1
	for car in g.cars:
		if car.get("blocked",false): blocked += 1
	var values = [["CIUDADES",str(g.cities.size())],["CONECTADAS",str(connected)],["HABITANTES",str(population)],["VIAJES COMPLETADOS",str(g.trips)],["COCHES EN LA RED",str(g.cars.size())],["EN COLA EN CIUDADES",str(g.traffic.queued)],["COCHES BLOQUEADOS",str(blocked)],["CASILLAS DE CARRETERA",str(g.roads.size())],["ACCIDENTES",str(g.incidents.accidents)],["CASILLAS CON FUEGO",str(g.incidents.fire.size())],["CASILLAS CON NIEVE",str(g.incidents.snow.size())],["TIEMPO SIMULADO","%02d:%02d:%02d" % [int(g.elapsed/3600),int(g.elapsed/60)%60,int(g.elapsed)%60]]]
	for i in values.size():
		var at = Vector2(160+(i%3)*322,174+int(i/3)*112)
		card(Rect2(at,Vector2(308,98)),Color("243c35"))
		text(at+Vector2(16,27),values[i][0],12,MUTED)
		text(at+Vector2(16,70),values[i][1],30,GREEN)
	text(Vector2(162,675),"Región "+str(g.world_seed)+" · "+str(g.maintenance.demolished)+" casillas demolidas · "+str(g.maintenance.trees_cut)+" árboles talados",14,MUTED)

func draw_accounts() -> void:
	var book = g.accounts
	var values = [["INGRESOS",book.income()],["GASTOS",-book.expenses()],["RESULTADO",book.income()-book.expenses()],["TESORERÍA",g.money]]
	for i in values.size():
		var at = Vector2(160+i*244,166)
		card(Rect2(at,Vector2(230,78)),Color("243c35"))
		text(at+Vector2(12,23),values[i][0],12,MUTED)
		text(at+Vector2(12,58),book.format_money(values[i][1]),23,Color("efac95") if values[i][1]<0 else GREEN)
	text(Vector2(164,278),"POR CONCEPTO",12,MUTED)
	var row = 0
	for category in book.LABELS:
		if not book.totals.has(category): continue
		var label: String = book.LABELS[category]
		if category=="legacy": label="Anterior sin desglose"
		text(Vector2(164,306+row*22),label,12,PAPER)
		text(Vector2(350,306+row*22),book.format_money(book.totals[category]),12,GREEN if book.totals[category]>0 else Color("efac95"))
		row += 1
	text(Vector2(164,631),"Capital inicial: "+book.format_money(book.opening),14,MUTED)
	button(Rect2(548,264,570,34),"MOVIMIENTOS · "+["Todos","Ingresos","Gastos"][g.account_filter]+" · X / Y","account_filter")
	var entries = book.recent(g.account_filter)
	g.account_scroll = clampi(g.account_scroll,0,maxi(0,entries.size()-1))
	for i in range(g.account_scroll,mini(g.account_scroll+6,entries.size())):
		var entry = entries[i]
		var y = 324+(i-g.account_scroll)*44
		text(Vector2(554,y),"%02d:%02d" % [int(entry.at/60),int(entry.at)%60]+"  "+entry.description.substr(0,39),14,PAPER)
		text(Vector2(980,y+18),book.format_money(entry.amount),14,GREEN if entry.amount>0 else Color("efac95"))
	if entries.is_empty(): text(Vector2(560,345),"Aún no hay movimientos.",16,MUTED)
	button(Rect2(548,602,172,36),"↑ Anteriores","account_prev")
	button(Rect2(732,602,172,36),"↓ Siguientes","account_next")
	text(Vector2(164,675),"Cruceta / stick elegir · A filtrar / desplazar · LB/RB filtros · B volver",13,MUTED)

func draw_catalog() -> void:
	g.construction_catalog.draw(self)

func draw_info() -> void:
	var ci = g.city_at(g.cursor)
	text(Vector2(166, 186), "SELECCIÓN  %03d / %03d" % [g.cursor.x, g.cursor.y], 13, MUTED)
	if ci >= 0:
		var c = g.cities[ci]
		text(Vector2(166, 230), c.name, 29)
		text(Vector2(166, 308),g.gameplay.PROFILES[g.gameplay.profile(c)]+" · "+g.gameplay.profile_description(c),16,GREEN)
		var settlement = "Ciudad" if g.CityDesign.is_urban(c) else "Pueblo"
		text(Vector2(166, 268), settlement + " · " + str(c.pop) + " habitantes · " + str(c.received) + " viajes · " + str(c.accesses.size()) + " accesos", 18, GREEN)
	elif g.roads.has(g.cursor):
		var r = g.roads[g.cursor]
		text(Vector2(166, 230), g.Catalog.ROADS[r.kind].name, 26)
		text(Vector2(166, 268), "Incendio · Paso cortado" if g.incidents.fire.has(g.cursor) else "En obras" if r.work > 0 else ("Cerrada al tráfico" if r.closed else "Abierta al tráfico"), 19, Color("f5b790") if r.closed or g.incidents.fire.has(g.cursor) else GREEN)
		text(Vector2(166, 302), "Conservación: " + str(int(r.hp)) + "%", 18)
		if r.work > 0: text(Vector2(166, 334), "Obra pendiente: %.1f s" % r.work, 18)
	else:
		text(Vector2(166, 232), ["Pradera", "Río", "Bosque", "Montaña", "Montaña"][g.ground(g.cursor)], 26)
	text(Vector2(166, 409), "TU RED", 13, MUTED)
	text(Vector2(166, 451), str(g.cities.size()) + " ciudades     " + str(g.cars.size()) + " coches     " + str(g.trips) + " viajes completados", 21)
	text(Vector2(166, 492), "Ingresos " + g.cash(g.earned) + " · Accidentes " + str(g.incidents.accidents) + " · Pérdidas " + g.cash(g.incidents.accident_losses), 21, GREEN)
	text(Vector2(166, 543), "En espera en ciudades: " + str(g.traffic.queued) + " · Día " + str(1 + int(g.elapsed / 60)) + " · Región " + str(g.world_seed) + " · Mapa en expansión", 16, MUTED)
	button(Rect2(166, 606, 264, 44), "Mostrar / ocultar mapa  M", "map")

func draw_help() -> void:
	var lines = [
		"Mueve el cursor con WASD, flechas, stick o cruceta.",
		"Cada carretera ocupa 1 casilla. Sus carriles determinan su anchura visual.",
		"A / Enter fija el inicio. Mueve el cursor y confirma el tramo con A / Enter.",
		"Las obras tienen franjas ámbar. Los cierres, barreras rojas y una cruz.",
		"La reparación cierra el tramo, espera a los coches y lo reabre al terminar.",
		"Conecta las calles y los accesos señalados de las ciudades.",
		"Los coches viajan y pagan al llegar: verás el ingreso junto a la ciudad.",
		"El fuego corta y destruye las vías. Envía bomberos y reconstruye las quemadas.",
		"Catálogo → Señales. Gira con R / X y coloca o retira con Enter / A.",
		"Zoom: LT / RT, rueda o + / −. LB / RB recorre las siete herramientas.",
		"Mayús mover rápido · Espacio / L3 pausa · F velocidad · G / R3 siguiente ciudad.",
		"F2 avisos · I inspección · M / View mapa · 8 / F10 / ☰ menú · B / Esc cancelar.",
		"K objetivos · C inspeccionar coche · L capas · Ctrl+Z deshacer · Menú: Red y servicios."
	]
	for i in lines.size(): text(Vector2(166, 191 + i * 38), lines[i], 18, PAPER)

func draw_city_accesses() -> void:
	for c in g.cities:
		for access in c.accesses:
			var at = g.screen(Vector2(access.end))
			if not Rect2(0, 85, 1210, 600).has_point(at): continue
			var color = GREEN if g.road_open(access.gate) else Color("ff8877")
			canvas.draw_arc(at, maxf(5, g.tile * 0.36), 0, TAU, 16, Color(color, 0.8), 2)
			var direction = Vector2(access.dir)
			var side = Vector2(-direction.y, direction.x)
			var tip = at + direction * g.tile * 0.23
			canvas.draw_polyline(PackedVector2Array([tip - direction * 6 + side * 5, tip, tip - direction * 6 - side * 5]), color, 2)
			if g.cursor == access.end and not g.roads.has(g.cursor):
				card(Rect2(at + Vector2(16, -42), Vector2(190, 30)))
				text(at + Vector2(27, -21), "ACCESO · " + c.name, 14, color)

func roundabout_texture(center: Vector2i, kind: int) -> Texture2D:
	var base: Texture2D = road_conditions[kind].roundabout
	if base == null: return null
	var key = [kind]
	var approaches: Array = []
	for i in Connections.DIRECTIONS.size():
		var direction: Vector2i = Connections.DIRECTIONS[i]
		var neighbour = center+direction*2
		if not g.edge_allowed(center+direction,neighbour): continue
		var texture: Texture2D
		var turns = i%2
		var other = g.incidents.roundabout_cells.get(neighbour,g.NO_CELL)
		if other!=g.NO_CELL:
			if other!=center+direction*3: continue
			# Ambas rotondas comparten el mismo perfil cuando son contiguas.
			var other_kind: int = g.incidents.roundabouts[other].kind
			texture = road_variants[mini(kind,other_kind)].straight
		else:
			var shape = node_shapes.get(neighbour,Connections.shape_for(0,g.roads[neighbour].axis))
			turns = shape.turns
			texture = road_texture(neighbour,shape.shape)
		if texture == null or (texture==road_variants[kind].straight and turns==i%2): continue
		key.append_array([i,texture.get_instance_id(),turns])
		approaches.append([i,texture,turns])
	if approaches.is_empty(): return base
	if roundabout_variants.has(key): return roundabout_variants[key]
	var pixels = base.get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	for arm in approaches:
		RoundaboutArt.fit_arm(pixels,arm[1].get_image(),arm[0],arm[2])
	var fitted = ImageTexture.create_from_image(pixels)
	if roundabout_variants.size()>=MAX_ROUNDABOUT_VARIANTS:
		roundabout_variants.erase(roundabout_variants.keys()[0])
	roundabout_variants[key]=fitted
	return fitted

func draw_roundabouts() -> void:
	for center in g.incidents.roundabouts:
		var size = g.tile * 3
		var area = Rect2(g.screen(Vector2(center)) - Vector2.ONE * size / 2, Vector2.ONE * size)
		if not area.intersects(Rect2(-size,-size,1280+size*2,800+size*2)): continue
		var texture = roundabout_texture(center,g.incidents.roundabouts[center].kind)
		if texture == null: continue
		var alpha = 1.0
		for p in g.incidents.ring_cells(center): alpha = minf(alpha,1.0-g.incidents.fade(p))
		canvas.draw_texture_rect(texture,area,false,Color(1,1,1,alpha))

func draw_environment() -> void:
	for p in g.incidents.snow:
		var area = tile_area(p)
		if not area.intersects(Rect2(-g.tile,-g.tile,1280+g.tile*2,800+g.tile*2)): continue
		var texture = environment.snow[posmod(p.x * 7 + p.y * 13,4)]
		if texture != null: canvas.draw_texture_rect(texture,area,false,Color(1,1,1,0.68))
	for p in g.incidents.fire:
		var area = tile_area(p).grow(g.tile*0.12)
		if not area.intersects(Rect2(-g.tile,-g.tile,1280+g.tile*2,800+g.tile*2)): continue
		var texture = environment.fire[posmod(int(g.visual_clock*7)+p.x+p.y,4)]
		if texture != null: canvas.draw_texture_rect(texture,area,false)
	for p in g.incidents.signals:
		if not g.roads.has(p) or g.is_bridge(p): continue
		var at = g.screen(Vector2(p))
		var enabled: bool = g.incidents.signals[p].enabled
		var shape = node_shapes.get(p,{"shape":"straight","turns":1 if g.roads[p].axis else 0})
		var horizontal: bool = shape.turns % 2 == 1 if shape.shape == "straight" else g.roads[p].axis
		var green = g.incidents.signal_allows(p,Vector2i.RIGHT if horizontal else Vector2i.UP)
		var across = Vector2.DOWN if horizontal else Vector2.RIGHT
		var lamp = Vector2.RIGHT if horizontal else Vector2.DOWN
		for side in [-1,1]:
			var pos = at + across*side*g.tile*0.34
			var size = Vector2(12,6) if horizontal else Vector2(6,12)
			canvas.draw_rect(Rect2(pos-size/2,size),Color("172c2c"))
			canvas.draw_circle(pos-lamp*3,2,Color("ef6254") if enabled and not green else Color("43514c"))
			canvas.draw_circle(pos+lamp*3,2,Color("b3e87d") if enabled and green else Color("43514c"))

func sign_icon(id: String, center: Vector2, side: float, heading: int = 0) -> void:
	var spec = g.RoadSigns.definition(id)
	if spec.is_empty(): return
	var symbol: String = spec.symbol
	if id in ["one_way","direction"]: symbol = g.RoadSigns.ARROWS[heading]
	var ink = Color("182623")
	var white = Color("fff8e3")
	var red = Color("cb4042")
	var radius = side*0.5
	match spec.family:
		"Prioridad":
			if id=="stop":
				var outline = PackedVector2Array()
				for i in 8: outline.append(center+Vector2.from_angle((i+0.5)*TAU/8)*radius)
				canvas.draw_colored_polygon(outline,red)
				ink=white
			elif id=="priority":
				canvas.draw_colored_polygon(PackedVector2Array([center+Vector2.UP*radius,center+Vector2.RIGHT*radius,center+Vector2.DOWN*radius,center+Vector2.LEFT*radius]),white)
				ink=Color("d7a830")
			else:
				var vertices = PackedVector2Array([Vector2(-0.5,-0.37),Vector2(0.5,-0.37),Vector2(0,0.5)])
				for i in 3: vertices[i]=center+vertices[i]*side
				canvas.draw_colored_polygon(vertices,red)
				for i in 3: vertices[i]=center+(vertices[i]-center)*0.70
				canvas.draw_colored_polygon(vertices,white)
				return
		"Prohibición":
			canvas.draw_circle(center,radius,red)
			if id=="no_entry": ink=white
			else: canvas.draw_circle(center,radius*0.76,white)
		"Obligación":
			if id=="one_way": canvas.draw_rect(Rect2(center-Vector2.ONE*radius,Vector2.ONE*side),Color("24649b"))
			else: canvas.draw_circle(center,radius,Color("24649b"))
			ink=white
		"Peligro","Temporal":
			var vertices = PackedVector2Array([Vector2(0,-0.53),Vector2(0.55,0.43),Vector2(-0.55,0.43)])
			for i in 3: vertices[i]=center+vertices[i]*side
			canvas.draw_colored_polygon(vertices,red)
			for i in 3: vertices[i]=center+(vertices[i]-center)*0.76
			canvas.draw_colored_polygon(vertices,Color("f4c858") if spec.family=="Temporal" else white)
			center.y += side*0.08
		_:
			canvas.draw_rect(Rect2(center-Vector2.ONE*radius,Vector2.ONE*side),Color("24649b"))
			ink=white
	var size = maxi(5,roundi(side*(0.25 if id=="stop" else (0.39 if symbol.length()>1 else 0.54))))
	var width = g.font.get_string_size(symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	text(center+Vector2(-width/2,(g.font.get_ascent(size)-g.font.get_descent(size))/2),symbol,size,ink)
	if id in ["no_left","no_right","no_u","no_overtaking"]:
		canvas.draw_line(center+Vector2(-0.57,0.57)*radius,center+Vector2(0.57,-0.57)*radius,red,maxf(1.0,side*0.07),true)

func draw_signage() -> void:
	if g.tile<12: return
	var viewport = Rect2(-g.tile,-g.tile,1280+g.tile*2,800+g.tile*2)
	var size = clampf(g.tile*0.32,10.0,29.0)
	for p in g.signage.placed:
		var center: Vector2 = g.screen(Vector2(p))
		if not viewport.has_point(center) or not g.roads.has(p): continue
		var counts = [0,0,0,0]
		for sign in g.signage.placed[p]:
			var direction = Vector2(g.RoadSigns.DIRECTIONS[sign.direction])
			var offset = Vector2(-direction.y,direction.x)*g.tile*0.38
			var at = center+offset+direction*(-g.tile*0.27+counts[sign.direction]*(size+2))
			counts[sign.direction] += 1
			canvas.draw_line(at,at+Vector2(0,size*0.6),Color("686c60"),maxf(1.0,size*0.09))
			sign_icon(sign.id,at,size,sign.direction)

func draw_tooltip() -> void:
	tooltip_rect = Rect2()
	var p: Vector2i = g.hover_cell if g.inside(g.hover_cell) else g.cursor
	var center = g.incidents.roundabout_cells.get(p,p)
	var is_roundabout: bool = g.incidents.roundabouts.has(center)
	var actual = p
	if not g.roads.has(p):
		if not is_roundabout: return
		actual = g.incidents.ring_cells(center)[0]
	if not g.roads.has(actual): return
	var road = g.roads[actual]
	var spec = g.Catalog.ROADS[road.kind]
	var lines: Array = []
	var signs: Array = g.signage.placed.get(p,[])
	for sign in signs.slice(0,3):
		lines.append(g.RoadSigns.definition(sign.id).name+" · "+g.RoadSigns.ARROWS[sign.direction])
	if signs.size()>3: lines.append("+%d señales"%[signs.size()-3])
	var status = "INCENDIO · PASO CORTADO" if g.incidents.fire.has(p) else "DEMOLIENDO" if road.get("demolishing",false) else ("EN OBRAS" if road.work > 0 else ("CERRADA" if road.closed else "ABIERTA"))
	lines.append(status + (" · Rotonda 3×3" if is_roundabout else ""))
	lines.append(str(spec.lanes) + " carriles · " + str(g.density.get(actual,0)) + "/" + str(g.traffic.capacity(actual)) + " coches")
	lines.append("Conservación " + str(int(road.hp)) + "% · " + str(int(spec.speed*15)) + " km/h")
	if g.incidents.fire.has(actual): lines.append("Fuego: −%.1f puntos/s · Envía bomberos"%g.WorldSettings.FIRE_ROAD_DAMAGE)
	elif g.traffic.junctions.collision_risk(actual): lines.append("Cruce sin regular · Riesgo de colisión")
	elif g.traffic.junctions.uncontrolled(actual): lines.append("Cruce regulado por señales de prioridad")
	lines.append("Accidentes " + str(int(round(g.incidents.risk(actual)*100))) + "%% cada %.1f s" % g.incidents.ACCIDENT_INTERVAL)
	if g.incidents.fire.has(actual) or g.incidents.snow.has(actual):
		lines.append(("Fuego +%d%%  " % roundi(g.WorldSettings.FIRE_ACCIDENT_RISK*100) if g.incidents.fire.has(actual) else "") + ("Nieve +%d%%" % roundi(g.WorldSettings.SNOW_ACCIDENT_RISK*100) if g.incidents.snow.has(actual) else ""))
	if g.incidents.protected_access(actual):
		lines.append("Calle urbana protegida" if road.has("urban_city") else "Acceso protegido frente al abandono")
		var city: int = road.get("access_city",road.get("urban_city",-1))
		if city >= 0: lines.append(g.cities[city].name + " · Cola: " + str(g.traffic.city_queue(city)))
	else:
		var unused = g.incidents.unused_seconds(actual)
		lines.append("Sin uso: " + str(int(unused)) + " s · Abandono: %.1f s" % g.incidents.rules.unused_start)
		if g.incidents.fade(actual) > 0: lines.append("Desapareciendo " + str(int(g.incidents.fade(actual)*100)) + "%")
	if road.get("reserve",false): lines.append("Reserva · Protegida del abandono")
	if g.services.service_jobs.has(actual):
		var job = g.services.service_jobs[actual]
		lines.append("Cerrada · esperando a que salgan los coches" if g.services.evacuating(actual) else "Mantenimiento %s: %.1f s"%["parcial" if job.partial else "con cierre",job.left])
	if road.work > 0: lines.append("Obra pendiente: %.1f s" % road.work)
	var has_signal = g.incidents.signals.has(actual)
	var height = 51 + lines.size()*23 + (42 if has_signal else 0)
	var at = g.screen(Vector2(p)) + Vector2(g.tile/2+18,-height-14)
	if g.anchor!=g.NO_CELL: at.x -= 350 + g.tile
	at.x = clampf(at.x,16,928)
	at.y = clampf(at.y,90,680-height)
	tooltip_rect = Rect2(at,Vector2(336,height))
	card(tooltip_rect,Color("19342e"))
	var name: String = spec.name
	if name.length()>30:name=name.substr(0,28)+"…"
	text(at+Vector2(14,28),name,18,GREEN)
	for i in lines.size():text(at+Vector2(14,52+i*23),lines[i],14,PAPER)
	if has_signal:
		button(Rect2(at+Vector2(12,height-40),Vector2(312,32)),"Configurar semáforo · T","signal_config:"+str(actual.x)+":"+str(actual.y))
	var point = g.screen(Vector2(p))
	if point.y > at.y+height:
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(point.x-5,at.y+height),Vector2(point.x+5,at.y+height),Vector2(point.x,at.y+height+7)]),Color("19342e"))

func draw_infrastructure() -> void:
	var names = ["Carretera normal · 1 casilla", "Rotonda · 3 × 3 casillas", "Semáforo configurable · sobre carretera"]
	for i in 3:
		button(Rect2(200,190+i*92,880,64),names[i],"mode:"+["road","roundabout","signal"][i],g.infrastructure_index==i)
	text(Vector2(202,506),"La rotonda ocupa nueve casillas y deja una isla central sin tráfico.",17,MUTED)
	text(Vector2(202,540),"Desvía el tráfico, vacía el espacio y cierra las vías antes de convertirlas.",17,MUTED)
	text(Vector2(202,594),"↑↓ / cruceta elegir · A / Enter aceptar · O rotonda · T semáforo · P normal",15,GREEN)

func draw_signal_panel() -> void:
	if not g.incidents.signals.has(g.cursor): return
	var light = g.incidents.signals[g.cursor]
	var names = ["Verde norte / sur: %.0f s" % light.ns, "Verde este / oeste: %.0f s" % light.ew, "Semáforo: " + ("ENCENDIDO" if light.enabled else "APAGADO")]
	for i in 3:
		button(Rect2(224,195+i*92,680,60),names[i],"signal:"+("ns+" if i==0 else ("ew+" if i==1 else "toggle")),g.signal_index==i)
		if i<2:
			button(Rect2(918,195+i*92,60,60),"−","signal:"+("ns-" if i==0 else "ew-"))
			button(Rect2(990,195+i*92,60,60),"+","signal:"+("ns+" if i==0 else "ew+"))
	var phase = "APAGADO · cruce sin regular" if not light.enabled else ("VERDE norte / sur" if g.incidents.signal_allows(g.cursor,Vector2i.UP) else "VERDE este / oeste")
	text(Vector2(225,522),phase,23,GREEN)
	text(Vector2(225,566),"Los coches esperan antes de entrar en la casilla mientras su dirección está roja.",16,MUTED)
	text(Vector2(225,619),"↑↓ elegir · ←→ ajustar · A / Enter aumentar o activar · B / Esc cerrar",16,PAPER)
