extends Node2D

const CityRoads = preload("res://scripts/city_roads.gd")
const CityDesign = preload("res://scripts/city_design.gd")
const Catalog = preload("res://scripts/catalog.gd")
const World = preload("res://scripts/world_terrain.gd")
const SIZE = World.SIZE # Centro de las partidas anteriores; no es un límite del mapa.
const Extent = preload("res://scripts/world_extent.gd")
const NO_CELL = World.NO_CELL
const WorldSettings = preload("res://scripts/world_settings.gd")
const MIN_CITY_DISTANCE = WorldSettings.MIN_CITY_DISTANCE
const START_CITY_DISTANCE = WorldSettings.START_CITY_DISTANCE
const INITIAL_CITY_COUNT = WorldSettings.INITIAL_CITY_COUNT
const MAX_CITIES = INITIAL_CITY_COUNT
const TOOLS = [
	{"id":"build_road","label":"Construir carretera","icon":"road"},
	{"id":"close_route","label":"Cerrar / abrir vía","icon":"close"},
	{"id":"repair_route","label":"Arreglar vía","icon":"repair"},
	{"id":"demolish_route","label":"Destruir vía","icon":"demolish"},
	{"id":"fell_trees","label":"Talar árboles","icon":"tree"},
	{"id":"menu","label":"Menú","icon":"menu"}
]
const ROAD_OPERATIONS = ["Construir", "Mejorar", "Reparar", "Cerrar", "Abrir"]
const SPEEDS = [0, 1, 2, 4, 8]
var save_path = "user://entre_ciudades_v2.save"
const DIRS = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
var terrain = World.new()
var explored = Extent.new()
var point_ids: Dictionary = {}
var city_connectors: Dictionary = {}
var retired_city_cells: Dictionary = {}
var roads: Dictionary = {}
var road_nodes: Dictionary = {}
var road_revision = 0
var cities: Array = []
var city_cells: Dictionary = {}
var cars: Array = []
var graph = preload("res://scripts/route_graph.gd").new()
var graph_dirty = true
var cursor = Vector2i(246, 250)
var camera = Vector2(246, 250)
var tile = 32.0
var zoom_target = 32.0
var visuals
var incidents
var event_notices
var traffic
var accounts
var maintenance
var navigator
var cheats
var gameplay
var services
var gameplay_ui
var selected_mode = "progression"
var selected_scenario = "budget"
var demolished_access_tiles: Dictionary = {}
var last_world_tool = 0
var panel_history: Array = []
var city_list_index = 0
var account_filter = 0
var account_scroll = 0
var ui_move_clock = 0.0
var construction_mode = "road"
var infrastructure_index = 0
var signal_index = 0
var hover_cell = NO_CELL
var money_popups: Array = []
var income_pulse = 0.0
var display_money = WorldSettings.STARTING_MONEY
var visual_clock = 0.0
var show_minimap = true
var kind = 0
var tool = 0
var horizontal = true
var anchor = NO_CELL
var speed_index = 1
var money = WorldSettings.STARTING_MONEY
var earned = 0.0
var trips = 0
var elapsed = 0.0
var demand_clock = 0.0
var growth_clock = 0.0
var building_world = false
var save_clock = 0.0
var move_clock = 0.0
var move_held = 0.0
var last_move = Vector2i.ZERO
var city_serial = 0
var world_seed = WorldSettings.WORLD_SEED
var rng = RandomNumberGenerator.new()
var notice = "Conecta los accesos de las ciudades. G / R3: siguiente acceso · Mayús: mover rápido."
var notice_time = 12.0
var panel = ""
var font: Font
var density: Dictionary = {}
var ui_hits: Array = []
var last_pad = false
var route_cache: Dictionary = {}
var at_title = true
var session_active = false
var title_index = 0
var title_confirm_new = false
var title_confirm_accept = false
var title_message = ""
var title_has_save = false
var test_mode = false
var trigger_left_down = false
var trigger_right_down = false
var reset_armed = false
var menu_index = 0
var focus_city_index = 0
var analog_menu_down = false
const MENU_LABELS = ["Ciudades", "Mapa", "Estadísticas", "Contabilidad", "Objetivos", "Red y servicios", "Escenarios"]
const MENU_ACTIONS = ["cities", "map", "stats", "accounts", "objectives", "network", "scenarios"]

func _ready() -> void:
	WorldSettings.validate()
	Engine.max_fps = 60
	font = ThemeDB.fallback_font
	incidents = preload("res://scripts/incidents.gd").new(self)
	event_notices = preload("res://scripts/event_notices.gd").new(self)
	traffic = preload("res://scripts/traffic_sim.gd").new(self)
	accounts = preload("res://scripts/accounts.gd").new()
	maintenance = preload("res://scripts/maintenance.gd").new(self)
	navigator = preload("res://scripts/navigation_map.gd").new(self)
	gameplay = preload("res://scripts/gameplay.gd").new(self)
	services = preload("res://scripts/network_services.gd").new(self)
	gameplay_ui = preload("res://scripts/gameplay_ui.gd").new(self)
	visuals = preload("res://scripts/visuals.gd").new(self)
	cheats = preload("res://scripts/cheat_console.gd").new(self)
	add_child(cheats)
	test_mode = "--test-mode" in OS.get_cmdline_user_args()
	if test_mode:
		save_path = "res://tests/test_save.bin"
		gameplay.records_path = "res://tests/test_scores.bin"
	gameplay.load_scores()
	rng.seed = world_seed
	if test_mode and not "--title-screen" in OS.get_cmdline_user_args():
		generate_world()
		at_title = false
		session_active = true
	else:
		title_has_save = FileAccess.file_exists(save_path)
	get_tree().auto_accept_quit = false
	queue_redraw()

func generate_world() -> void:
	rng.seed = world_seed
	accounts.reset(money)
	maintenance.reset()
	services.reset()
	gameplay.reset(gameplay.mode,gameplay.scenario_id)
	demolished_access_tiles.clear()
	navigator.seed_value = -1
	incidents.reset()
	traffic.reset()
	roads.clear()
	road_nodes.clear()
	cities.clear()
	city_serial = 0
	city_cells.clear()
	terrain.reset(world_seed)
	explored.reset()
	point_ids.clear()
	road_revision += 1
	city_connectors.clear()
	building_world = true
	assert(MIN_CITY_DISTANCE>0 and START_CITY_DISTANCE>=MIN_CITY_DISTANCE and INITIAL_CITY_COUNT>=2)
	var start = starting_city_center()
	add_city(start-Vector2i(START_CITY_DISTANCE/2,0), "Valverde", WorldSettings.START_CITY_RADIUS)
	add_city(start+Vector2i(START_CITY_DISTANCE/2,0), "Los Olmos", WorldSettings.START_CITY_RADIUS)
	generate_initial_cities()
	building_world = false
	rebuild_city_lookup()
	ensure_city_accesses()
	graph_dirty = true
	cursor = cities[0].accesses[0].end
	camera = Vector2(cursor)
	gameplay.prepare_cities()
	if gameplay.mode=="scenario" and gameplay.scenario_id=="winter":
		incidents.rules.weather_interval=90.0
		incidents.rules.snow_chance=1.0

