extends RefCounted
## Ajusta el ancho y el material de un acceso al perfil de la vía contigua.
const TILE = 64
const SIZE = TILE * 3
const SEAM = 6
const DEPTH = 34

static func bounds(image: Image, y: int) -> Vector2i:
	var left = image.get_width()
	var right = 0
	for x in image.get_width():
		if image.get_pixel(x,y).a < 0.12: continue
		left = mini(left,x)
		right = x+1
	return Vector2i(left,right)

static func blend_color(road: Color, arm: Color, weight: float) -> Color:
	var a = road.a*(1.0-weight)
	var b = arm.a*weight
	var alpha = a+b
	if alpha <= 0.001: return Color.TRANSPARENT
	var result = (road*a+arm*b)/alpha
	result.a = alpha
	return result

static func fit_arm(roundabout: Image, road: Image, direction: int, turns: int) -> void:
	# Trabajar con el acceso hacia el norte. El extremo de la carretera que
	# toca la rotonda queda en la última fila de su imagen orientada.
	road = road.duplicate()
	road.convert(Image.FORMAT_RGBA8)
	for i in posmod(turns-direction,4): road.rotate_90(CLOCKWISE)
	for i in direction: roundabout.rotate_90(COUNTERCLOCKWISE)

	var road_edge = bounds(road,TILE-1)
	if road_edge.x>=road_edge.y: road_edge = Vector2i(0,TILE)
	for y in DEPTH:
		var arm_edge = bounds(roundabout,y)
		var road_y = TILE-1-mini(y,11)
		if y<SEAM:
			roundabout.fill_rect(Rect2i(0,y,SIZE,1),Color.TRANSPARENT)
			roundabout.blit_rect(road,Rect2i(0,road_y,TILE,1),Vector2i(TILE,y))
			continue
		if arm_edge.x>=arm_edge.y: arm_edge = road_edge+Vector2i.ONE*TILE
		var taper = smoothstep(float(SEAM-1),float(DEPTH-1),float(y))
		var left = lerpf(road_edge.x+TILE,arm_edge.x,taper)
		var right = lerpf(road_edge.y+TILE,arm_edge.y,taper)
		var row = roundabout.get_region(Rect2i(0,y,SIZE,1))
		var material = smoothstep(8.0,float(DEPTH-1),float(y))
		for x in SIZE:
			var across = (float(x)+0.5-left)/(right-left)
			if across < 0.0 or across >= 1.0:
				roundabout.set_pixel(x,y,Color.TRANSPARENT)
				continue
			var road_x = int(lerpf(road_edge.x,road_edge.y,across))
			var arm_x = int(lerpf(arm_edge.x,arm_edge.y,across))
			var pixel = blend_color(road.get_pixel(road_x,road_y),row.get_pixel(arm_x,0),material)
			roundabout.set_pixel(x,y,pixel)
	for i in direction: roundabout.rotate_90(CLOCKWISE)
