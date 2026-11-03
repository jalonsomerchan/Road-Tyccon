extends RefCounted
## Presentación: los sprites, la interfaz y los efectos no alteran la simulación.
var g
var canvas
var terrain_cache
var scenery_atlas: Texture2D
var scenery_atlas_size = Vector2.ONE
var atlas_white_uv = Vector2.ZERO
var sheets: Dictionary = {}
const Connections = preload("res://scripts/road_connections.gd")
var road_variants: Array = []
var road_conditions: Array = []
var environment: Dictionary = {}
var tooltip_rect = Rect2()
var visible_car_tickets: Array = []
var road_layout_revision = -1
var junctions: Array = []
var junction_coverage: Dictionary = {}
var node_shapes: Dictionary = {}
const INK = Color("172c2c")
const PAPER = Color("f2edda")
const MUTED = Color("a0b4a4")
const GREEN = Color("d3e69b")
const WORLD = Rect2(0, 84, 1280, 604)

func _init(game) -> void:
	g = game
	canvas = game
	for family in ["terrain", "roads", "props"]:
		var frames: Array = []
		for i in 16:
			var path = "res://assets/sprites/%s/sprite-%d.png" % [family, i + 1]
			frames.append(load(path) if ResourceLoader.exists(path) else null)
		sheets[family] = frames
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
	for name in g.CityDesign.BUILDINGS: sheets.buildings.append(load("res://assets/sprites/city-v2/"+name+".png"))
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

func batch_scenery_atlas() -> void:
	# Una textura compartida permite a Godot agrupar miles de sprites sin cambiar de textura.
	var families = ["terrain","props","buildings","city_streets"]
	var count = 1
	for family in families: count += sheets[family].size()
	scenery_atlas_size = Vector2(1024,ceilf(count/16.0)*64)
	var atlas_image = Image.create(int(scenery_atlas_size.x),int(scenery_atlas_size.y),false,Image.FORMAT_RGBA8)
	var index = 0
	var regions: Array = []
	for family in families:
		for i in sheets[family].size():
			var source = sheets[family][i]
			if source == null: continue
			var pixels: Image = source.get_image()
			if pixels.is_compressed(): pixels.decompress()
			pixels.convert(Image.FORMAT_RGBA8)
			var at = Vector2i((index%16)*64,int(index/16)*64)
			atlas_image.blit_rect(pixels,Rect2i(0,0,64,64),at)
			regions.append({"family":family,"index":i,"at":at})
			index += 1
	var white_at = Vector2i((index%16)*64,int(index/16)*64)
	atlas_image.fill_rect(Rect2i(white_at,Vector2i(64,64)),Color.WHITE)
	atlas_white_uv = (Vector2(white_at)+Vector2(32.5,32.5))/scenery_atlas_size
	var atlas = ImageTexture.create_from_image(atlas_image)
	scenery_atlas = atlas
	for region in regions:
		var frame = AtlasTexture.new()
		frame.atlas = atlas
		frame.region = Rect2(Vector2(region.at),Vector2(64,64))
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
	rect(area, GREEN if active else Color("263d38"))
	text(area.position + Vector2(12, area.size.y / 2 + 6), value, 16, INK if active else PAPER)
	g.ui_hits.append({"rect":area, "action":action})

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
	if g.at_title:
		tooltip_rect = Rect2()
		draw_title()
		return
	if terrain_cache == null: terrain_cache = preload("res://scripts/terrain_render_cache.gd").new(g)
	g.explore_around(g.camera)
	terrain_cache.prepare()
	draw_jobs()
	draw_environment()
	g.gameplay_ui.draw_world(self)
	draw_cars()
	draw_cities()
	draw_city_accesses()
	draw_selection()
	draw_income()
	draw_hud()
	g.gameplay_ui.draw_hud(self)
	if g.show_minimap: draw_minimap()
	if g.panel != "":
		tooltip_rect = Rect2()
		draw_panel()
	else: draw_tooltip()

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
	var detail = "Crea una nueva región y empieza con 80.000 €."
	if g.title_index==1: detail = "Recupera tu región, sus carreteras y sus viajes."
	elif g.title_index==2: detail = "Hasta la próxima conexión."
	if not g.title_has_save and g.title_index==0: detail = "Empieza tu primera región con 80.000 €."
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
			sprite("terrain", 2 if variation == 0 else (3 if variation == 7 else 0), Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * cell))
	# Un río ancho y suavemente cambiante atraviesa la región; la carretera lo cruza por un puente.
	var river_columns: Array[int] = []
	for y in 13:
		var center = 12 + roundi(sin(y * 0.48) * 1.4)
		river_columns.append(center)
		for x in range(center - 1, center + 2):
			sprite("terrain", 5, Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * cell))
	# Rocas y árboles, colocados con una pauta fija para que el menú no parpadee.
	for y in 13:
		for x in 20:
			var p = Vector2i(x, y)
			var river = river_columns[y]
			if abs(x - river) <= 1 or y == 7 or (x >= 9 and x <= 13 and y >= 4 and y <= 10): continue
			if (x * 17 + y * 31) % 19 == 0:
				sprite("props", 9 if (x + y) % 2 == 0 else 10, Rect2(origin + Vector2(p) * cell, Vector2.ONE * cell))
			elif (x * 13 + y * 23) % 5 <= 1:
				var tree = 6 + posmod(x * 7 + y * 11, 3)
				var size = cell * (0.86 + float(posmod(x + y * 3, 4)) * 0.06)
				sprite("props", tree, Rect2(origin + Vector2(p) * cell + (Vector2.ONE * cell - Vector2.ONE * size) / 2, Vector2.ONE * size))
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
		sprite("buildings", posmod(i * 3 + p.x, 8), Rect2(origin + Vector2(p) * cell, Vector2.ONE * cell))
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
	return Rect2((g.screen(Vector2(p)) - Vector2.ONE * g.tile / 2).floor(), Vector2.ONE * ceilf(g.tile + 0.2))