func generate_initial_cities() -> void:
	# Emplazamientos escalonados: permiten una región densa sin atascar un
	# muestreo aleatorio por rechazo. Se barajan y priorizan praderas/bosques.
	var area = explored.bounds.grow(-16)
	var spacing = MIN_CITY_DISTANCE+4
	var row_step = ceili(spacing*sqrt(3.0)/2.0)
	var candidates: Array[Vector2i] = []
	var row = 0
	for y in range(area.position.y+2,area.end.y-2,row_step):
		for x in range(area.position.x+2+(spacing/2 if row%2 else 0),area.end.x-2,spacing):
			candidates.append(Vector2i(x,y)+Vector2i(rng.randi_range(-1,1),rng.randi_range(-1,1)))
		row+=1
	for i in range(candidates.size()-1,0,-1):
		var j = rng.randi_range(0,i)
		var swap = candidates[i]; candidates[i]=candidates[j]; candidates[j]=swap
	for pass_index in 2:
		for p in candidates:
			if cities.size()>=INITIAL_CITY_COUNT: return
			if pass_index==0 and terrain.sample_cell(p) not in [0,2]: continue
			var valid = true
			for city in cities:
				if Vector2(p).distance_squared_to(Vector2(city.pos))<MIN_CITY_DISTANCE*MIN_CITY_DISTANCE: valid=false; break
			if not valid: continue
			city_serial+=1
			var names = ["Ribera", "Encinar", "Puertollano", "Santa Clara", "Villalba", "Las Lomas", "Buenavista", "Peñablanca", "Alameda"]
			add_city(p,names[(city_serial-1)%names.size()]+(" "+str(city_serial) if city_serial>names.size() else ""),WorldSettings.NEW_CITY_RADIUS)
	if cities.size()<INITIAL_CITY_COUNT:
		push_warning("Solo caben %d de %d ciudades. Ajusta scripts/world_settings.gd."%[cities.size(),INITIAL_CITY_COUNT])

func starting_city_center() -> Vector2i:
	# Buscar terreno transitable natural para una primera conexión sin puentes ni montañas.
	var middle = explored.bounds.get_center()
	for radius in range(0,257,32):
		for y in range(-radius,radius+1,32):
			for x in range(-radius,radius+1,32):
				if maxi(absi(x),absi(y)) != radius: continue
				var center = middle+Vector2i(x,y)
				var passable = true
				for offset in range(-START_CITY_DISTANCE/2,START_CITY_DISTANCE/2+1):
					if ground(center+Vector2i(offset,0)) not in [0,2]: passable = false; break
				if passable: return center
	return middle

func add_city(pos: Vector2i, title: String, radius: int = WorldSettings.NEW_CITY_RADIUS) -> void:
	var first_direction = Vector2i.RIGHT
	if not cities.is_empty():
		var nearest = cities[0].pos
		for c in cities:
			if Vector2(pos).distance_squared_to(Vector2(c.pos)) < Vector2(pos).distance_squared_to(Vector2(nearest)): nearest = c.pos
		var delta: Vector2i = nearest - pos
		first_direction = Vector2i(int(sign(delta.x)), 0) if abs(delta.x) >= abs(delta.y) else Vector2i(0, int(sign(delta.y)))
	cities.append({"pos":pos, "name":title, "radius":radius, "pop":(radius - 1) * WorldSettings.POPULATION_PER_RADIUS + WorldSettings.CITY_BASE_POPULATION, "received":0, "recent":0, "access_dirs":[first_direction], "accesses":[]})
	explored.reveal(Vector2(pos),Vector2.ONE*(radius+5))
	gameplay.prepare_cities()
	if cities.size()<=2: cities.back().profile=cities.size()-1
	clear_city_plot(cities.back())
	if not building_world:
		rebuild_city_lookup()
		ensure_city_accesses()
	graph_dirty = true

func clear_city_plot(city: Dictionary) -> void:
	var radius: int = city.radius + maxi(4,WorldSettings.CITY_ACCESS_LENGTH+1)
	for y in range(city.pos.y - radius, city.pos.y + radius + 1):
		for x in range(city.pos.x - radius, city.pos.x + radius + 1):
			var p = Vector2i(x, y)
			if inside(p): terrain.set_cell(p, 0)

func ensure_city_accesses() -> void:
	CityRoads.sync(self)

func city_road(road_kind: int, along_x: bool) -> Dictionary:
	return {"kind":road_kind,"hp":100.0,"closed":false,"work":0.0,"total":1.0,"axis":along_x,"last_used":elapsed}

func refresh_city_connectors() -> void:
	city_connectors.clear()
	for c in cities: c.accesses=[]
	for p in roads:
		if roads[p].has("access_city"): roads[p].erase("access_city")
		if city_at(p)>=0: continue
		for d in DIRS:
			var inside_cell = p-d
			var owner = city_at(inside_cell)
			if owner<0 or not roads.has(inside_cell): continue
			city_connectors[p]=owner
			var end = p
			for step in range(1,WorldSettings.CITY_ACCESS_LENGTH):
				if not roads.has(p+d*step): break
				end=p+d*step
			cities[owner].accesses.append({"gate":p,"end":end,"dir":d})
			roads[p].access_city=owner
			break
	# Mantener el acceso principal orientado a la ciudad vecina para G / R3.
	for c in cities:
		var preferred: Vector2i = c.access_dirs[0]
		c.accesses.sort_custom(func(a,b):
			var score_a = (0 if a.dir==preferred else 100)+absi((a.gate-c.pos).x*preferred.y-(a.gate-c.pos).y*preferred.x)
			var score_b = (0 if b.dir==preferred else 100)+absi((b.gate-c.pos).x*preferred.y-(b.gate-c.pos).y*preferred.x)
			return score_a<score_b)

func edge_allowed(p: Vector2i, q: Vector2i) -> bool:
	return roads.has(p) and roads.has(q) and incidents.edge_allows(p,q)

func inside(p: Vector2i) -> bool:
	return p != NO_CELL

func ground(p: Vector2i) -> int:
	return terrain.get_cell(p) if inside(p) else 3

func city_at(p: Vector2i) -> int:
	return city_cells.get(p, -1)

func rebuild_city_lookup() -> void:
	city_cells.clear()
	for i in cities.size():
		var c = cities[i]
		CityDesign.ensure(c,i,world_seed)
		for y in range(c.pos.y - c.radius, c.pos.y + c.radius + 1):
			for x in range(c.pos.x - c.radius, c.pos.x + c.radius + 1):
				city_cells[Vector2i(x, y)] = i

func point_id(p: Vector2i) -> int:
	if not point_ids.has(p): point_ids[p] = point_ids.size()
	return point_ids[p]

func road_open(p: Vector2i) -> bool:
	return roads.has(p) and not roads[p].closed and roads[p].work <= 0.0

func rebuild_graph() -> void:
	refresh_city_connectors()
	road_revision += 1
	graph.clear()
	graph.minimum_step_cost=INF
	route_cache.clear()
	for p in roads:
		if road_open(p):
			var cost = 1.0 / Catalog.ROADS[roads[p].kind].speed * (1.0 if road_nodes.has(p) else 2.5)
			graph.add_point(point_id(p),Vector2(p),cost)
			graph.minimum_step_cost=minf(graph.minimum_step_cost,cost)
	for id in graph.get_point_ids():
		var p = Vector2i(graph.get_point_position(id))
		for d in DIRS:
			var q = p + d
			if inside(q) and graph.has_point(point_id(q)) and edge_allowed(p, q):
				if not graph.are_points_connected(id, point_id(q), false): graph.connect_points(id, point_id(q), false)
	graph_dirty = false
	traffic.refresh_connections()
	gameplay.connections_changed()

