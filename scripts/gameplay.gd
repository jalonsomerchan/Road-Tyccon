extends RefCounted
## Objetivos, economía, telemetría y escenarios; compatible con guardados v2.
const PROFILES = ["Residencial", "Industrial", "Turística", "Agrícola"]
const SCENARIOS = [
	{"id":"budget", "name":"Pueblos con presupuesto", "seed":42193, "duration":900.0, "money":12000.0, "goal":120, "description":"Completa 120 viajes en 15 minutos con 12.000 € iniciales."},
	{"id":"winter", "name":"Invierno en la región", "seed":71129, "duration":1200.0, "money":30000.0, "goal":180, "description":"Completa 180 viajes en 20 minutos de nevadas frecuentes."},
	{"id":"network", "name":"La gran conexión", "seed":98731, "duration":1800.0, "money":45000.0, "goal":6, "description":"Conecta 6 ciudades en 30 minutos y conserva una caja positiva."}
]
const BASE_ROADS = [0,3,10,16,17]
var g
var mode = "free"
var reputation = 0
var tier = 0
var contracts: Array = []
var efficient_trips = 0
var samples: Array = []
var routes: Dictionary = {}
var road_income: Dictionary = {}
var demand_credit: Dictionary = {}
var connected_seen: Dictionary = {}
var celebration = ""
var celebration_left = 0.0
var review: Dictionary = {}
var improvements: Array = []
var sample_clock = 0.0
var upkeep_clock = 0.0
var upkeep_revision = -1
var upkeep_cached = 0.0
var monitor_clock = 0.0
var alert_cell = Vector2i.ZERO
var alert_text = ""
var scenario_id = ""
var scenario_done = false
var scenario_result: Dictionary = {}
var scenario_cheated = false
var scores: Dictionary = {}
var selected_ticket = -1
var overlay = "none"
var next_weather = "snow"
var records_path = "user://entre_ciudades_scores_v1.dat"

func _init(game) -> void:
	g = game

func reset(new_mode: String = "free", scenario: String = "") -> void:
	mode = new_mode
	reputation = 0
	tier = 0
	contracts.clear()
	efficient_trips = 0
	samples.clear()
	routes.clear()
	road_income.clear()
	demand_credit.clear()
	connected_seen.clear()
	celebration = ""
	celebration_left = 0
	review.clear()
	improvements.clear()
	sample_clock = 0
	upkeep_clock = 0
	upkeep_revision = -1
	monitor_clock = 0
	alert_text = ""
	alert_cell = g.NO_CELL
	selected_ticket = -1
	overlay = "none"
	scenario_id = scenario
	scenario_done = false
	scenario_result.clear()
	scenario_cheated = false
	next_weather = "snow" if posmod(g.world_seed,2)==1 else "fire"
	for slot in 3: contracts.append(make_contract(slot,0))

func prepare_cities() -> void:
	for city in g.cities:
		prepare_city(city)

func prepare_city(city: Dictionary) -> void:
	if not city.has("profile"): city.profile = posmod(city.pos.x*31+city.pos.y*17+g.world_seed,4)
	if not city.has("connected_at"): city.connected_at = -1.0

func profile(city: Dictionary) -> int:
	return int(city.get("profile",posmod(city.get("pos",Vector2i.ZERO).x*31+city.get("pos",Vector2i.ZERO).y*17+g.world_seed,4)))

func profile_description(city: Dictionary) -> String:
	return ["Horas punta · 1,8× demanda", "Mercancías · 1,4× tarifa · 0,8× velocidad", "Fines de semana · 1,6× demanda · 1,25× tarifa", "Cosecha · 2× demanda · 1,2× tarifa"][profile(city)]

func demand_count(origin: int, base: int) -> int:
	var city = g.cities[origin]
	var phase = int(g.elapsed/60.0)%10
	var multiplier = 1.0
	match profile(city):
		0: multiplier = 1.8 if phase in [2,3,7,8] else 0.8
		1: multiplier = 1.25 if phase in range(2,9) else 0.6
		2: multiplier = 1.6 if phase in [0,1,8,9] else 0.7
		3: multiplier = 2.0 if int(g.elapsed/300.0)%4==3 else 0.7
	var credit = float(demand_credit.get(origin,0.0))+base*multiplier
	var result = int(credit)
	demand_credit[origin] = credit-result
	return result