func draw_connection(kind: int, shape: String, area: Rect2, turns: int) -> void:
	var texture = road_variants[kind][shape]
	if texture == null: return
	if turns == 0:
		canvas.draw_texture_rect(texture, area, false)
	else:
		canvas.draw_set_transform(area.get_center(), turns * PI / 2)
		canvas.draw_texture_rect(texture, Rect2(-area.size / 2, area.size), false)
		canvas.draw_set_transform(Vector2.ZERO)

func prepare_road_layout() -> void:
	if road_layout_revision == g.road_revision: return
	road_layout_revision = g.road_revision
	junctions.clear()
	junction_coverage.clear()
	node_shapes.clear()
	for p in g.roads:
		var r = g.roads[p]
		node_shapes[p] = Connections.shape_for(Connections.mask_for(p, g.roads, g.city_cells, g.city_connectors), r.axis)

func draw_road(p: Vector2i, area: Rect2) -> void:
	var r = g.roads[p]
	if g.incidents.roundabout_cells.has(p): return
	var shape = node_shapes.get(p, Connections.shape_for(0, r.axis))
	var state = g.incidents.visual_state(p)
	if shape.shape == "straight" and state != "" and road_conditions[r.kind][state] != null:
		var alpha = 1.0 - g.incidents.fade(p)
		canvas.draw_set_transform(area.get_center(), shape.turns * PI / 2)
		canvas.draw_texture_rect(road_conditions[r.kind][state], Rect2(-area.size / 2, area.size), false, Color(1,1,1,alpha))
		canvas.draw_set_transform(Vector2.ZERO)
	else:
		draw_connection(r.kind, shape.shape, area, shape.turns)

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
		var key = Vector2i((pos/size).floor())
		var clear = true
		for dy in range(-1,2):
			for dx in range(-1,2):
				for other in occupied.get(key+Vector2i(dx,dy),[]):
					if bounds.intersects(other): clear=false; break
		if not clear: continue
		if not occupied.has(key): occupied[key]=[]
		occupied[key].append(bounds)
		result.append({"car":car,"pos":pos,"direction":direction,"angle":angle,"size":size,"bounds":bounds,"sprite":posmod(car.get("sprite_id",car.get("color",0)),8)})
	return result