func _process(delta: float) -> void:
	visual_clock += delta
	if at_title:
		ui_move_clock -= delta
		if ui_move_clock<=0 and not Input.get_connected_joypads().is_empty():
			var pad = Input.get_connected_joypads()[0]
			var axis = JOY_AXIS_LEFT_X if title_confirm_new else JOY_AXIS_LEFT_Y
			var value = Input.get_joy_axis(pad,axis)
			if absf(value)>0.6: title_move(int(sign(value))); ui_move_clock = 0.2
		queue_redraw()
		return
	tile = lerpf(tile, zoom_target, minf(1, delta * 14))
	if absf(tile - zoom_target) < 0.05: tile = zoom_target
	income_pulse = maxf(0, income_pulse - delta * 2)
	display_money = lerpf(display_money, money, minf(1, delta * 9))
	for i in range(money_popups.size() - 1, -1, -1):
		money_popups[i].age += delta
		if money_popups[i].age > 2.2: money_popups.remove_at(i)
	if cheats!=null and cheats.is_open():
		queue_redraw()
		return
	var dt = delta * SPEEDS[speed_index]
	if gameplay.scenario_done: dt = 0.0
	elif not gameplay.scenario_id.is_empty(): dt = minf(dt,maxf(0,gameplay.scenario().duration-elapsed))
	elapsed += dt
	notice_time -= delta
	if notice_time <= 0: reset_armed = false
	move_clock -= delta
	ui_move_clock -= delta
	var move = Vector2i.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): move.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): move.y += 1
	if not Input.is_physical_key_pressed(KEY_A): event_notices.suppress_a=false
	if (Input.is_physical_key_pressed(KEY_A) and not event_notices.suppress_a) or Input.is_physical_key_pressed(KEY_LEFT): move.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): move.x += 1
	if not Input.get_connected_joypads().is_empty():
		var pad = Input.get_connected_joypads()[0]
		var stick = Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		var zoom_axis = Input.get_joy_axis(pad,JOY_AXIS_TRIGGER_RIGHT)-Input.get_joy_axis(pad,JOY_AXIS_TRIGGER_LEFT)
		if absf(zoom_axis)>0.1 and panel in ["","map"]: zoom_control(exp(zoom_axis*delta*1.4))
		if abs(stick.x) > 0.4: move.x = int(sign(stick.x))
		if abs(stick.y) > 0.4: move.y = int(sign(stick.y))
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT): move.x = -1
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT): move.x = 1
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP): move.y = -1
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN): move.y = 1
		if panel != "" and panel != "map" and ui_move_clock<=0:
			if absf(stick.x)>0.6: panel_move(int(sign(stick.x)),0); ui_move_clock=0.18
			elif absf(stick.y)>0.6: panel_move(0,int(sign(stick.y))); ui_move_clock=0.18
	if move != Vector2i.ZERO and move == last_move and panel == "": move_held += delta
	else: move_held = 0.0
	last_move = move
	if panel == "map":
		if move != Vector2i.ZERO: navigator.pan(Vector2(move).normalized()*navigator.span*delta*0.45*(2 if Input.is_physical_key_pressed(KEY_SHIFT) else 1))
		navigator.update(delta)
	if panel == "" and move != Vector2i.ZERO and move_clock <= 0:
		var stride = 8 if Input.is_physical_key_pressed(KEY_SHIFT) else (4 if last_pad and move_held > 0.65 else 1)
		cursor += move * stride
		move_clock = 0.085
	explore_around(Vector2(cursor))
	camera = camera.lerp(Vector2(cursor), minf(1.0, delta * 12))
	for p in roads:
		var r = roads[p]
		if r.work > 0:
			r.work = maxf(0, r.work - dt)
			if r.work == 0:
				r.hp = 100.0
				r.last_used = elapsed
				graph_dirty = true
		elif not r.closed:
			r.hp = maxf(WorldSettings.ROAD_MIN_HEALTH, r.hp - dt * WorldSettings.ROAD_PASSIVE_WEAR)
	maintenance.update(dt)
	services.update(dt)
	if graph_dirty: rebuild_graph()
	update_cars(dt)
	incidents.update(dt)
	gameplay.update(dt,delta)
	demand_clock += dt
	if demand_clock >= traffic.DEMAND_INTERVAL:
		demand_clock = fmod(demand_clock,traffic.DEMAND_INTERVAL)
		spawn_trips()
	growth_clock += dt
	if growth_clock >= WorldSettings.CITY_GROWTH_INTERVAL:
		growth_clock = 0
		grow_cities()
	save_clock += delta
	if WorldSettings.AUTOSAVE_ENABLED and save_clock >= WorldSettings.AUTOSAVE_INTERVAL and not test_mode:
		save_clock = 0
		save_game(false)
	queue_redraw()

func spawn_trips() -> void:
	traffic.spawn_demand()

func update_cars(dt: float) -> void:
	traffic.update(dt)

func grow_cities() -> void:
	var changed = false
	for c in cities:
		c.pop = maxi(WorldSettings.CITY_MIN_POPULATION, c.pop + WorldSettings.CITY_BASE_GROWTH + mini(c.recent * WorldSettings.CITY_GROWTH_PER_TRIP, WorldSettings.CITY_MAX_TRIP_GROWTH) - (WorldSettings.CITY_SHRINK_WITHOUT_TRIPS if c.recent == 0 and c.get("connected_at",-1.0)>=0 and elapsed-c.connected_at > WorldSettings.CITY_SHRINK_GRACE else 0))
		var radius = clampi(1 + int(c.pop / WorldSettings.POPULATION_PER_RADIUS), 1, WorldSettings.CITY_MAX_RADIUS)
		if radius != c.radius:
			c.radius = radius
			clear_city_plot(c)
			changed = true
		c.recent = 0
	if changed:
		rebuild_city_lookup()
		ensure_city_accesses()
		graph_dirty = true

func explore_around(at: Vector2) -> void:
	if Vector2i(at)==NO_CELL: return
	var added = explored.reveal(at,Vector2(660,420)/tile+Vector2.ONE*World.CHUNK)
	if added.is_empty(): return
	if terrain.flat_override<0:
		var before = cities.size()
		building_world = true
		for key in added: populate_region(key)
		building_world = false
		if cities.size()>before:
			rebuild_city_lookup()
			ensure_city_accesses()
			road_revision += 1
			graph_dirty = true
			tell("Nueva zona · "+str(cities.size()-before)+" ciudades descubiertas")
	navigator.changed()

func populate_region(key: Vector2i) -> void:
	var random = RandomNumberGenerator.new()
	random.seed = world_seed+key.x*73856093+key.y*19349663
	# Una cuadrícula con variación mantiene la separación incluso entre regiones vecinas.
	var grid = maxi(1,WorldSettings.EXPLORATION_CITY_GRID)
	for y in grid:
		for x in grid:
			var site = key*Extent.REGION+Vector2i(roundi((x+.5)*Extent.REGION/float(grid)),roundi((y+.5)*Extent.REGION/float(grid)))
			for attempt in WorldSettings.EXPLORATION_CITY_ATTEMPTS:
				var pos = site+Vector2i(random.randi_range(-WorldSettings.EXPLORATION_CITY_JITTER,WorldSettings.EXPLORATION_CITY_JITTER),random.randi_range(-WorldSettings.EXPLORATION_CITY_JITTER,WorldSettings.EXPLORATION_CITY_JITTER))
				if terrain.sample_cell(pos) not in [0,2]: continue
				var free = true
				for city in cities:
					if Vector2(pos).distance_squared_to(Vector2(city.pos))<MIN_CITY_DISTANCE*MIN_CITY_DISTANCE: free=false; break
				if not free: continue
				for dy in range(-5,6):
					for dx in range(-5,6):
						if roads.has(pos+Vector2i(dx,dy)): free=false; break
					if not free: break
				if not free: continue
				city_serial += 1
				add_city(pos,"Villa "+str(city_serial),WorldSettings.NEW_CITY_RADIUS)
				break