func choose_destination(origin: int, destinations: Array) -> int:
	var total = 0.0
	var weights: Array = []
	for dest in destinations:
		var weight = sqrt(maxf(1,g.cities[dest].pop))
		if profile(g.cities[dest]) != profile(g.cities[origin]): weight *= 1.4
		weights.append(weight)
		total += weight
	var pick = g.rng.randf()*total
	for i in destinations.size():
		pick -= weights[i]
		if pick<=0: return destinations[i]
	return destinations.back()

func connected_count() -> int:
	var count = 0
	for i in g.cities.size():
		if not g.traffic.current_links.get(i,[]).is_empty(): count+=1
	return count

func connections_changed() -> void:
	prepare_cities()
	for i in g.cities.size():
		if g.traffic.current_links.get(i,[]).is_empty(): continue
		if g.cities[i].connected_at<0: g.cities[i].connected_at=g.elapsed
		if connected_seen.has(i): continue
		connected_seen[i]=true
		celebrate("¡"+g.cities[i].name+" conectada a la red!")

func celebrate(value: String) -> void:
	celebration = value
	celebration_left = 5.0

func unlocked(road_kind: int) -> bool:
	if mode!="progression": return true
	return road_tier(road_kind)<=tier

func road_tier(road_kind: int) -> int:
	if road_kind in BASE_ROADS: return 0
	if road_kind in [1,2,4,11,18,19,20,21]: return 1
	if road_kind in [5,6,7,12,13,22]: return 2
	return 3

func available_kind(current: int, direction: int) -> int:
	for offset in range(1,25):
		var candidate = posmod(current+offset*direction,24)
		if unlocked(candidate): return candidate
	return 0

func update_tier() -> void:
	var old = tier
	tier = 3 if reputation>=180 else (2 if reputation>=80 else (1 if reputation>=20 else 0))
	if mode=="progression" and tier>old: celebrate("Nivel %d · Nuevas carreteras y puentes disponibles"%tier)

func make_contract(slot: int, stage: int) -> Dictionary:
	return {"slot":slot,"stage":stage,"goal":([2,30,10][slot]+stage*[2,60,25][slot]),"reward":([2000,1500,1800][slot]+stage*750),"rep":20+stage*5,"ready":false}

func contract_value(contract: Dictionary) -> int:
	return [connected_count(),g.trips,efficient_trips][contract.slot]

func contract_title(contract: Dictionary) -> String:
	return ["Conecta %d ciudades", "Completa %d viajes", "Completa %d viajes con demora ≤ 10 s"][contract.slot]%contract.goal

func claim(slot: int) -> void:
	if slot<0 or slot>=contracts.size() or scenario_done: return
	var contract = contracts[slot]
	if contract_value(contract)<contract.goal: g.tell("El contrato todavía está en marcha."); return
	g.transact(contract.reward,"contracts",contract_title(contract))
	reputation += contract.rep
	contracts[slot]=make_contract(slot,contract.stage+1)
	celebrate("Contrato completado · +%d € · +%d reputación"%[contract.reward,contract.rep])
	update_tier()

func trip_completed(car: Dictionary, fare: float) -> void:
	var delay = maxf(0,car.age-car.ideal)
	if delay<=10: efficient_trips+=1
	samples.append({"at":g.elapsed,"duration":car.age,"delay":delay,"fare":fare})
	if samples.size()>256: samples.pop_front()
	var trip_path = car.get("path",PackedVector2Array())
	var share = fare/maxi(1,trip_path.size())
	for cell in trip_path:
		var p = Vector2i(cell)
		if g.roads.has(p): road_income[p]=float(road_income.get(p,0.0))+share
	var key = Vector2i(car.get("origin",0),car.dest)
	if not routes.has(key): routes[key]={"income":0.0,"trips":0,"duration":0.0,"delay":0.0}
	var route = routes[key]
	route.income+=fare
	route.trips+=1
	route.duration+=car.age
	route.delay+=delay

func metrics(after_time: float = -1.0) -> Dictionary:
	var duration = 0.0
	var delay = 0.0
	var count = 0
	for entry in samples:
		if entry.at<=after_time: continue
		count+=1
		duration+=entry.duration
		delay+=entry.delay
	return {"duration":duration/maxi(1,count),"delay":delay/maxi(1,count),"queue":g.traffic.queued,"count":count,"trips":g.trips}