func draw_cars() -> void:
	visible_car_tickets.clear()
	for item in car_draw_list():
		var car = item.car
		var pos: Vector2 = item.pos
		var size: float = item.size
		visible_car_tickets.append(car.get("ticket",0))
		# Las texturas de coches se mantienen independientes del atlas del terreno.
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
	if g.anchor!=g.NO_CELL:
		var distance: Vector2i = (g.cursor-g.anchor).abs()
		var count = distance.x+distance.y+1
		var tag = area.position + Vector2(g.tile + 10, -8)
		card(Rect2(tag, Vector2(190, 32)))
		text(tag + Vector2(10, 22), str(count) + " secciones · " + g.cash(count * g.Catalog.ROADS[g.kind].cost), 14, GREEN)

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
	button(Rect2(891, 12, 96, 36), "Ⅱ Pausa" if g.speed_index == 0 else "▶ " + str(g.SPEEDS[g.speed_index]) + "×", "speed", g.speed_index == 0)
	button(Rect2(1000, 12, 132, 36), "Región · M", "map")
	var menu_area = Rect2(1144, 12, 116, 36)
	button(menu_area, "", "menu", g.panel == "menu")
	draw_tool_icon("menu", menu_area.position + Vector2(20, 18), INK if g.panel == "menu" else PAPER)
	text(menu_area.position + Vector2(36, 24), "Menú", 15, INK if g.panel == "menu" else PAPER)
	# Dock centrado: cinco herramientas frecuentes y el selector de carretera elegido.
	var dock = Rect2(140, 690, 1000, 90)
	card(dock)
	var visible_tools = [0, 2, 3, 4, 1]
	var labels = ["Construir", "Reparar", "Destruir", "Talar", "Cerrar"]
	var tool_width = 116.0
	for i in visible_tools.size():
		var index: int = visible_tools[i]
		var area = Rect2(152 + i * 124, 700, tool_width, 48)
		var active = g.tool == index
		button(area, "", "tool:" + str(index), active)
		draw_tool_icon(g.TOOLS[index].icon, area.position + Vector2(23, 24), INK if active else PAPER)
		text(area.position + Vector2(42, 29), labels[i], 14, INK if active else PAPER)
	rect(Rect2(782, 700, 1, 48), Color("47605a"))
	var selector = Rect2(798, 700, 328, 58)
	button(selector, "", "catalog", g.panel == "catalog")
	if g.construction_mode == "roundabout":
		var roundabout = road_conditions[g.kind].roundabout
		if roundabout != null: canvas.draw_texture_rect(roundabout, Rect2(809, 708, 42, 42), false)
	else:
		sprite("roads", g.kind, Rect2(807, 710, 38, 38))
	text(Vector2(855, 723), g.Catalog.ROADS[g.kind].name, 15, INK if g.panel == "catalog" else PAPER)
	text(Vector2(855, 744), str(g.Catalog.ROADS[g.kind].lanes) + (" carril · " if g.Catalog.ROADS[g.kind].lanes == 1 else " carriles · ") + g.cash(g.Catalog.ROADS[g.kind].cost), 12, INK if g.panel == "catalog" else MUTED)
	canvas.draw_polyline(PackedVector2Array([Vector2(1109, 721), Vector2(1114, 726), Vector2(1119, 721)]), INK if g.panel == "catalog" else GREEN, 2)
	var hint = "Enter inicio · Y catálogo · R giro" if g.anchor==g.NO_CELL else "Enter construir · Esc cancelar · R giro"
	if g.last_pad: hint = "A inicio · Y catálogo · X giro" if g.anchor==g.NO_CELL else "A construir · B cancelar · X giro"
	if g.TOOLS[g.tool].id == "repair_route": hint = "Enter reparar · U mejorar al tipo elegido" if not g.last_pad else "A reparar · X mejorar al tipo elegido"
	if g.TOOLS[g.tool].id == "demolish_route": hint = "Enter destruir · 25 % del precio · 5 s"
	if g.TOOLS[g.tool].id == "fell_trees": hint = "Enter talar · 20 € · 3 s"
	if g.TOOLS[g.tool].id == "close_route": hint = "Enter cerrar o abrir la vía seleccionada"
	text(Vector2(154, 772), hint, 12, MUTED)
	card(Rect2(1216,324,44,140))
	button(Rect2(1218,326,40,40),"+","zoom_in")
	text(Vector2(1220,395),str(int(g.zoom_target/32*100))+"%",12,MUTED)
	button(Rect2(1218,416,40,40),"−","zoom_out")
	if g.notice_time > 0:
		var width = minf(940, g.font.get_string_size(g.notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 32)
		card(Rect2(20, 72, width, 34), Color("243e34"))
		text(Vector2(36, 95), g.notice, 15, Color("f0edcf"))

func draw_minimap() -> void:
	card(Rect2(20, 492, 184, 184))
	var low = Vector2(g.cursor)
	var high = low
	for c in g.cities:
		low = low.min(Vector2(c.pos))
		high = high.max(Vector2(c.pos))
	low -= Vector2.ONE * 150
	high += Vector2.ONE * 150
	var span = maxf(600, maxf(high.x - low.x, high.y - low.y))
	for c in g.cities:
		var p = Vector2(29, 501) + (Vector2(c.pos) - low) / span * 166
		rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Color("f6dd9f"))
	for p in g.roads:
		rect(Rect2(Vector2(29, 501) + (Vector2(p) - low) / span * 166, Vector2(1, 1)), GREEN)
	var current = Vector2(29, 501) + (g.camera - low) / span * 166
	canvas.draw_rect(Rect2(current - Vector2(640, 400) / g.tile / span * 166, Vector2(1280, 800) / g.tile / span * 166), GREEN, false, 1)
	text(Vector2(32, 515), "REGIÓN CONOCIDA · M", 10, MUTED)

