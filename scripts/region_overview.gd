extends RefCounted
## Mosaicos en coordenadas del mundo: mover la cámara reutiliza terreno, sin volver a muestrearlo.
const DETAIL_THRESHOLD = 8.0
const SAMPLES = 32
const MAX_TILES = 192
const BUDGET_USEC = 1200
const ATLAS_SIDE = 512
const COLUMNS = ATLAS_SIDE/SAMPLES
const COLORS = [Color("93964f"),Color("297584"),Color("566239"),Color("a6a088"),Color("a6a088")]
var g
var texture: ImageTexture
var atlas_image: Image
var tiles: Dictionary = {}
var visible_tiles: Array = []
var pending: Array = []
var builds = 0
var labels: Array = []
var frame = 0
var player_revision = -1
var road_style: Array = []
var road_lines: Dictionary = {}
var deck_lines: Dictionary = {}
var city_names: Dictionary = {}

func _init(game) -> void: g=game

func view() -> Rect2:
	return Rect2(g.camera-Vector2(640,400)/g.tile,Vector2(1280,800)/g.tile)

func terrain_stamp(origin: Vector2i, side: int) -> Array:
	var result: Array = [g.terrain.generation]
	var first = Vector2i(floori(origin.x/256.0),floori(origin.y/256.0))
	var last = Vector2i(floori((origin.x+side-1)/256.0),floori((origin.y+side-1)/256.0))
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1): result.append(g.terrain.map_versions.get(Vector2i(x,y),0))
	return result

func update(budget: int = BUDGET_USEC) -> void:
	frame += 1
	var step = maxi(1,int(pow(2,ceil(log(4.0/g.tile)/log(2.0)))))
	var side = SAMPLES*step
	var visible = view()
	var first = Vector2i((visible.position/side).floor())
	var last = Vector2i((visible.end/side).floor())
	visible_tiles.clear();pending.clear()
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var origin = Vector2i(x,y)*side
			if not g.explored.contains(origin): continue
			var key = Vector3i(x,y,step)
			var stamp = terrain_stamp(origin,side)
			visible_tiles.append({"key":key,"origin":origin,"side":side})
			if tiles.has(key): tiles[key].used=frame
			if not tiles.has(key) or tiles[key].stamp!=stamp:
				pending.append({"key":key,"origin":origin,"side":side,"stamp":stamp})
	# La zona próxima al cursor aparece primero; los bordes se completan sin parar el movimiento.
	pending.sort_custom(func(a,b): return Vector2(a.origin).distance_squared_to(g.camera)<Vector2(b.origin).distance_squared_to(g.camera))
	if atlas_image==null: atlas_image=Image.create(ATLAS_SIDE,ATLAS_SIDE,false,Image.FORMAT_RGB8)
	var changed=false
	var deadline = Time.get_ticks_usec()+budget
	while not pending.is_empty() and Time.get_ticks_usec()<deadline:
		var job = pending.pop_front()
		var image = Image.create(SAMPLES,SAMPLES,false,Image.FORMAT_RGB8)
		for y in SAMPLES:
			for x in SAMPLES:
				var p = job.origin+Vector2i(x*step+step/2,y*step+step/2)
				image.set_pixel(x,y,COLORS[g.terrain.sample_cell(p)])
		var slot=tiles[job.key].slot if tiles.has(job.key) else tiles.size()
		if not tiles.has(job.key) and tiles.size()>=MAX_TILES:
			var oldest=tiles.keys()[0]
			for key in tiles:
				if tiles[key].used<tiles[oldest].used: oldest=key
			slot=tiles[oldest].slot;tiles.erase(oldest)
		var at=Vector2i(slot%COLUMNS,int(slot/COLUMNS))*SAMPLES
		atlas_image.blit_rect(image,Rect2i(0,0,SAMPLES,SAMPLES),at)
		tiles[job.key]={"slot":slot,"stamp":job.stamp,"used":frame}
		builds += 1;changed=true
	if changed:
		if texture==null: texture=ImageTexture.create_from_image(atlas_image)
		else: texture.update(atlas_image)