func spawn_city(announce: bool = true) -> bool:
	if cities.size() >= MAX_CITIES: return false
	for attempt in 200:
		var p: Vector2i
		if building_world:
			var area = explored.bounds.grow(-16)
			p = Vector2i(rng.randi_range(area.position.x,area.end.x-1),rng.randi_range(area.position.y,area.end.y-1))
		else:
			var base = cities[rng.randi_range(0, cities.size() - 1)].pos
			var angle = rng.randf_range(0, TAU)
			var distance = rng.randf_range(MIN_CITY_DISTANCE + 100, MIN_CITY_DISTANCE * 2.2)
			p = base + Vector2i(Vector2.from_angle(angle)*distance)
		if terrain.sample_cell(p) not in [0,2]: continue
		var valid = true
		for c in cities:
			if Vector2(p).distance_to(Vector2(c.pos)) < MIN_CITY_DISTANCE: valid = false; break
		if not valid: continue
		city_serial += 1
		var names = ["Encinar", "Puertollano", "Santa Clara", "Villalba", "Las Lomas", "Buenavista", "Peñablanca", "Alameda"]
		add_city(p, names[(city_serial - 1) % names.size()] + (" " + str(city_serial) if city_serial > 8 else ""))
		if announce: tell("Nueva ciudad: " + cities.back().name + " · G / R3 para localizar su acceso")
		return true
	return false

func line_cells(a: Vector2i, b: Vector2i) -> Array:
	var result: Array = []
	var p = a
	result.append(p)
	while p != b:
		if horizontal:
			if p.x != b.x: p.x += int(sign(b.x - p.x))
			else: p.y += int(sign(b.y - p.y))
		else:
			if p.y != b.y: p.y += int(sign(b.y - p.y))
			else: p.x += int(sign(b.x - p.x))
		result.append(p)
	return result

func footprint(centers: Array, width: int) -> Array:
	return footprint_axes(centers, width).keys()

func footprint_axes(centers: Array, _width: int) -> Dictionary:
	var cells: Dictionary = {}
	for i in centers.size():
		var p: Vector2i = centers[i]
		var along_x = horizontal
		if centers.size() > 1:
			var other: Vector2i = centers[i + 1] if i + 1 < centers.size() else centers[i - 1]
			along_x = other.x != p.x
		cells[p] = along_x
	return cells

func apply_action() -> void:
	match TOOLS[tool].id:
		"build_road":
			if construction_mode == "roundabout": build_roundabout(); return
			if construction_mode == "signal": install_signal(); return
			if anchor == NO_CELL:
				anchor = cursor
				tell("Inicio del tramo fijado · Mueve la selección y pulsa A / Enter para construir")
			elif anchor == cursor:
				tell("Selecciona otro extremo: las carreteras se construyen por tramos")
			else: apply_road_operation(0)
		"close_route": toggle_route()
		"repair_route": apply_road_operation(2)
		"demolish_route": maintenance.demolition(cursor)
		"fell_trees": maintenance.logging(cursor)
		"menu": open_menu()

func apply_road_operation(operation: int) -> void:
	var centers = line_cells(anchor, cursor) if anchor != NO_CELL else [cursor]
	if incidents.roundabout_cells.has(cursor):
		if operation == 0: tell("Ya hay una rotonda de 3 × 3 en esta posición."); return
		centers = incidents.ring_cells(incidents.roundabout_cells[cursor])
	else:
		for p in centers:
			if incidents.roundabout_cells.has(p): tell("La rotonda ocupa estas casillas."); return
	var spec = Catalog.ROADS[kind]
	if operation<=1 and not gameplay.unlocked(kind): tell("Débloqueala completando contratos · Nivel %d"%gameplay.road_tier(kind)); return
	var width: int = spec.w
	if operation >= 2 and roads.has(cursor): width = Catalog.ROADS[roads[cursor].kind].w
	var axes = footprint_axes(centers, width)
	var cells = axes.keys()
	var targets: Array = []
	var cost = 0.0
	for p in cells:
		if services.service_jobs.has(p): tell("Espera a que termine el mantenimiento del tramo."); return
		if not inside(p): return
		if terrain.flat_override<0 and not explored.contains(p): tell("Explora esa zona antes de construir el tramo."); return
		if city_at(p)>=0 and not CityDesign.is_street(cities[city_at(p)],p-cities[city_at(p)].pos) and not roads.has(p): continue
		if operation <= 1:
			if ground(p) == 3 or ground(p) == 4:
				tell("Las montañas y roquedos bloquean este trazado."); return
			if ground(p) == 1 and not spec.get("bridge", false):
				tell("Para cruzar el río selecciona un puente en el catálogo."); return
			if operation == 0 and roads.has(p): continue
			if operation == 1 and roads.has(p):
				if not roads[p].closed or roads[p].work > 0:
					tell("Cierra todo el tramo y espera las obras antes de mejorarlo."); return
				if spec.cost <= Catalog.ROADS[roads[p].kind].cost or spec.get("bridge", false) != Catalog.ROADS[roads[p].kind].get("bridge", false):
					tell("Selecciona una categoría superior del mismo tipo de vía."); return
			cost += float(spec.cost) / spec.w * (WorldSettings.UPGRADE_COST_RATIO if operation == 1 else 1.0)
			targets.append(p)
		elif roads.has(p):
			var r = roads[p]
			if operation == 2:
				if not r.closed or r.work > 0: tell("Cierra la carretera y espera las obras antes de repararla."); return
				cost += float(Catalog.ROADS[r.kind].cost) / Catalog.ROADS[r.kind].w * WorldSettings.REPAIR_COST_RATIO
			if operation == 4 and r.work > 0: tell("No se puede abrir una carretera en obras."); return
			targets.append(p)
	if targets.is_empty(): tell("No hay casillas válidas para esta acción."); return
	if money < cost: tell("Fondos insuficientes. Coste: " + cash(cost)); return
	var undo_before: Dictionary = {}
	if operation == 0:
		for p in targets:
			if roads.has(p): undo_before[p]={"road":roads[p].duplicate(true),"node":road_nodes.get(p,{}).duplicate(true)}
	else: services.invalidate_undo(targets)
	if operation in [0,1,2]: gameplay.begin_review(ROAD_OPERATIONS[operation]+" carretera")
	transact(-cost,"construction" if operation == 0 else ("upgrades" if operation == 1 else "repairs"),ROAD_OPERATIONS[operation]+" · "+str(targets.size())+" casillas")
	for p in targets:
		if operation <= 1:
			var owner = roads[p].get("access_city", -1) if roads.has(p) else access_owner(p)
			roads[p] = {"kind":kind, "hp":100.0, "closed":operation == 1, "work":float(spec.time), "total":float(spec.time), "axis":axes[p], "last_used":elapsed}
			if owner >= 0: roads[p].access_city = owner
			if city_at(p)>=0: roads[p].urban_city=city_at(p)
			demolished_access_tiles.erase(p)
		elif operation == 2:
			roads[p].work = WorldSettings.REPAIR_BASE_TIME + (100 - roads[p].hp) * WorldSettings.REPAIR_TIME_PER_DAMAGE
			roads[p].total = roads[p].work
		else:
			roads[p].closed = operation == 3
		roads[p].player_modified=true
	if operation <= 1:
		for center in centers:
			if roads.has(center):
				road_nodes[center] = {"kind":roads[center].kind, "axis":axes.get(center, horizontal)}
	if operation == 0: services.record_build(targets,undo_before,cost)
	if operation == 1 and incidents.roundabout_cells.has(cursor): incidents.roundabouts[incidents.roundabout_cells[cursor]].kind = kind
	graph_dirty = true
	anchor = NO_CELL
	tell(ROAD_OPERATIONS[operation] + " · " + str(targets.size()) + " casillas" + (" · " + cash(cost) if cost > 0 else ""))

