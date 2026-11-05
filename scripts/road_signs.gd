extends RefCounted
## La orientación indica el rumbo del vehículo al llegar a la señal.
const DIRECTIONS = [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
const HEADINGS = ["Norte","Este","Sur","Oeste"]
const ARROWS = ["↑","→","↓","←"]
const LIMITS = [20,30,40,50,60,70,80,90,100,110,120]
const TYPES = {
	"stop":{"name":"STOP","family":"Prioridad","symbol":"STOP","description":"Obliga a detenerse antes de entrar y esperar a que quede libre el cruce."},
	"yield":{"name":"Ceda el paso","family":"Prioridad","symbol":"▽","description":"Deja pasar al tráfico con prioridad. Puede continuar si la vía está libre."},
	"priority":{"name":"Calzada con prioridad","family":"Prioridad","symbol":"◆","description":"Da preferencia a los vehículos del sentido indicado."},
	"no_entry":{"name":"Entrada prohibida","family":"Prohibición","symbol":"━","description":"Impide entrar en esta casilla desde el sentido indicado."},
	"one_way":{"name":"Sentido único","family":"Obligación","symbol":"↑","description":"La vía permite circular en el sentido indicado."},
	"no_left":{"name":"Giro a la izquierda prohibido","family":"Prohibición","symbol":"↰","description":"Los vehículos de este acceso deben elegir otro giro."},
	"no_right":{"name":"Giro a la derecha prohibido","family":"Prohibición","symbol":"↱","description":"Los vehículos de este acceso deben elegir otro giro."},
	"no_u":{"name":"Cambio de sentido prohibido","family":"Prohibición","symbol":"↶","description":"Impide dar la vuelta al llegar desde el sentido indicado."},
	"straight":{"name":"Dirección obligatoria recto","family":"Obligación","symbol":"↑","description":"Los vehículos de este acceso deben seguir recto."},
	"left":{"name":"Giro obligatorio a la izquierda","family":"Obligación","symbol":"↰","description":"Los vehículos de este acceso deben girar a la izquierda."},
	"right":{"name":"Giro obligatorio a la derecha","family":"Obligación","symbol":"↱","description":"Los vehículos de este acceso deben girar a la derecha."},
	"end_limit":{"name":"Fin de limitación de velocidad","family":"Prohibición","symbol":"╱","description":"Termina el límite anterior en el sentido indicado."},
	"no_overtaking":{"name":"Adelantamiento prohibido","family":"Prohibición","symbol":"↟","description":"Señal visual. El tráfico del juego ya mantiene su orden en el carril."},
	"curve_left":{"name":"Curva peligrosa a la izquierda","family":"Peligro","symbol":"↰"},
	"curve_right":{"name":"Curva peligrosa a la derecha","family":"Peligro","symbol":"↱"},
	"junction":{"name":"Cruce próximo","family":"Peligro","symbol":"+"},
	"roundabout":{"name":"Rotonda próxima","family":"Peligro","symbol":"⟳"},
	"pedestrians":{"name":"Peatones","family":"Peligro","symbol":"P"},
	"children":{"name":"Zona escolar","family":"Peligro","symbol":"N"},
	"animals":{"name":"Paso de animales","family":"Peligro","symbol":"A"},
	"slippery":{"name":"Pavimento deslizante","family":"Peligro","symbol":"≈"},
	"narrow":{"name":"Estrechamiento","family":"Peligro","symbol":"><"},
	"works":{"name":"Obras","family":"Temporal","symbol":"⚒"},
	"detour":{"name":"Desvío","family":"Temporal","symbol":"↱"},
	"crosswalk":{"name":"Paso de peatones","family":"Información","symbol":"▤"},
	"parking":{"name":"Aparcamiento","family":"Información","symbol":"P"},
	"hospital":{"name":"Hospital","family":"Información","symbol":"H"},
	"fuel":{"name":"Estación de servicio","family":"Información","symbol":"S"},
	"dead_end":{"name":"Calle sin salida","family":"Información","symbol":"⊤"},
	"direction":{"name":"Dirección y destinos","family":"Información","symbol":"↑"},
}
const PRIORITY = ["stop","yield","priority"]
const TURNS = ["no_left","no_right","no_u","straight","left","right"]
const MOVEMENT = ["no_entry","one_way","no_left","no_right","no_u","straight","left","right"]

var g
var placed: Dictionary = {}
var heading = 0
var limits: Dictionary = {}
var junction_priorities: Dictionary = {}
var has_movement_rules = false

func _init(game) -> void: g = game

static func definition(id: String) -> Dictionary:
	if id.begins_with("limit_") and id.trim_prefix("limit_").is_valid_int():
		var speed = int(id.trim_prefix("limit_"))
		if speed in LIMITS:
			return {"name":"Velocidad máxima %d km/h"%speed,"family":"Prohibición","symbol":str(speed),"description":"Limita la velocidad en este sentido hasta la siguiente señal de velocidad o el siguiente cruce."}
	return TYPES.get(id,{})

static func entries() -> Array:
	var result = TYPES.keys()
	for speed in LIMITS: result.insert(11+LIMITS.find(speed),"limit_"+str(speed))
	return result

func reset() -> void:
	placed.clear()
	limits.clear()
	junction_priorities.clear()
	heading = 0
	has_movement_rules = false

func rotate() -> void:
	heading = (heading+1)%4
	g.tell("Sentido de la señal · "+HEADINGS[heading])

func slot(id: String) -> String:
	if id in PRIORITY: return "priority"
	if id in ["straight","left","right"]: return "mandatory"
	if id=="end_limit" or id.begins_with("limit_"): return "speed"
	return id

func place(p: Vector2i, id: String) -> void:
	var spec = definition(id)
	if spec.is_empty(): return
	if not g.roads.has(p) or g.incidents.roundabout_cells.has(p):
		g.tell("Coloca la señal sobre una carretera o en el acceso a la rotonda.")
		return
	if g.roads[p].get("demolishing",false):
		g.tell("La vía se está demoliendo.")
		return
	var signs: Array = placed.get(p,[])
	for i in signs.size():
		var sign: Dictionary = signs[i]
		if slot(sign.id)!=slot(id) or (sign.direction!=heading and id!="one_way"): continue
		signs.remove_at(i)
		if sign.id==id and sign.direction==heading:
			if signs.is_empty(): placed.erase(p)
			g.graph_dirty = true
			g.tell("Señal retirada · "+spec.name+" · "+HEADINGS[heading])
			return
		break
	signs.append({"id":id,"direction":heading})
	placed[p] = signs
	g.services.invalidate_undo([p])
	g.roads[p].player_modified = true
	g.graph_dirty = true
	g.tell("Señal instalada · "+spec.name+" · "+HEADINGS[heading])

func priority(p: Vector2i, direction: Vector2i) -> String:
	var index = DIRECTIONS.find(direction)
	for sign in placed.get(p,[]):
		if sign.direction==index and sign.id in PRIORITY: return sign.id
	return ""

func has_priority(p: Vector2i) -> bool:
	for sign in placed.get(p,[]):
		if sign.id in PRIORITY: return true
	return false

func controls_junction(p: Vector2i) -> bool:
	return has_priority(p) or junction_priorities.has(p)

func approach_priority(p: Vector2i, direction: Vector2i) -> String:
	var sign = priority(p,direction)
	if not sign.is_empty(): return sign
	# Una señal en el acceso regula también el cruce inmediatamente posterior.
	# El STOP ya se cumple al llegar a su casilla; en el cruce se sigue cediendo.
	sign = junction_priorities.get(p,{}).get(direction,"")
	return "yield" if sign=="stop" else sign

func allows_edge(p: Vector2i, q: Vector2i) -> bool:
	var direction = DIRECTIONS.find((q-p).sign())
	for sign in placed.get(q,[]):
		if sign.id=="no_entry" and sign.direction==direction: return false
		if sign.id=="one_way" and sign.direction!=direction: return false
	for sign in placed.get(p,[]):
		if sign.id=="one_way" and sign.direction!=direction: return false
	return true

static func allows_turn(signs: Array, incoming: Vector2i, outgoing: Vector2i) -> bool:
	if incoming==Vector2i.ZERO: return true
	var index = DIRECTIONS.find(incoming)
	var right = Vector2i(-incoming.y,incoming.x)
	for sign in signs:
		if sign.direction!=index: continue
		match sign.id:
			"no_left": if outgoing==-right: return false
			"no_right": if outgoing==right: return false
			"no_u": if outgoing==-incoming: return false
			"straight": if outgoing!=incoming: return false
			"left": if outgoing!=-right: return false
			"right": if outgoing!=right: return false
	return true

func rebuild() -> void:
	limits.clear()
	junction_priorities.clear()
	has_movement_rules = false
	var boundaries: Dictionary = {}
	for p in placed:
		if not g.roads.has(p): continue
		for sign in placed[p]:
			if sign.id in PRIORITY and g.road_neighbours(p).size()<3:
				var direction: Vector2i = DIRECTIONS[sign.direction]
				var junction: Vector2i = p+direction
				if junction in g.road_neighbours(p) and g.road_neighbours(junction).size()>=3:
					if not junction_priorities.has(junction): junction_priorities[junction] = {}
					junction_priorities[junction][direction] = sign.id
			if sign.id in MOVEMENT: has_movement_rules = true
			if slot(sign.id)=="speed":
				boundaries[Vector3i(p.x,p.y,sign.direction)] = int(sign.id.trim_prefix("limit_")) if sign.id!="end_limit" else 0
	for start in boundaries:
		var speed: int = boundaries[start]
		if speed<=0: continue
		var direction: Vector2i = DIRECTIONS[start.z]
		var origin = Vector2i(start.x,start.y)
		var p = origin
		var previous = p-direction
		var visited: Dictionary = {}
		while true:
			var neighbours: Array = g.road_neighbours(p)
			if p!=origin and neighbours.size()>2: break
			var next = p+direction
			if p==origin and not next in neighbours and not previous in neighbours: break
			if not next in neighbours and neighbours.size()<=2:
				for q in neighbours:
					if q!=previous:
						next=q
						break
			if next==previous or g.incidents.roundabout_cells.has(next) or not g.edge_allowed(p,next): break
			direction = (next-p).sign()
			var index = DIRECTIONS.find(direction)
			var key = Vector3i(p.x,p.y,index)
			if visited.has(key): break
			visited[key] = true
			limits[key] = minf(limits.get(key,INF),speed/15.0)
			if boundaries.has(Vector3i(next.x,next.y,index)): break
			previous = p
			p = next

func speed_at(p: Vector2i, direction: Vector2i) -> float:
	if limits.is_empty(): return INF
	return limits.get(Vector3i(p.x,p.y,DIRECTIONS.find(direction)),INF)

func snapshot() -> Dictionary:
	return {"placed":placed,"heading":heading}

func restore(data: Dictionary) -> void:
	reset()
	placed = data.get("placed",{})
	heading = posmod(int(data.get("heading",0)),4)
