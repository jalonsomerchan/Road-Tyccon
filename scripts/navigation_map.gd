extends RefCounted
## Vista del mapa independiente de la cámara de juego. Muestras de terreno acotadas por frame.
const RECT = Rect2(154,156,800,488)
const IMAGE_SIZE = Vector2i(256,160)
var g
var center = Vector2.ZERO
var target = Vector2i.ZERO
var span = 1800.0
var version = 0
var dirty = true
var since_change = 1.0
var building = false
var image: Image
var texture: ImageTexture
var image_view = Rect2()
var build_view = Rect2()
var row = 0
var seed_value = -1
var roads_revision = -1
var roads_view_version = -1
var road_pixels: Dictionary = {}

func _init(game) -> void:
	g = game

func view() -> Rect2:
	var size = Vector2(span * RECT.size.x / RECT.size.y,span)
	return Rect2(center-size/2,size)

func constrain() -> void:
	pass

func changed() -> void:
	constrain()
	version += 1
	dirty = true
	since_change = 0
	building = false

func open() -> void:
	if seed_value != g.world_seed:
		texture = null
		seed_value = g.world_seed
	known_region()
	target = g.cursor

func known_region() -> void:
	var low = Vector2(g.cursor)
	var high = low
	for city in g.cities:
		low = low.min(Vector2(city.pos))
		high = high.max(Vector2(city.pos))
	center = (low+high)/2
	span = maxf(128,maxf((high.x-low.x)*RECT.size.y/RECT.size.x,high.y-low.y)*1.35+220)
	changed()

func whole_region() -> void:
	center = Vector2(g.explored.bounds.get_center())
	span = maxf(g.explored.bounds.size.y,g.explored.bounds.size.x*RECT.size.y/RECT.size.x)*1.05
	target = g.cursor
	changed()

func pan(delta_world: Vector2) -> void:
	center += delta_world
	changed()
	target = Vector2i(center.round())

func zoom(factor: float) -> void:
	span = clampf(span/factor,64,maxf(65536,maxf(g.explored.bounds.size.x,g.explored.bounds.size.y)*4))
	changed()

func to_world(pixel: Vector2) -> Vector2i:
	var world = view().position + (pixel-RECT.position)/RECT.size*view().size
	return Vector2i(world.round())

func to_screen(world: Vector2) -> Vector2:
	return RECT.position+(world-view().position)/view().size*RECT.size

func update(delta: float) -> void:
	since_change += delta
	if not dirty or since_change < 0.10: return
	if not building:
		image = Image.create(IMAGE_SIZE.x,IMAGE_SIZE.y,false,Image.FORMAT_RGBA8)
		build_view = view()
		row = 0
		building = true
	var colors = [Color("7d925b"),Color("477e8c"),Color("365e48"),Color("b2b39c"),Color("918a6b")]
	var last = mini(IMAGE_SIZE.y,row+16)
	for y in range(row,last):
		for x in IMAGE_SIZE.x:
			var world = Vector2i((build_view.position + Vector2((x+0.5)/IMAGE_SIZE.x,(y+0.5)/IMAGE_SIZE.y)*build_view.size).floor())
			image.set_pixel(x,y,colors[g.terrain.sample_cell(world)] if g.explored.contains(world) else Color("132926"))
	row = last
	if row >= IMAGE_SIZE.y:
		texture = ImageTexture.create_from_image(image)
		image_view = build_view
		dirty = false
		building = false

func map_road_pixels() -> Dictionary:
	if roads_revision == g.road_revision and roads_view_version == version: return road_pixels
	roads_revision = g.road_revision
	roads_view_version = version
	road_pixels.clear()
	var visible = view()
	for p in g.roads:
		if visible.has_point(Vector2(p)):
			var screen = Vector2i(to_screen(Vector2(p)).floor())
			road_pixels[screen] = g.roads[p].closed or g.roads[p].work > 0
	return road_pixels