func route_cells(p: Vector2i) -> Array:
	return incidents.ring_cells(incidents.roundabout_cells[p]) if incidents.roundabout_cells.has(p) else [p]

func toggle_route() -> void:
	var found = false
	var all_closed = true
	for p in route_cells(cursor):
		if roads.has(p): found = true; all_closed = all_closed and roads[p].closed
	if not found: tell("No hay ninguna vía en esta casilla."); return
	anchor = NO_CELL
	apply_road_operation(4 if all_closed else 3)

func access_owner(p: Vector2i) -> int:
	for i in cities.size():
		for access in cities[i].accesses:
			for j in WorldSettings.CITY_ACCESS_LENGTH:
				if p == access.gate+access.dir*j: return i
	return -1

func transact(amount: float, category: String, description: String) -> void:
	money += amount
	accounts.record(amount,category,description,elapsed)
	if category=="cheats" and not gameplay.scenario_id.is_empty(): gameplay.scenario_cheated=true

func tell(message: String) -> void:
	notice = message
	notice_time = 7

func cash(value: float) -> String:
	return str(int(value)).pad_decimals(0) + " €"

func save_game(message: bool = true) -> void:
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null: tell("No se pudo guardar la partida."); return
	file.store_var({"version":2, "roads":roads, "road_nodes":road_nodes, "cities":cities, "money":money, "earned":earned, "trips":trips, "elapsed":elapsed, "cursor":cursor, "seed":world_seed, "city_serial":city_serial, "terrain":terrain.snapshot(), "explored":explored.snapshot(), "rng":rng.state, "growth_clock":growth_clock, "demand_clock":demand_clock, "tile":zoom_target, "kind":kind, "tool":tool, "speed_index":speed_index, "incidents":incidents.snapshot(), "traffic":traffic.snapshot(), "accounts":accounts.snapshot(), "maintenance":maintenance.snapshot(), "demolished_access_tiles":demolished_access_tiles, "tool_id":TOOLS[tool].id, "last_world_tool_id":TOOLS[last_world_tool].id,"construction_mode":construction_mode,"gameplay":gameplay.snapshot(),"services":services.snapshot()})
	if message: tell("Partida guardada.")

func load_game() -> bool:
	var file = FileAccess.open(save_path, FileAccess.READ)
	if file == null: tell("Todavía no hay una partida guardada."); return false
	var data = file.get_var(false)
	if not data is Dictionary or data.get("version", 0) != 2: tell("Archivo de guardado incompatible."); return false
	roads = data.roads
	point_ids.clear()
	explored.restore(data.get("explored",{}))
	demolished_access_tiles = data.get("demolished_access_tiles",{})
	road_nodes = data.get("road_nodes", {})
	if road_nodes.is_empty() and not roads.is_empty(): restore_road_nodes()
	cities = data.cities
	world_seed = data.seed
	rebuild_city_lookup()
	money = data.money
	earned = data.earned
	trips = data.trips
	elapsed = data.elapsed
	cursor = data.cursor
	camera = Vector2(cursor)
	world_seed = data.seed
	terrain.restore(data.terrain)
	incidents.restore(data.get("incidents", {}))
	ensure_city_accesses()
	maintenance.restore(data.get("maintenance",{}))
	if data.has("accounts"): accounts.restore(data.accounts)
	else: accounts.legacy_balance(earned,incidents.accident_losses,money,elapsed)
	for p in roads:
		if not roads[p].has("last_used"): roads[p].last_used = elapsed
	city_serial = data.city_serial
	rng.state = data.rng
	growth_clock = data.get("growth_clock", 0.0)
	demand_clock = data.get("demand_clock", 0.0)
	tile = clampf(data.get("tile", 32.0), 8, 96)
	zoom_target = tile
	display_money = money
	money_popups.clear()
	kind = data.get("kind", 0)
	tool = 0
	if data.has("tool_id"):
		for i in TOOLS.size():
			if TOOLS[i].id == data.tool_id: tool = i
	else:
		tool = {0:0,1:0,2:2,3:1,4:1}.get(data.get("tool",0),0)
	last_world_tool = tool if TOOLS[tool].id != "menu" else 0
	for i in TOOLS.size()-1:
		if TOOLS[i].id == data.get("last_world_tool_id",TOOLS[last_world_tool].id): last_world_tool = i
	if TOOLS[tool].id == "menu": tool = last_world_tool
	anchor = NO_CELL
	construction_mode = data.get("construction_mode","road")
	if not construction_mode in ["road","roundabout","signal"]: construction_mode = "road"
	navigator.seed_value = -1
	speed_index = data.get("speed_index", 1)
	traffic.restore(data.get("traffic", {}))
	services.restore(data.get("services",{}))
	gameplay.restore(data.get("gameplay",{}))
	graph_dirty = true
	rebuild_graph()
	tell("Partida recuperada. La demanda de viajes se reanuda.")
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: quit_game()

func quit_game() -> void:
	if session_active and WorldSettings.AUTOSAVE_ENABLED and not test_mode: save_game(false)
	get_tree().quit()

func title_move(direction: int) -> void:
	if title_confirm_new:
		title_confirm_accept = not title_confirm_accept
		return
	for i in 3:
		title_index = posmod(title_index+direction,3)
		if title_index != 1 or title_has_save: break

func title_accept() -> void:
	if title_confirm_new:
		if title_confirm_accept: start_new_session()
		else: title_confirm_new = false
		return
	match title_index:
		0:
			if title_has_save:
				title_confirm_new = true
				title_confirm_accept = false
			else: start_new_session()
		1:
			if not title_has_save: return
			if load_game():
				at_title = false
				session_active = true
				save_clock = 0
				close_panels()
			else: title_message = notice
		2: quit_game()

func start_new_session() -> void:
	gameplay.mode=selected_mode
	gameplay.scenario_id=selected_scenario if selected_mode=="scenario" else ""
	reset_armed = true
	new_game()
	at_title = false
	session_active = true
	title_confirm_new = false
	title_message = ""
	save_clock = 0
	speed_index = 1
	kind = 0
	horizontal = true
	tile = 32.0
	zoom_target = 32.0
	hover_cell = NO_CELL
	density.clear()
	route_cache.clear()
	move_clock = 0.15
	ui_hits.clear()
	if gameplay.mode=="scenario":
		money=gameplay.scenario().money
		display_money=money
		accounts.reset(money)
		if gameplay.scenario_id=="winter":
			incidents.rules.weather_interval=90.0
			incidents.rules.snow_chance=1.0