func begin_review(label: String) -> void:
	if samples.size()<5: return
	if review.is_empty(): review={"label":label,"before":metrics(),"at":g.elapsed}
	else: review.label=label

func finish_review() -> void:
	if review.is_empty() or g.elapsed-review.at<60 or g.trips-review.before.trips<5: return
	var after = metrics(review.at)
	if after.count<5: return
	var entry = {"label":review.label,"before":review.before,"after":after,"at":g.elapsed}
	improvements.push_front(entry)
	if improvements.size()>6: improvements.pop_back()
	celebrate("%s · Demora media %.0f → %.0f s"%[review.label,review.before.delay,after.delay])
	review.clear()

func is_player_road(p: Vector2i) -> bool:
	var road = g.roads[p]
	if road.get("player_modified",false): return true
	return not road.has("generated_city") and not road.has("urban_city") and not road.has("access_city")

func upkeep_per_minute() -> float:
	if not g.graph_dirty and upkeep_revision==g.road_revision: return upkeep_cached
	var cost = 0.0
	for p in g.roads:
		var road = g.roads[p]
		# Solo infraestructura del jugador; las calles municipales son gratuitas.
		if not is_player_road(p): continue
		cost += g.Catalog.ROADS[road.kind].cost*0.0008*(1.35 if road.get("reserve",false) else 1.0)
	upkeep_cached=cost
	upkeep_revision=g.road_revision if not g.graph_dirty else -1
	return cost

func income_per_minute() -> float:
	var last_minute = int(g.elapsed/60)
	var value = 0.0
	for entry in g.accounts.entries:
		if entry.category=="trips" and int(entry.at/60)>=maxi(0,last_minute-5) and int(entry.at/60)<last_minute:
			value+=entry.amount
	return value/maxi(1,mini(5,last_minute))

func route_report(key: Vector2i) -> Dictionary:
	var stats = routes[key]
	var path = g.traffic.route(g.cities[key.x].pos,key.y)
	var upkeep = 0.0
	var repair_quote = 0.0
	for cell in path:
		var p = Vector2i(cell)
		if not g.roads.has(p): continue
		var road = g.roads[p]
		if not is_player_road(p): continue
		upkeep += g.Catalog.ROADS[road.kind].cost*0.0008*(1.35 if road.get("reserve",false) else 1.0)
		repair_quote += g.Catalog.ROADS[road.kind].cost*0.25*(1-road.hp/100.0)
	var minutes = maxf(1,g.elapsed/60.0)
	return {"income":stats.income/minutes,"upkeep":upkeep,"net":stats.income/minutes-upkeep,"repair":repair_quote,"delay":stats.delay/maxi(1,stats.trips),"trips":stats.trips}

func diagnose() -> void:
	alert_text = "Red fluida · Sin colas en accesos"
	alert_cell = g.NO_CELL
	var largest = 0
	for i in g.cities.size():
		var count = g.traffic.city_queue(i)
		if count<=largest: continue
		largest=count
		alert_cell=g.cities[i].accesses[0].end if not g.cities[i].accesses.is_empty() else g.cities[i].pos
		alert_text="%s · %d coches esperan en sus accesos"%[g.cities[i].name,count]
	for car in g.cars:
		if not car.get("blocked",false): continue
		if largest>0: break
		alert_cell=g.traffic.position(car)
		alert_text="Vehículo detenido · "+car_reason(car)
		break

func car_reason(car: Dictionary) -> String:
	var p = g.traffic.position(car)
	if car.get("crash_left",0.0)>0: return "Accidente: %.0f s restantes"%car.crash_left
	if g.incidents.fire.has(p): return "Incendio · Paso cortado"
	if not g.road_open(p): return "Carretera cerrada, en obras o retirada"
	if car.step+1>=car.path.size(): return "Destino sin ruta disponible"
	var next = Vector2i(car.path[car.step+1])
	if g.incidents.fire.has(next): return "Incendio por delante · Esperando desvío o bomberos"
	if not g.road_open(next): return "Corte de carretera por delante"
	if not g.incidents.signal_allows(next,next-p): return "Semáforo en rojo"
	if car.get("yielding",false): return "Parado en cruce · Cediendo el paso"
	if car.get("blocked",false): return "Cola o capacidad agotada"
	if g.traffic.curve_factor(car)<1: return "Tomando curva · Velocidad al %d %% · "%roundi(g.WorldSettings.CURVE_SPEED_FACTOR*100)+g.cities[car.dest].name
	return "Circulando hacia "+g.cities[car.dest].name

