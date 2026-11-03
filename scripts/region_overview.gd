extends RefCounted
## Vista regional muestreada: coste acotado incluso con millones de casillas en pantalla.
const SIZE = Vector2i(400,250)
const DETAIL_THRESHOLD = 8.0
const COLORS = [Color("869663"),Color("487f90"),Color("3e654c"),Color("a6ac99"),Color("8b8c76")]
var g
var texture: ImageTexture
var image: Image
var image_view = Rect2()
var build_view = Rect2()
var row = 0
var building = false
var stamp: Array = []
var build_stamp: Array = []
var builds = 0
var labels: Array = []

func _init(game) -> void: g=game

func view() -> Rect2:
	return Rect2(g.camera-Vector2(640,400)/g.tile,Vector2(1280,800)/g.tile)

func state() -> Array:
	return [g.world_seed,g.terrain.generation,g.road_revision,g.explored.revision,g.gameplay.overlay,int(g.elapsed/10) if g.gameplay.overlay!="none" else 0]

func update() -> void:
	if not building:
		var visible=view()
		if texture!=null and stamp==state() and image_view.encloses(visible) and image_view.size.x/visible.size.x<1.7: return
		var size=Vector2(1600,1000)/g.tile
		build_view=Rect2(g.camera-size/2,size)
		build_stamp=state()
		image=Image.create(SIZE.x,SIZE.y,false,Image.FORMAT_RGB8)
		row=0;building=true
	var end=mini(SIZE.y,row+40)
	for y in range(row,end):
		for x in SIZE.x:
			var p=Vector2i((build_view.position+Vector2(x+.5,y+.5)/Vector2(SIZE)*build_view.size).floor())
			image.set_pixel(x,y,COLORS[g.terrain.sample_cell(p)] if g.explored.contains(p) else Color("132926"))
	row=end
	if row<SIZE.y: return
	for p in g.roads:
		if not build_view.has_point(Vector2(p)): continue
		var pixel=Vector2i(((Vector2(p)-build_view.position)/build_view.size*Vector2(SIZE)).floor())
		var road=g.roads[p]
		var color=Color("bad08c") if g.gameplay.is_player_road(p) else Color("8d9c80")
		if road.closed or road.work>0: color=Color("dd9477")
		elif g.gameplay.overlay=="condition": color=Color("df775d") if road.hp<40 else (Color("d0b36b") if road.hp<75 else Color("a4cc90"))
		elif g.gameplay.overlay=="profit" and g.gameplay.is_player_road(p):
			var revenue=float(g.gameplay.road_income.get(p,0))/maxf(1,g.elapsed/60)
			color=Color("a4cc90") if revenue>=g.Catalog.ROADS[road.kind].cost*.0008 else Color("df775d")
		image.set_pixel(pixel.x,pixel.y,color)
	texture=ImageTexture.create_from_image(image)
	image_view=build_view;stamp=build_stamp;building=false;builds+=1

func draw(v) -> void:
	update()
	v.rect(Rect2(0,60,1280,630),Color("132926"))
	if texture!=null: v.canvas.draw_texture_rect(texture,Rect2(g.screen(image_view.position),image_view.size*g.tile),false)
	# Señales y vehículos conservan su posición real aunque se simplifique su dibujo.
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
	for i in g.cities.size():
		var city=g.cities[i]
		var at=g.screen(Vector2(city.pos))
		if not area.has_point(at): continue
		var connected=not g.traffic.current_links.get(i,[]).is_empty()
		v.canvas.draw_circle(at,3,Color("d6e7a3") if connected else Color("e3c493"))
		var size=g.font.get_string_size(city.name,HORIZONTAL_ALIGNMENT_LEFT,-1,12)+Vector2(10,6)
		var label=Rect2(at+Vector2(6,-19),size)
		var clear=area.encloses(label)
		for previous in occupied:
			if previous.grow(10).intersects(label): clear=false;break
		if clear and occupied.size()<32:
			occupied.append(label);labels.append(city.name)
			v.rect(label,Color("19342e"))
			v.text(label.position+Vector2(5,14),city.name,12,v.PAPER)
	var cursor=g.screen(Vector2(g.cursor))
	v.canvas.draw_line(cursor-Vector2(9,0),cursor+Vector2(9,0),v.PAPER,2)
	v.canvas.draw_line(cursor-Vector2(0,9),cursor+Vector2(0,9),v.PAPER,2)
	if g.anchor!=g.NO_CELL:
		var turn=Vector2(g.cursor.x,g.anchor.y) if g.horizontal else Vector2(g.anchor.x,g.cursor.y)
		v.canvas.draw_polyline(PackedVector2Array([g.screen(Vector2(g.anchor)),g.screen(turn),cursor]),v.GREEN,2)
	v.text(Vector2(20,671),"VISTA REGIONAL · %.0f × %.0f casillas"%[1280/g.tile,800/g.tile],12,v.GREEN)