func draw_tool_icon(icon: String, at: Vector2, color: Color) -> void:
	match icon:
		"road":
			if g.construction_mode == "roundabout":
				canvas.draw_texture_rect(road_conditions[g.kind].roundabout,Rect2(at-Vector2(22,22),Vector2(44,44)),false)
			else: sprite("roads",g.kind,Rect2(at-Vector2(22,22),Vector2(44,44)))
			if g.construction_mode == "signal":
				rect(Rect2(at+Vector2(8,-18),Vector2(9,26)),INK)
				canvas.draw_circle(at+Vector2(12,-11),3,Color("e7896f"))
				canvas.draw_circle(at+Vector2(12,0),3,GREEN)
		"close":
			rect(Rect2(at-Vector2(24,7),Vector2(48,12)),color)
			for x in [-17,0,17]: canvas.draw_line(at+Vector2(x-4,-6),at+Vector2(x+4,4),INK if color==PAPER else Color("a6664c"),4)
			for x in [-18,18]: rect(Rect2(at+Vector2(x-2,5),Vector2(4,15)),color)
		"repair":
			canvas.draw_line(at+Vector2(-16,17),at+Vector2(11,-10),color,8)
			canvas.draw_arc(at+Vector2(12,-11),10,0.2,4.5,12,color,6)
			canvas.draw_circle(at+Vector2(-16,17),3,INK if color==PAPER else GREEN)
		"demolish":
			canvas.draw_line(at+Vector2(-13,18),at+Vector2(9,-12),color,6)
			canvas.draw_line(at+Vector2(-8,-20),at+Vector2(25,0),color,12)
		"tree":
			rect(Rect2(at+Vector2(-3,2),Vector2(6,19)),color)
			canvas.draw_colored_polygon(PackedVector2Array([at+Vector2(0,-22),at+Vector2(-21,8),at+Vector2(21,8)]),color)
			canvas.draw_line(at+Vector2(8,17),at+Vector2(25,0),Color("b5795c"),4)
		"menu":
			for y in [-12,0,12]: rect(Rect2(at+Vector2(-18,y-2),Vector2(36,4)),color)

