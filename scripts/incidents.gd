extends RefCounted
## Condiciones y controles. Los porcentajes se suman y se comprueban por intervalo.
const Settings = preload("res://scripts/world_settings.gd")
const ACCIDENT_INTERVAL = Settings.ACCIDENT_INTERVAL
const ACCIDENT_COST = Settings.ACCIDENT_COST
const ACCIDENT_STOP = Settings.ACCIDENT_STOP
const STATES = ["burning", "snowy", "damaged", "very_damaged", "extreme_damage", "closed", "fading", "roundabout", "signal"]
var g
var snow: Dictionary = {}
var fire: Dictionary = {}
var zones: Array = []
var signals: Dictionary = {}
var roundabouts: Dictionary = {}
var roundabout_cells: Dictionary = {}
var accidents = 0
var accident_losses = 0.0
var weather_clock = 0.0
var last_alert = preload("res://scripts/world_terrain.gd").NO_CELL
var protection_revision = -1
var protected_tiles: Dictionary = {}
var rules = Settings.incident_rules()
# Tiempos de simulación confirmados por el usuario.

func _init(game) -> void:
	g = game

func reset() -> void:
	rules = Settings.incident_rules()
	snow.clear()
	fire.clear()
	zones.clear()
	signals.clear()
	roundabouts.clear()
	roundabout_cells.clear()
	accidents = 0
	accident_losses = 0
	weather_clock = 0
	last_alert = g.NO_CELL
	protection_revision = -1
	protected_tiles.clear()

func protected_access(p: Vector2i) -> bool:
	if g.roads.has(p) and g.roads[p].has("urban_city"): return true
	if g.roads.has(p) and g.roads[p].has("access_city"): return true
	if protection_revision != g.road_revision:
		protection_revision = g.road_revision
		protected_tiles.clear()
		for c in g.cities:
			for a in c.accesses:
				for i in Settings.CITY_ACCESS_LENGTH: protected_tiles[a.gate + a.dir * i] = true
	return protected_tiles.has(p)

func used(p: Vector2i) -> void:
	if not g.roads.has(p): return
	g.services.note_used(p)
	g.roads[p].last_used = g.elapsed
	if roundabout_cells.has(p):
		var center = roundabout_cells[p]
		for q in ring_cells(center):
			if g.roads.has(q): g.roads[q].last_used = g.elapsed

func unused_seconds(p: Vector2i) -> float:
	return maxf(0, g.elapsed - float(g.roads[p].get("last_used", g.elapsed))) if g.roads.has(p) else 0.0

func fade(p: Vector2i) -> float:
	if not rules.abandon_enabled or protected_access(p) or g.roads.get(p,{}).get("reserve",false): return 0
	return clampf((unused_seconds(p) - rules.unused_start) / maxf(1, rules.unused_fade), 0, 1)

func wear_risk(p: Vector2i) -> float:
	if not g.roads.has(p): return 0
	var hp: float = g.roads[p].hp
	return Settings.EXTREME_DAMAGE_ACCIDENT_RISK if hp < 15 else (Settings.VERY_DAMAGED_ACCIDENT_RISK if hp < 40 else (Settings.DAMAGED_ACCIDENT_RISK if hp < 75 else 0.0))

func risk(p: Vector2i) -> float:
	return minf(1, wear_risk(p) + (Settings.FIRE_ACCIDENT_RISK if fire.has(p) else 0) + (Settings.SNOW_ACCIDENT_RISK if snow.has(p) else 0))

func visual_state(p: Vector2i) -> String:
	if not g.roads.has(p): return ""
	var r = g.roads[p]
	if r.closed: return "closed"
	if fire.has(p): return "burning"
	if snow.has(p): return "snowy"
	if fade(p) > 0: return "fading"
	if r.hp < 15: return "extreme_damage"
	if r.hp < 40: return "very_damaged"
	if r.hp < 75: return "damaged"
	if signals.has(p): return "signal"
	return ""

func update(dt: float) -> void:
	if dt <= 0: return
	for p in snow.keys():
		if snow[p] <= g.elapsed: snow.erase(p)
	for p in fire.keys():
		if fire[p] <= g.elapsed: fire.erase(p)
	for i in range(zones.size() - 1, -1, -1):
		var z = zones[i]
		if g.elapsed >= z.until:
			zones.remove_at(i)
			continue
		z.clock += dt
		while z.clock >= rules.fire_spread:
			z.clock -= rules.fire_spread
			spread_fire(z)
	if rules.weather_enabled:
		weather_clock += dt
		if weather_clock >= rules.weather_interval:
			weather_clock = fmod(weather_clock, rules.weather_interval)
			if not g.roads.is_empty():
				var seed: Vector2i = g.roads.keys()[g.rng.randi_range(0, g.roads.size() - 1)]
				if g.gameplay.weather_kind()=="snow": snow_zone(seed, int(rules.snow_radius))
				else: ignite(seed)
				g.gameplay.weather_dispatched()
	if rules.abandon_enabled:
		var remove: Array = []
		for p in g.roads:
			if g.roads[p].work <= 0 and fade(p) >= 1: remove.append(p)
		for p in remove: erase_road(p)