func prepare_roads() -> void:
	var style: Array = [g.gameplay.overlay,int(g.elapsed*2) if g.gameplay.overlay!="none" else 0]
	if player_revision==g.road_revision and road_style==style: return
	player_revision=g.road_revision;road_style=style;road_lines.clear();deck_lines.clear()
	for p in g.roads:
		if not g.gameplay.is_player_road(p): continue
		var road=g.roads[p]
		var color=Color("bad08c")
		if road.closed or road.work>0: color=Color("dd9477")
		elif g.gameplay.overlay=="condition": color=Color("df775d") if road.hp<40 else (Color("d0b36b") if road.hp<75 else Color("a4cc90"))
		elif g.gameplay.overlay=="traffic": color=Color("df775d") if g.density.get(p,0)>=g.traffic.capacity(p) else Color("a4cc90")
		elif g.gameplay.overlay=="profit":
			var revenue=float(g.gameplay.road_income.get(p,0))/maxf(1,g.elapsed/60)
			color=Color("a4cc90") if revenue>=g.Catalog.ROADS[road.kind].cost*.0008 else Color("df775d")
		if not road_lines.has(color): road_lines[color]=PackedVector2Array()
		var axis=Vector2.RIGHT if road.axis else Vector2.DOWN
		road_lines[color].append(Vector2(p)-axis*.5);road_lines[color].append(Vector2(p)+axis*.5)
	for span in g.bridge_spans:
		var a = Vector2i(span.x,span.y)
		var b = Vector2i(span.z,span.w)
		if not g.roads.has(a) or not g.roads.has(b): continue
		var color = Color("dd9477") if g.bridge_spans[span]>0 or g.roads[a].closed or g.roads[b].closed or g.roads[a].work>0 or g.roads[b].work>0 else Color("c0ddd0")
		if not deck_lines.has(color): deck_lines[color]=PackedVector2Array()
		var half_cell = Vector2(b-a).normalized()*0.5
		deck_lines[color].append(Vector2(a)+half_cell)
		deck_lines[color].append(Vector2(b)-half_cell)

func draw(v) -> void:
	update()
	v.rect(Rect2(0,60,1280,630),Color("132926"))
	for item in visible_tiles:
		var area = Rect2(g.screen(Vector2(item.origin)-Vector2.ONE*.5),Vector2.ONE*item.side*g.tile)
		if tiles.has(item.key):
			var slot:int=tiles[item.key].slot
			v.canvas.draw_texture_rect_region(texture,area,Rect2(Vector2(slot%COLUMNS,int(slot/COLUMNS))*SAMPLES,Vector2.ONE*SAMPLES))
		else: v.rect(area,COLORS[0].darkened(.18))
	prepare_roads()
	v.canvas.draw_set_transform(g.screen(Vector2.ZERO),0,Vector2.ONE*g.tile)
	for color in road_lines:
		v.canvas.draw_multiline(road_lines[color],color,maxf(1.0,1.0/g.tile))
	for color in deck_lines:
		v.canvas.draw_multiline(deck_lines[color],color,maxf(1.0,1.0/g.tile))
	v.canvas.draw_set_transform(Vector2.ZERO)
	var area=Rect2(8,92,1264,585)
	for car in g.cars:
		var at=g.screen(Vector2(g.traffic.position(car)))
		if area.has_point(at): v.canvas.draw_circle(at,2,Color("f1e4ac") if not car.get("blocked",false) else Color("ed886d"))
	for p in g.incidents.fire:
		var at=g.screen(Vector2(p))
		if area.has_point(at): v.canvas.draw_circle(at,3,Color("f08758"))
	for p in g.incidents.snow:
		var at=g.screen(Vector2(p))
		if area.has_point(at): v.canvas.draw_circle(at,1.5,Color("98c9d9"))
	var occupied: Array[Rect2] = []
	labels.clear()
	var markers:Dictionary={}
	var label_draws:Array=[]
	for i in g.cities.size():
		var city=g.cities[i]
		var at=g.screen(Vector2(city.pos))
		if not area.has_point(at): continue
		var connected=not g.traffic.current_links.get(i,[]).is_empty()
		var color=Color("d6e7a3") if connected else Color("e3c493")
		if not markers.has(color): markers[color]=PackedVector2Array()
		markers[color].append(at-Vector2(1,0));markers[color].append(at+Vector2(1,0))
		if occupied.size()>=32: continue
		if not city_names.has(city.name): city_names[city.name]=g.font.get_string_size(city.name,HORIZONTAL_ALIGNMENT_LEFT,-1,12)+Vector2(10,6)
		var label=Rect2(at+Vector2(6,-19),city_names[city.name])
		var clear=area.encloses(label)
		for previous in occupied:
			if previous.grow(10).intersects(label): clear=false;break
		if clear:
			occupied.append(label);labels.append(city.name)
			label_draws.append({"rect":label,"name":city.name})
	for color in markers: v.canvas.draw_multiline(markers[color],color,5.0)
	for label in label_draws:
		v.rect(label.rect,Color("19342e"));v.text(label.rect.position+Vector2(5,14),label.name,12,v.PAPER)
	var cursor=g.screen(Vector2(g.cursor))
	v.canvas.draw_line(cursor-Vector2(9,0),cursor+Vector2(9,0),v.PAPER,2)
	v.canvas.draw_line(cursor-Vector2(0,9),cursor+Vector2(0,9),v.PAPER,2)
	if g.anchor!=g.NO_CELL:
		var turn=Vector2(g.cursor.x,g.anchor.y) if g.horizontal else Vector2(g.anchor.x,g.cursor.y)
		v.canvas.draw_polyline(PackedVector2Array([g.screen(Vector2(g.anchor)),g.screen(turn),cursor]),v.GREEN,2)
	v.text(Vector2(20,671),"VISTA REGIONAL · %.0f × %.0f casillas"%[1280/g.tile,800/g.tile],12,v.GREEN)
