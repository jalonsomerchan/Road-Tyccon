extends RefCounted
## Formas canónicas del atlas: recta N/S, curva N/E, T N/E/W, cruce N/E/S/W.
const SLUGS = ["dirt", "gravel", "concrete", "local", "secondary", "main", "express", "dual", "motorway", "premium", "wood_bridge", "stone_bridge", "concrete_bridge", "steel_bridge", "cable_bridge", "suspension_bridge", "forest", "farm", "cobble", "residential", "avenue", "county", "ring", "superhighway"]
const SHAPES = ["straight", "curve", "tee", "cross"]
const NORTH = 1
const EAST = 2
const SOUTH = 4
const WEST = 8
const DIRECTIONS = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

static func rotate_mask(mask: int, turns: int) -> int:
	for i in posmod(turns, 4): mask = ((mask << 1) & 15) | ((mask >> 3) & 1)
	return mask

static func shape_for(mask: int, horizontal: bool = false) -> Dictionary:
	var count = 0
	for bit in [1, 2, 4, 8]:
		if mask & bit: count += 1
	if count == 4: return {"shape":"cross", "turns":0}
	if count == 3:
		for turns in 4:
			if rotate_mask(11, turns) == mask: return {"shape":"tee", "turns":turns}
	if count == 2 and mask != 5 and mask != 10:
		for turns in 4:
			if rotate_mask(3, turns) == mask: return {"shape":"curve", "turns":turns}
	var along_x = mask == 10 or (count == 1 and (mask & 10) != 0) or (mask == 0 and horizontal)
	return {"shape":"straight", "turns":1 if along_x else 0}

static func mask_for(p: Vector2i, nodes: Dictionary, city_cells: Dictionary, connectors: Dictionary = {}) -> int:
	var mask = 0
	for i in 4:
		var q = p + DIRECTIONS[i]
		if nodes.has(q): mask |= 1 << i
	return mask