func draw_jobs() -> void:
	for p in g.maintenance.jobs:
		var job = g.maintenance.jobs[p]
		var area = tile_area(p)
		if not area.intersects(WORLD): continue
		canvas.draw_rect(area,Color("efbe70"),false,2)
		if job.type == "logging": draw_tool_icon("tree",area.get_center(),Color("efbe70"))
		rect(Rect2(area.position+Vector2(0,area.size.y-4),Vector2(area.size.x,4)),INK)
		rect(Rect2(area.position+Vector2(0,area.size.y-4),Vector2(area.size.x*(1-job.left/job.total),4)),Color("efbe70"))

func draw_panel() -> void:
	g.ui_hits.clear()
	rect(Rect2(0,0,1280,800),Color(0.03,0.08,0.06,0.86))
	card(Rect2(128,92,1024,614))
	var titles = {"catalog":"Elige tu carretera", "menu":"Tu región", "cities":"Ciudades", "map":"Mapa de la región", "stats":"Estadísticas", "accounts":"Contabilidad", "info":"Tu selección", "help":"Cómo jugar", "infrastructure":"Rotondas y semáforos", "signal":"Configurar semáforo","objectives":"Objetivos y progresión","network":"Gestión de la red","scenarios":"Escenarios y récords"}
	text(Vector2(156,132),titles.get(g.panel,"Entre Ciudades"),25,GREEN)
	button(Rect2(1015,105,110,36),"Volver B","close")
	match g.panel:
		"menu":
			var descriptions = ["Conexiones, habitantes y viajes", "Explora y desplázate por la región", "Evolución de tu red y del tráfico", "Ingresos, gastos y movimientos", "Contratos, reputación y desbloqueos", "Tráfico, mantenimiento y emergencias", "Retos de 15–30 min y récords locales"]
			for i in g.MENU_LABELS.size():
				var area = Rect2(166+(i%2)*486,164+int(i/2)*104,462,92)
				button(area,"",g.MENU_ACTIONS[i],g.menu_index==i)
				var color = INK if g.menu_index==i else PAPER
				text(area.position+Vector2(18,35),g.MENU_LABELS[i],23,color)
				text(area.position+Vector2(18,66),descriptions[i],14,color)
			button(Rect2(166,592,180,40),"Guardar · X","save")
			button(Rect2(360,592,180,40),"Cargar · Y","load")
			button(Rect2(554,592,180,40),"Ayuda · H","help")
			button(Rect2(748,592,180,40),"Trucos · L3 / F8","cheats")
			text(Vector2(166,675),"Cruceta / stick elegir · A / Enter abrir · B / Esc volver",14,MUTED)
		"objectives","network","scenarios": g.gameplay_ui.draw_panel(self)
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
	text(Vector2(164,675),"Totales de toda la partida · Hasta 1.000 movimientos recientes · ↑ ↓ desplazar · B volver",13,MUTED)

func draw_catalog() -> void:
	for i in 3:
		button(Rect2(156+i*325,150,310,34),["Carretera","Rotonda · 3×3","Semáforo"][i],"mode:"+["road","roundabout","signal"][i],g.construction_mode==["road","roundabout","signal"][i])
	for i in g.Catalog.ROADS.size():
		var column = int(i / 12)
		var row = i % 12
		var spec = g.Catalog.ROADS[i]
		var area = Rect2(156 + column * 486, 195 + row * 36, 470, 33)
		button(area, "", "kind:" + str(i), i == g.kind)
		sprite("roads", i, Rect2(area.position + Vector2(5, 5), Vector2(26, 26)))
		var color = INK if i == g.kind else PAPER
		var unlocked = g.gameplay.unlocked(i)
		if not unlocked: color=MUTED
		text(area.position + Vector2(43, 14), spec.name+(" · N%d"%g.gameplay.road_tier(i) if not unlocked else ""), 15, color)
		text(area.position + Vector2(43, 29), (str(spec.lanes) + (" carril · " if spec.lanes == 1 else " carriles · ")) + str(int(spec.speed * 15)) + " km/h · cap. " + str(spec.cap) + " · " + g.cash(spec.cost), 12, color)
	text(Vector2(161, 669), "Cruceta / flechas elegir · A / Enter confirmar · X cambiar modo · B volver", 15, MUTED)

