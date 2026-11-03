extends AStar2D
## El límite inferior debe respetar los pesos de las carreteras rápidas.
func _estimate_cost(from_id: int, end_id: int) -> float:
	return get_point_position(from_id).distance_to(get_point_position(end_id)) * 0.08