func inspected_car() -> Dictionary:
	for car in g.cars:
		if car.ticket==selected_ticket: return car
	return {}

func select_car_at(p: Vector2i) -> void:
	var candidates: Array = []
	for car in g.cars:
		if g.traffic.position(car)==p: candidates.append(car.ticket)
	if candidates.is_empty():
		for car in g.cars: candidates.append(car.ticket)
	if candidates.is_empty(): selected_ticket=-1; g.tell("Todavía no hay vehículos en la red."); return
	selected_ticket=candidates[(candidates.find(selected_ticket)+1)%candidates.size()]

func weather_kind() -> String:
	if scenario_id=="winter" or g.incidents.rules.snow_chance>=1: return "snow"
	if g.incidents.rules.snow_chance<=0: return "fire"
	return next_weather

func weather_dispatched() -> void:
	next_weather="snow" if g.rng.randf()<g.incidents.rules.snow_chance else "fire"

func update(dt: float, real_dt: float) -> void:
	celebration_left=maxf(0,celebration_left-real_dt)
	if dt<=0 or scenario_done: return
	sample_clock+=dt
	monitor_clock+=dt
	upkeep_clock+=dt
	if monitor_clock>=2:
		monitor_clock=fmod(monitor_clock,2)
		diagnose()
		finish_review()
	if upkeep_clock>=60:
		var periods = int(upkeep_clock/60)
		upkeep_clock=fmod(upkeep_clock,60)
		g.transact(-upkeep_per_minute()*periods,"upkeep","Conservación de la red · %d min"%periods)
	if not scenario_id.is_empty() and g.elapsed>=scenario().duration: finish_scenario()

func scenario() -> Dictionary:
	for item in SCENARIOS:
		if item.id==scenario_id: return item
	return SCENARIOS[0]

func finish_scenario() -> void:
	if scenario_done: return
	scenario_done=true
	var definition = scenario()
	var achieved = connected_count()>=definition.goal if scenario_id=="network" else g.trips>=definition.goal
	var success = achieved and g.money>=0
	var score = maxi(0,g.trips*100+connected_count()*1000+int(g.money/10)-g.incidents.accidents*100-int(metrics().delay*10))
	scenario_result={"success":success,"score":score,"trips":g.trips,"connected":connected_count(),"money":g.money,"ranked":not scenario_cheated}
	if not scenario_cheated:
		var old = int(scores.get(scenario_id,{}).get("score",-1))
		if score>old:
			scores[scenario_id]=scenario_result.duplicate(true)
			save_scores()
	g.speed_index=0
	g.open_panel("scenarios")
	celebrate("Reto superado" if success else "Tiempo terminado · Puedes volver a intentarlo")

func save_scores() -> void:
	var file = FileAccess.open(records_path,FileAccess.WRITE)
	if file!=null: file.store_var(scores)

func load_scores() -> void:
	if not FileAccess.file_exists(records_path): return
	var file = FileAccess.open(records_path,FileAccess.READ)
	if file==null: return
	var data = file.get_var(false)
	if data is Dictionary: scores=data

func snapshot() -> Dictionary:
	return {"mode":mode,"reputation":reputation,"tier":tier,"contracts":contracts,"efficient_trips":efficient_trips,"samples":samples,"routes":routes,"road_income":road_income,"demand_credit":demand_credit,"connected_seen":connected_seen,"review":review,"improvements":improvements,"upkeep_clock":upkeep_clock,"scenario_id":scenario_id,"scenario_done":scenario_done,"scenario_result":scenario_result,"scenario_cheated":scenario_cheated,"overlay":overlay,"next_weather":next_weather}

func restore(data: Dictionary) -> void:
	reset(data.get("mode","free"),data.get("scenario_id",""))
	for key in ["reputation","tier","contracts","efficient_trips","samples","routes","road_income","demand_credit","connected_seen","review","improvements","upkeep_clock","scenario_done","scenario_result","scenario_cheated","overlay","next_weather"]:
		if data.has(key): set(key,data[key])
	prepare_cities()
	update_tier()