func title_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		last_pad = false
		for hit in ui_hits:
			if not hit.rect.has_point(event.position): continue
			if hit.action.begins_with("title:"):
				if hit.action == "title:new": title_index = 0
				elif hit.action == "title:load": title_index = 1
				elif hit.action == "title:quit": title_index = 2
			elif hit.action == "title_confirm": title_confirm_accept = true
			elif hit.action == "title_cancel": title_confirm_accept = false
	if event is InputEventMouseButton and event.pressed:
		last_pad = false
		if event.button_index == MOUSE_BUTTON_RIGHT: title_confirm_new = false
		if event.button_index == MOUSE_BUTTON_LEFT:
			for hit in ui_hits:
				if hit.rect.has_point(event.position): title_action(hit.action); return
	if event is InputEventKey and event.pressed and not event.echo:
		last_pad = false
		var key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		match key:
			KEY_UP,KEY_W,KEY_LEFT,KEY_A: title_move(-1)
			KEY_DOWN,KEY_S,KEY_RIGHT,KEY_D,KEY_TAB: title_move(1)
			KEY_ENTER,KEY_KP_ENTER,KEY_SPACE: title_accept()
			KEY_ESCAPE: title_confirm_new = false
			KEY_X: if not title_confirm_new: gameplay_ui.cycle_mode()
			KEY_F9:
				if not title_confirm_new and title_has_save: title_index = 1; title_accept()
	if event is InputEventJoypadButton and event.pressed:
		last_pad = true
		match event.button_index:
			JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_LEFT: title_move(-1)
			JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_RIGHT: title_move(1)
			JOY_BUTTON_X: if not title_confirm_new: gameplay_ui.cycle_mode()
			JOY_BUTTON_A: title_accept()
			JOY_BUTTON_B,JOY_BUTTON_BACK: title_confirm_new = false
		ui_move_clock = 0.2
	if event is InputEventJoypadMotion and absf(event.axis_value)>0.6:
		last_pad = true
		if event.axis == (JOY_AXIS_LEFT_X if title_confirm_new else JOY_AXIS_LEFT_Y) and ui_move_clock<=0:
			title_move(int(sign(event.axis_value)))
			ui_move_clock = 0.2

func title_action(action: String) -> void:
	if action=="play:mode": gameplay_ui.cycle_mode(); return
	match action:
		"title:new": title_index = 0; title_accept()
		"title:load": title_index = 1; title_accept()
		"title:quit": title_index = 2; title_accept()
		"title_confirm": start_new_session()
		"title_cancel": title_confirm_new = false

func _unhandled_input(event: InputEvent) -> void:
	if cheats!=null and cheats.is_open(): return
	if at_title: title_input(event); return
	if event_notices.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		last_pad = false
		if panel == "map" and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			navigator.pan(-event.relative/navigator.RECT.size*navigator.view().size)
		elif panel == "":
			if visuals.tooltip_rect.has_point(event.position): return
			for hit in ui_hits:
				if hit.rect.has_point(event.position): hover_cell = NO_CELL; return
			hover_cell = Vector2i(((event.position-Vector2(640,400))/tile+camera+Vector2(0.5,0.5)).floor())
	if event is InputEventMouseButton and event.pressed:
		last_pad = false
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var direction = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			if panel == "cities": move_city_list(-direction)
			elif panel == "accounts": account_scroll = maxi(0,account_scroll-direction)
			elif panel in ["","map"]: zoom_control(pow(1.25,direction))
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if panel == "map": return
			cancel_or_back()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			for index in range(ui_hits.size()-1,-1,-1):
				var hit = ui_hits[index]
				if hit.rect.has_point(event.position): ui_action(hit.action); return
			if panel == "map" and navigator.RECT.has_point(event.position):
				var point = navigator.to_world(event.position)
				if inside(point):
					navigator.target = point
					if event.double_click: travel_to(point)
				return
			if visuals.tooltip_rect.has_point(event.position): return
			if panel == "" and event.position.y > 86 and event.position.y < 686:
				cursor = Vector2i(((event.position-Vector2(640,400))/tile+camera+Vector2(0.5,0.5)).floor())
				explore_around(Vector2(cursor))
				hover_cell = cursor
				if event.ctrl_pressed: gameplay.select_car_at(cursor); gameplay_ui.tab=1; open_panel("network")
				else: apply_action()
	if event is InputEventJoypadMotion:
		if absf(event.axis_value)>0.4: last_pad = true; hover_cell = NO_CELL
		if event.axis in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT]:
			var pressed = event.axis_value>0.6
			var was_down = trigger_left_down if event.axis == JOY_AXIS_TRIGGER_LEFT else trigger_right_down
			if pressed and not was_down and panel in ["","map"]: zoom_control(1.18 if event.axis == JOY_AXIS_TRIGGER_RIGHT else 1.0/1.18)
			if event.axis == JOY_AXIS_TRIGGER_LEFT: trigger_left_down = pressed
			else: trigger_right_down = pressed
		elif panel != "" and panel != "map" and absf(event.axis_value)>0.6 and ui_move_clock<=0:
			if event.axis == JOY_AXIS_LEFT_X: panel_move(int(sign(event.axis_value)),0)
			elif event.axis == JOY_AXIS_LEFT_Y: panel_move(0,int(sign(event.axis_value)))
			ui_move_clock = 0.18
	if event is InputEventJoypadButton and event.pressed:
		last_pad = true
		hover_cell = NO_CELL
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER: select_tool(posmod(tool-1,TOOLS.size())); return
		if event.button_index == JOY_BUTTON_RIGHT_SHOULDER: select_tool((tool+1)%TOOLS.size()); return
		if event.button_index == JOY_BUTTON_START: cycle_speed(); return
		if event.button_index == JOY_BUTTON_B or event.button_index == JOY_BUTTON_BACK: cancel_or_back(); return
		if panel=="menu" and event.button_index==JOY_BUTTON_LEFT_STICK: cheats.open(); return
		if panel != "":
			match event.button_index:
				JOY_BUTTON_A: panel_accept()
				JOY_BUTTON_X: panel_secondary(false)
				JOY_BUTTON_Y: panel_secondary(true)
				JOY_BUTTON_DPAD_UP: panel_move(0,-1)
				JOY_BUTTON_DPAD_DOWN: panel_move(0,1)
				JOY_BUTTON_DPAD_LEFT: panel_move(-1,0)
				JOY_BUTTON_DPAD_RIGHT: panel_move(1,0)
			return
		match event.button_index:
			JOY_BUTTON_A: apply_action()
			JOY_BUTTON_Y: if TOOLS[tool].id == "build_road": open_road_selector()
			JOY_BUTTON_X:
				if TOOLS[tool].id == "build_road": horizontal = not horizontal
				elif TOOLS[tool].id == "repair_route": upgrade_current()
			JOY_BUTTON_LEFT_STICK: zoom_control(1.5 if zoom_target<64 else 0.25)
			JOY_BUTTON_RIGHT_STICK: focus_next_city()
	if event is InputEventKey and event.pressed and not event.echo:
		last_pad = false
		hover_cell = NO_CELL
		if event.physical_keycode == KEY_ESCAPE: cancel_or_back(); return
		if event.physical_keycode == KEY_F5: save_game(); return
		if event.physical_keycode == KEY_F9: load_game(); close_panels(); return
		if event.physical_keycode == KEY_SPACE: speed_index = 1 if speed_index == 0 else 0; return
		if event.physical_keycode == KEY_F: cycle_speed(); return
		if event.keycode in [KEY_PLUS,KEY_KP_ADD] or event.physical_keycode in [KEY_EQUAL,KEY_PAGEUP]:
			if panel == "cities": move_city_list(-6)
			elif panel in ["","map"]: zoom_control(1.25)
			return
		if event.keycode in [KEY_MINUS,KEY_KP_SUBTRACT] or event.physical_keycode in [KEY_MINUS,KEY_PAGEDOWN]:
			if panel == "cities": move_city_list(6)
			elif panel in ["","map"]: zoom_control(1.0/1.25)
			return
		if event.physical_keycode == KEY_H and panel == "menu": open_panel("help"); return
		if event.physical_keycode == KEY_Q: select_tool(posmod(tool-1,TOOLS.size())); return
		if event.physical_keycode == KEY_TAB: select_tool((tool+1)%TOOLS.size()); return
		if panel != "":
			match event.physical_keycode:
				KEY_ENTER,KEY_E: panel_accept()
				KEY_UP,KEY_W: if panel != "map": panel_move(0,-1)
				KEY_DOWN,KEY_S: if panel != "map": panel_move(0,1)
				KEY_LEFT,KEY_A: if panel != "map": panel_move(-1,0)
				KEY_RIGHT,KEY_D: if panel != "map": panel_move(1,0)
				KEY_X: panel_secondary(false)
				KEY_Y: panel_secondary(true)
			return
		match event.physical_keycode:
			KEY_ENTER,KEY_E: apply_action()
			KEY_Q: select_tool(posmod(tool-1,TOOLS.size()))
			KEY_TAB: select_tool((tool+1)%TOOLS.size())
			KEY_R,KEY_X: if TOOLS[tool].id == "build_road": horizontal = not horizontal
			KEY_V,KEY_Y: open_road_selector()
			KEY_H: open_panel("help")
			KEY_I: open_panel("info")
			KEY_C: gameplay.select_car_at(cursor); gameplay_ui.tab=1; open_panel("network")
			KEY_L: gameplay_ui.cycle_overlay()
			KEY_Z: if event.ctrl_pressed: services.undo_build()
			KEY_K: open_panel("objectives")
			KEY_M: open_panel("map")
			KEY_G: focus_next_city()
			KEY_J: focus_alert()
			KEY_U: upgrade_current()
			KEY_N: new_game()
			KEY_O: select_tool(0); construction_mode = "roundabout"; tell("Rotonda · 3 × 3 casillas")
			KEY_T: install_signal()
			KEY_P: select_tool(0); construction_mode = "road"
			KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6: select_tool(event.physical_keycode-KEY_1)