func snow_zone(center: Vector2i, radius: int, duration: float = -1) -> void:
	last_alert = center
	var end = g.elapsed + (rules.snow_duration if duration < 0 else duration)
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var p = center + Vector2i(x, y)
			if g.inside(p) and Vector2(x, y).length() <= radius + 0.3: snow[p] = end
	g.tell("Zona nevada · Riesgo +%d %% · J / menú para localizar" % roundi(Settings.SNOW_ACCIDENT_RISK*100))

func ignite(p: Vector2i, duration: float = -1) -> void:
	if not g.inside(p): return
	last_alert = p
	var life: float = rules.fire_duration if duration < 0 else duration
	fire[p] = g.elapsed + life
	zones.append({"cells":[p], "until":g.elapsed + life, "clock":0.0})
	g.tell("Incendio detectado · Riesgo +%d %% · J / menú para localizar" % roundi(Settings.FIRE_ACCIDENT_RISK*100))

func spread_fire(zone: Dictionary) -> void:
	var candidates: Array = []
	for p in zone.cells:
		if not fire.has(p): continue
		for d in g.DIRS:
			var q = p + d
			if g.inside(q) and not fire.has(q) and (g.ground(q) != 1 or g.roads.has(q)):
				candidates.append(q)
	if candidates.is_empty(): return
	var p = candidates[g.rng.randi_range(0, candidates.size() - 1)]
	fire[p] = g.elapsed + rules.fire_duration
	zone.cells.append(p)

func erase_road(p: Vector2i, force: bool = false) -> void:
	if protected_access(p) and not force: return
	if roundabout_cells.has(p):
		var center = roundabout_cells[p]
		for q in ring_cells(center):
			g.roads.erase(q)
			g.road_nodes.erase(q)
		for y in range(-1, 2):
			for x in range(-1, 2): roundabout_cells.erase(center + Vector2i(x, y))
		roundabouts.erase(center)
	else:
		g.roads.erase(p)
		g.road_nodes.erase(p)
	signals.erase(p)
	g.graph_dirty = true

func accident(car: Dictionary, p: Vector2i, dt: float) -> bool:
	car.accident_clock = car.get("accident_clock", 0.0) + dt
	while car.accident_clock >= ACCIDENT_INTERVAL:
		car.accident_clock -= ACCIDENT_INTERVAL
		if g.roads.has(p) and g.rng.randf() < risk(p):
			car.crash_left = ACCIDENT_STOP
			g.transact(-ACCIDENT_COST,"accidents","Accidente de tráfico")
			accidents += 1
			accident_losses += ACCIDENT_COST
			g.money_popups.append({"amount":-ACCIDENT_COST, "pos":Vector2(p), "age":0.0, "offset":0})
			if g.money_popups.size() > 96: g.money_popups.pop_front()
			return true
	return false

func signal_allows(p: Vector2i, direction: Vector2i) -> bool:
	if not signals.has(p) or not signals[p].enabled: return true
	var s = signals[p]
	var phase = fposmod(g.elapsed + s.offset, s.ns + s.ew)
	return phase < s.ns if direction.y != 0 else phase >= s.ns

func ring_cells(center: Vector2i) -> Array:
	return [center + Vector2i(1,-1), center + Vector2i(0,-1), center + Vector2i(-1,-1), center + Vector2i(-1,0), center + Vector2i(-1,1), center + Vector2i(0,1), center + Vector2i(1,1), center + Vector2i(1,0)]

func edge_allows(p: Vector2i, q: Vector2i) -> bool:
	if roundabout_cells.has(p):
		var c = roundabout_cells[p]
		if q == c: return false
		if roundabout_cells.get(q, g.NO_CELL) == c:
			var ring = ring_cells(c)
			var index = ring.find(p)
			return index >= 0 and q == ring[(index + 1) % 8]
		var d: Vector2i = p - c
		return abs(d.x) + abs(d.y) == 1 and q == c + d * 2
	if roundabout_cells.has(q):
		var c = roundabout_cells[q]
		var d: Vector2i = q - c
		return abs(d.x) + abs(d.y) == 1 and p == c + d * 2
	return true

func snapshot() -> Dictionary:
	return {"sentinel_version":1,"snow":snow, "fire":fire, "zones":zones, "signals":signals, "roundabouts":roundabouts, "roundabout_cells":roundabout_cells, "accidents":accidents, "losses":accident_losses, "clock":weather_clock, "rules":rules, "last_alert":last_alert}

func restore(data: Dictionary) -> void:
	reset()
	snow = data.get("snow", {})
	fire = data.get("fire", {})
	zones = data.get("zones", [])
	signals = data.get("signals", {})
	roundabouts = data.get("roundabouts", {})
	roundabout_cells = data.get("roundabout_cells", {})
	accidents = data.get("accidents", 0)
	accident_losses = data.get("losses", 0.0)
	weather_clock = data.get("clock", 0.0)
	last_alert = data.get("last_alert",g.NO_CELL)
	if not data.has("sentinel_version") and last_alert==Vector2i(-1,-1): last_alert=g.NO_CELL
	# Estos dos parámetros no se incluían en los guardados anteriores.
	rules.snow_chance=0.5
	rules.snow_radius=6
	for key in data.get("rules", {}): rules[key] = data.rules[key]
