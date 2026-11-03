extends AStar2D
## El rumbo forma parte de la búsqueda: girar en un cruce también consume tiempo.
const Settings = preload("res://scripts/world_settings.gd")
const DIRECTIONS = [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
var minimum_step_cost = 0.0
var junction_delays: Dictionary = {}

func _estimate_cost(from_id: int, end_id: int) -> float:
	return get_point_position(from_id).distance_to(get_point_position(end_id))*minimum_step_cost

static func direction_index(direction: Vector2i) -> int:
	var index = DIRECTIONS.find(direction)
	return index if index>=0 else 4

static func turn_factor(incoming: Vector2i, outgoing: Vector2i) -> float:
	return Settings.CURVE_SPEED_FACTOR if incoming!=Vector2i.ZERO and outgoing!=Vector2i.ZERO and incoming!=outgoing else 1.0

func passage_factor(point: int, incoming: Vector2i, outgoing: Vector2i) -> float:
	if incoming!=Vector2i.ZERO: return turn_factor(incoming,outgoing)
	# Si la partida antigua o una salida comienza en una curva, inferir sus dos brazos.
	var neighbours = get_point_connections(point)
	if neighbours.size()==2:
		var a = Vector2i(get_point_position(neighbours[0])-get_point_position(point))
		var b = Vector2i(get_point_position(neighbours[1])-get_point_position(point))
		if a!=-b: return Settings.CURVE_SPEED_FACTOR
	return 1.0

func heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var child = heap.size()-1
	while child>0:
		var parent = (child-1)/2
		if heap[parent][0]<=entry[0]: break
		heap[child]=heap[parent]
		child=parent
	heap[child]=entry

func heap_pop(heap: Array) -> Array:
	var first: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty(): return first
	var parent = 0
	while parent*2+1<heap.size():
		var child = parent*2+1
		if child+1<heap.size() and heap[child+1][0]<heap[child][0]: child+=1
		if last[0]<=heap[child][0]: break
		heap[parent]=heap[child]
		parent=child
	heap[parent]=last
	return first

func driving_path(start: int, destination: int, incoming: Vector2i = Vector2i.ZERO) -> PackedVector2Array:
	if not has_point(start) or not has_point(destination): return PackedVector2Array()
	if start==destination: return PackedVector2Array([get_point_position(start)])
	var initial = start*5+direction_index(incoming)
	var costs: Dictionary = {initial:0.0}
	var previous: Dictionary = {}
	var heap: Array = []
	heap_push(heap,[_estimate_cost(start,destination),initial,0.0])
	while not heap.is_empty():
		var entry = heap_pop(heap)
		var state: int = entry[1]
		if entry[2]!=costs[state]: continue
		var point: int = state/5
		if point==destination:
			var result = PackedVector2Array()
			while true:
				result.append(get_point_position(int(state/5)))
				if state==initial: break
				state=previous[state]
			result.reverse()
			return result
		var heading: Vector2i = DIRECTIONS[state%5] if state%5<4 else Vector2i.ZERO
		for next in get_point_connections(point):
			var outgoing = Vector2i(get_point_position(next)-get_point_position(point))
			var next_state: int = next*5+direction_index(outgoing)
			var cost: float = costs[state]+get_point_weight_scale(point)/passage_factor(point,heading,outgoing)+junction_delays.get(next,0.0)
			if cost>=float(costs.get(next_state,INF)): continue
			costs[next_state]=cost
			previous[next_state]=state
			heap_push(heap,[cost+_estimate_cost(next,destination),next_state,cost])
	return PackedVector2Array()