func cycle_speed() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()

func toggle_anchor() -> void:
	anchor = cursor if anchor == NO_CELL else NO_CELL

func ui_action(action: String) -> void:
	if action.begins_with("event:"): event_notices.action(action); return
	if action.begins_with("play:"): gameplay_ui.action(action); return
	if action.begins_with("tool:"): select_tool(int(action.get_slice(":",1)))
	elif action.begins_with("kind:"):
		var requested = int(action.get_slice(":",1))
		if not gameplay.unlocked(requested): tell("Completa contratos para desbloquear el nivel %d"%gameplay.road_tier(requested)); return
		kind = requested
		tool = 0
		last_world_tool = 0
		panel = ""
		panel_history.clear()
	elif action.begins_with("mode:"):
		construction_mode = action.get_slice(":",1)
		anchor = NO_CELL
	elif action.begins_with("city_select:"): city_list_index = int(action.get_slice(":",1))
	elif action.begins_with("city_go:"): travel_city(int(action.get_slice(":",1)))
	elif action.begins_with("signal_config:"):
		cursor = Vector2i(int(action.get_slice(":",1)),int(action.get_slice(":",2)))
		open_panel("signal")
	elif action.begins_with("signal:"):
		var key = action.get_slice(":",1)
		signal_index = 2 if key == "toggle" else (0 if key.begins_with("ns") else 1)
		if signal_index == 2: special_accept()
		else: adjust_signal(1 if key.ends_with("+") else -1)
	else:
		match action:
			"menu": open_menu()
			"cheats": cheats.open()
			"cities","map","stats","accounts","help","info","infrastructure","objectives","network","scenarios": open_panel(action)
			"close": back_panel()
			"speed": cycle_speed()
			"save": save_game()
			"load": load_game(); close_panels()
			"new": new_game()
			"catalog": open_road_selector()
			"map_go": travel_to(navigator.target)
			"map_known": navigator.known_region()
			"map_all": navigator.whole_region()
			"cities_prev": move_city_list(-6)
			"cities_next": move_city_list(6)
			"account_filter": account_filter = (account_filter+1)%3; account_scroll = 0
			"account_prev": account_scroll = maxi(0,account_scroll-6)
			"account_next": account_scroll += 6
			"zoom_in": zoom_control(1.25)
			"zoom_out": zoom_control(1.0/1.25)
			"rotate": horizontal = not horizontal
			"anchor": apply_action()
			"upgrade": upgrade_current()
			"alert": focus_alert(); close_panels()
			"configure_signal": install_signal()
			"prev": kind = gameplay.available_kind(kind,-1)
			"next": kind = gameplay.available_kind(kind,1)

func select_tool(index: int) -> void:
	index = posmod(index,TOOLS.size())
	if TOOLS[index].id == "menu": open_menu(); return
	if TOOLS[index].id != "build_road": anchor = NO_CELL
	tool = index
	last_world_tool = index
	panel = ""
	panel_history.clear()
	hover_cell = NO_CELL

func open_menu() -> void:
	if TOOLS[tool].id != "menu": last_world_tool = tool
	tool = TOOLS.size()-1
	panel = "menu"
	panel_history.clear()
	menu_index = 0

func open_panel(name: String) -> void:
	if panel == name: return
	if panel != "": panel_history.append(panel)
	if name in ["menu","cities","map","stats","accounts"]:
		if TOOLS[tool].id != "menu": last_world_tool = tool
		tool = TOOLS.size()-1
	panel = name
	if name == "map": navigator.open()
	if name == "cities": city_list_index = clampi(city_list_index,0,maxi(0,cities.size()-1))
	if name == "accounts": account_scroll = 0
	gameplay_ui.focus_index=0
	if name=="network":
		services.select_segment(cursor)
		gameplay.diagnose()

func back_panel() -> void:
	if not panel_history.is_empty(): panel = panel_history.pop_back()
	else: close_panels()

func close_panels() -> void:
	panel = ""
	panel_history.clear()
	if TOOLS[tool].id == "menu": tool = clampi(last_world_tool,0,TOOLS.size()-2)

func cancel_or_back() -> void:
	if panel != "": back_panel()
	elif anchor != NO_CELL: anchor = NO_CELL
	else: open_menu()

func open_road_selector() -> void:
	if TOOLS[tool].id != "build_road": select_tool(0)
	open_panel("catalog")

func zoom_control(factor: float) -> void:
	if panel == "map": navigator.zoom(factor)
	else: set_zoom(zoom_target*factor)

func panel_move(x: int, y: int) -> void:
	if panel in ["objectives","network","scenarios"]: gameplay_ui.move_focus(x+y); return
	match panel:
		"menu": menu_index = posmod(menu_index+x+y*2,MENU_ACTIONS.size())
		"catalog": kind = posmod(kind+y+x*12,Catalog.ROADS.size())
		"cities": move_city_list(y+x*6)
		"accounts":
			if x != 0: account_filter = posmod(account_filter+x,3); account_scroll = 0
			else: account_scroll = maxi(0,account_scroll+y)
		"infrastructure": special_move(y if y != 0 else x)
		"signal":
			if x != 0: adjust_signal(x)
			else: special_move(y)

func panel_accept() -> void:
	if panel in ["objectives","network","scenarios"]: gameplay_ui.accept(); return
	match panel:
		"menu": open_panel(MENU_ACTIONS[menu_index])
		"catalog": ui_action("kind:"+str(kind))
		"cities": travel_city(city_list_index)
		"map": travel_to(navigator.target)
		"infrastructure","signal": special_accept()