func draw_info() -> void:
	var ci = g.city_at(g.cursor)
	text(Vector2(166, 186), "SELECCIÓN  %03d / %03d" % [g.cursor.x, g.cursor.y], 13, MUTED)
	if ci >= 0:
		var c = g.cities[ci]
		text(Vector2(166, 230), c.name, 29)
		text(Vector2(166, 308),g.gameplay.PROFILES[g.gameplay.profile(c)]+" · "+g.gameplay.profile_description(c),16,GREEN)
		text(Vector2(166, 268), str(c.pop) + " habitantes · " + str(c.received) + " viajes · " + str(c.accesses.size()) + " accesos", 18, GREEN)
	elif g.roads.has(g.cursor):
		var r = g.roads[g.cursor]
		text(Vector2(166, 230), g.Catalog.ROADS[r.kind].name, 26)
		text(Vector2(166, 268), "En obras" if r.work > 0 else ("Cerrada al tráfico" if r.closed else "Abierta al tráfico"), 19, Color("f5b790") if r.closed else GREEN)
		text(Vector2(166, 302), "Conservación: " + str(int(r.hp)) + "%", 18)
		if r.work > 0: text(Vector2(166, 334), "Obra pendiente: %.1f s" % r.work, 18)
	else:
		text(Vector2(166, 232), ["Pradera", "Río", "Bosque", "Montaña", "Roquedo"][g.ground(g.cursor)], 26)
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
		"Cierra antes de reparar o mejorar. Después de las obras, vuelve a abrir.",
		"Une las ciudades por sus accesos señalados. No se conectan por los otros bordes.",
		"Los coches viajan y pagan al llegar: verás el ingreso junto a la ciudad.",
		"Zoom: LT / RT, rueda o + / −. LB / RB cambia de herramienta.",
		"Mayús mueve rápido · Espacio pausa · F / Start velocidad · G / R3 siguiente acceso.",
		"I inspección · M mapa · Esc / View menú · F5 guardar · F9 cargar.",
		"K objetivos · C inspeccionar coche · L capas · Ctrl+Z deshacer · Menú: Red y servicios."
	]
	for i in lines.size(): text(Vector2(166, 191 + i * 42), lines[i], 18, PAPER)

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

func draw_roundabouts() -> void:
	for center in g.incidents.roundabouts:
		var info = g.incidents.roundabouts[center]
		var texture = road_conditions[info.kind].roundabout
		if texture == null: continue
		var size = g.tile * 3
		var area = Rect2(g.screen(Vector2(center)) - Vector2.ONE * size / 2, Vector2.ONE * size)
		if not area.intersects(Rect2(-size,-size,1280+size*2,800+size*2)): continue
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
		if not g.roads.has(p): continue
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
	var status = "DEMOLIENDO" if road.get("demolishing",false) else ("EN OBRAS" if road.work > 0 else ("CERRADA" if road.closed else "ABIERTA"))
	lines.append(status + (" · Rotonda 3×3" if is_roundabout else ""))
	lines.append(str(spec.lanes) + " carriles · " + str(g.density.get(actual,0)) + "/" + str(spec.cap) + " coches")
	lines.append("Conservación " + str(int(road.hp)) + "% · " + str(int(spec.speed*15)) + " km/h")
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
	var phase = "APAGADO · paso libre" if not light.enabled else ("VERDE norte / sur" if g.incidents.signal_allows(g.cursor,Vector2i.UP) else "VERDE este / oeste")
	text(Vector2(225,522),phase,23,GREEN)
	text(Vector2(225,566),"Los coches esperan antes de entrar en la casilla mientras su dirección está roja.",16,MUTED)
	text(Vector2(225,619),"↑↓ elegir · ←→ ajustar · A / Enter aumentar o activar · B / Esc cerrar",16,PAPER)