func panel_secondary(y_button: bool) -> void:
	match panel:
		"menu":
			if y_button: load_game(); close_panels()
			else: save_game()
		"cities": move_city_list(6 if y_button else -6)
		"map":
			if y_button: navigator.whole_region()
			else: navigator.known_region()
		"accounts": account_filter = (account_filter+1)%3; account_scroll = 0
		"catalog":
			if not y_button:
				var modes = ["road","roundabout","signal"]
				construction_mode = modes[(modes.find(construction_mode)+1)%modes.size()]
				anchor = NO_CELL

func move_city_list(amount: int) -> void:
	city_list_index = clampi(city_list_index+amount,0,maxi(0,cities.size()-1))

func travel_city(index: int) -> void:
	if index < 0 or index >= cities.size(): return
	city_list_index = index
	travel_to(cities[index].accesses[0].end if not cities[index].accesses.is_empty() else cities[index].pos)
	tell(cities[index].name+" · Acceso principal")

func travel_to(p: Vector2i) -> void:
	if not inside(p): return
	cursor = p
	explore_around(Vector2(cursor))
	camera = Vector2(cursor)
	hover_cell = NO_CELL
	close_panels()

func upgrade_current() -> void:
	anchor = NO_CELL
	apply_road_operation(1)

func screen(p: Vector2) -> Vector2:
	return (p - camera) * tile + Vector2(640, 400)

func _draw() -> void:
	if visuals != null: visuals.draw()

func set_zoom(value: float) -> void:
	zoom_target = clampf(value, 8.0, 96.0)

func emit_income(amount: float, destination: int) -> void:
	income_pulse = 1.0
	money_popups.append({"amount":amount, "pos":Vector2(cities[destination].pos), "age":0.0, "offset":(trips % 4) * 16})
	if money_popups.size() > 96: money_popups.pop_front()

func new_game() -> void:
	if not reset_armed:
		reset_armed = true
		tell("Repite Nueva región / N para confirmar: se reemplazará la partida y su autoguardado.")
		notice_time = 20
		return
	reset_armed = false
	world_seed = int(Time.get_unix_time_from_system()) % 1000000 if WorldSettings.RANDOM_WORLD_SEED else WorldSettings.WORLD_SEED
	if gameplay.mode=="scenario": world_seed=gameplay.scenario().seed
	rng.seed = world_seed
	roads.clear()
	road_nodes.clear()
	cities.clear()
	cars.clear()
	money = gameplay.scenario().money if gameplay.mode=="scenario" else WorldSettings.STARTING_MONEY
	earned = 0.0
	display_money = money
	money_popups.clear()
	trips = 0
	elapsed = 0.0
	growth_clock = 0.0
	demand_clock = 0.0
	city_serial = 0
	cursor = Vector2i(246, 250)
	camera = Vector2(cursor)
	anchor = NO_CELL
	construction_mode = "road"
	tool = 0
	last_world_tool = 0
	panel_history.clear()
	panel = ""
	generate_world()
	tell("Nueva región generada. Conecta las primeras ciudades.")

func focus_next_city() -> void:
	if cities.is_empty(): return
	focus_city_index = (focus_city_index + 1) % cities.size()
	cursor = cities[focus_city_index].accesses[0].end if not cities[focus_city_index].accesses.is_empty() else cities[focus_city_index].pos
	tell(cities[focus_city_index].name + " · " + str(cities[focus_city_index].pop) + " habitantes · Acceso de carretera")

func restore_road_nodes() -> void:
	road_nodes.clear()
	for p in roads:
		road_nodes[p] = {"kind":roads[p].kind, "axis":roads[p].axis}

func build_roundabout() -> void:
	var center = cursor
	var cells: Array = []
	var spec = Catalog.ROADS[kind]
	if not gameplay.unlocked(kind): tell("Esta carretera requiere completar contratos."); return
	for y in range(-1, 2):
		for x in range(-1, 2):
			var p = center + Vector2i(x, y)
			if not inside(p) or city_at(p) >= 0 or incidents.protected_access(p) or incidents.roundabout_cells.has(p):
				tell("La rotonda necesita 3 × 3 casillas libres de ciudades, accesos y otras rotondas."); return
			if ground(p) in [3, 4] or (ground(p) == 1 and not spec.get("bridge", false)):
				tell("El terreno no permite construir esta rotonda."); return
			if roads.has(p) and (not roads[p].closed or roads[p].work > 0):
				tell("Cierra las carreteras existentes antes de convertirlas en rotonda."); return
			if density.get(p, 0) > 0: tell("Espera a que no haya coches dentro de la obra."); return
			cells.append(p)
	var cost: float = spec.cost * 9
	if money < cost: tell("Fondos insuficientes: " + cash(cost)); return
	var undo_before: Dictionary = {}
	for p in cells:
		if roads.has(p): undo_before[p]={"road":roads[p].duplicate(true),"node":road_nodes.get(p,{}).duplicate(true)}
	gameplay.begin_review("Nueva rotonda")
	transact(-cost,"construction","Rotonda · "+spec.name)
	for p in cells:
		incidents.roundabout_cells[p] = center
		incidents.signals.erase(p)
		roads.erase(p)
		road_nodes.erase(p)
	for p in incidents.ring_cells(center):
		roads[p] = {"kind":kind, "hp":100.0, "closed":false, "work":float(spec.time), "total":float(spec.time), "axis":true, "last_used":elapsed,"player_modified":true}
		road_nodes[p] = {"kind":kind, "axis":true}
	incidents.roundabouts[center] = {"kind":kind}
	services.record_build(cells,undo_before,cost,center)
	graph_dirty = true
	anchor = NO_CELL
	tell("Rotonda en construcción · 3 × 3 casillas · " + cash(cost))

func install_signal() -> void:
	if incidents.signals.has(cursor): panel = "signal"; return
	if not roads.has(cursor) or incidents.roundabout_cells.has(cursor):
		tell("Coloca el semáforo sobre una carretera que no sea una rotonda."); return
	services.invalidate_undo([cursor])
	gameplay.begin_review("Nuevo semáforo")
	roads[cursor].player_modified=true
	incidents.signals[cursor] = {"ns":WorldSettings.SIGNAL_NS_GREEN, "ew":WorldSettings.SIGNAL_EW_GREEN, "enabled":true, "offset":-elapsed}
	panel = "signal"
	tell("Semáforo instalado · Ajusta los tiempos por dirección")

func special_move(amount: int) -> void:
	if panel == "infrastructure": infrastructure_index = posmod(infrastructure_index + amount, 3)
	elif panel == "signal": signal_index = posmod(signal_index + amount, 3)

func special_accept() -> void:
	if panel == "infrastructure":
		construction_mode = ["road", "roundabout", "signal"][infrastructure_index]
		tool = 0
		panel = ""
	elif panel == "signal" and incidents.signals.has(cursor):
		if signal_index == 2: incidents.signals[cursor].enabled = not incidents.signals[cursor].enabled
		else: adjust_signal(1)

func adjust_signal(amount: int) -> void:
	if panel != "signal" or not incidents.signals.has(cursor): return
	gameplay.begin_review("Ajuste del semáforo")
	var s = incidents.signals[cursor]
	if signal_index == 2: s.enabled = not s.enabled; return
	var key = "ns" if signal_index == 0 else "ew"
	s[key] = clampf(s[key] + amount * 2, 1, 120)

func focus_alert() -> void:
	if not inside(incidents.last_alert): tell("No hay alertas de eventos todavía."); return
	cursor = incidents.last_alert
	tell("Última alerta · " + str(cursor.x) + ", " + str(cursor.y))
