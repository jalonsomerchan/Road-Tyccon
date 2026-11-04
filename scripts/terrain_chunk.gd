extends Node2D
## Comandos de dibujo retenidos por Godot: moverse o hacer zoom solo cambia la transformación.
var game
var origin = Vector2i.ZERO
var props = false
var sparse = false
var stamp: Array = []
var rebuilds = 0
var built_stamp: Array = []
var mesh: ArrayMesh
var vertices = PackedVector3Array()
var uvs = PackedVector2Array()
var colors = PackedColorArray()
var indices = PackedInt32Array()
const CELL = 32.0
const SIDE = 32

func quad(area: Rect2, uv: Rect2, color: Color = Color.WHITE, turns: int = 0) -> void:
	var base = vertices.size()
	var corners = [Vector2.ZERO,Vector2(1,0),Vector2.ONE,Vector2(0,1)]
	for i in 4:
		var at = corners[i]
		var p = area.position+at*area.size
		vertices.append(Vector3(p.x,p.y,0))
		uvs.append(uv.position+corners[posmod(i-turns,4)]*uv.size)
		colors.append(color)
	indices.append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3]))

func solid(area: Rect2, color: Color) -> void:
	quad(area,Rect2(game.visuals.atlas_white_uv,Vector2.ZERO),color)

func sprite(family: String, index: int, area: Rect2, turns: int = 0) -> void:
	var texture = game.visuals.sheets[family][index]
	if texture == null: return
	quad(area,Rect2(texture.region.position/game.visuals.scenery_atlas_size,texture.region.size/game.visuals.scenery_atlas_size),Color.WHITE,turns)

func _draw() -> void:
	if mesh != null and built_stamp == stamp:
		if mesh.get_surface_count()>0: draw_mesh(mesh,game.visuals.scenery_atlas)
		return
	built_stamp = stamp
	rebuilds += 1
	vertices.clear(); uvs.clear(); colors.clear(); indices.clear()
	for y in SIDE:
		for x in SIDE:
			var p = origin+Vector2i(x,y)
			if not game.inside(p): continue
			var pos = Vector2(x,y)*CELL
			if props: draw_prop(p,pos+Vector2.ONE*CELL/2)
			else: draw_ground(p,pos)

	mesh = ArrayMesh.new()
	if not vertices.is_empty():
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		draw_mesh(mesh,game.visuals.scenery_atlas)
	# El buffer vive en la malla; no conservar una segunda copia en GDScript.
	vertices.clear(); uvs.clear(); colors.clear(); indices.clear()

func draw_ground(p: Vector2i, pos: Vector2) -> void:
	var area = Rect2(pos,Vector2.ONE*CELL)
	var ground_type = game.ground(p)
	var index = 0
	match ground_type:
		1: index = 5
		2: index = 2
		3,4: index = 10
	var ci = game.city_at(p)
	if ci>=0:
		var city = game.cities[ci]
		var plan = game.CityDesign.cell(city,p-city.pos)
		if plan.role in ["building","civic"]: index = game.visuals.PAVEMENT_TILE
	sprite("terrain",index,area)
	if ground_type != 1:
		for d in game.DIRS:
			if game.ground(p+d)==1:
				var a = pos+Vector2(maxi(d.x,0),maxi(d.y,0))*CELL
				var b = a+(Vector2(0,CELL) if d.x!=0 else Vector2(CELL,0))
				solid(Rect2(a.min(b)-Vector2.ONE*CELL*0.035,(b-a).abs()+Vector2.ONE*CELL*0.07),Color("c2b780"))

func draw_prop(p: Vector2i, center: Vector2) -> void:
	var ci = game.city_at(p)
	if ci>=0:
		if game.roads.has(p): return
		var city = game.cities[ci]
		var plan = game.CityDesign.cell(city,p-city.pos)
		if plan.role=="vacant": return
		if plan.role!="street":
			var size = Vector2.ONE*CELL*plan.scale
			sprite("props" if plan.role=="garden" else "buildings",plan.sprite,Rect2(center+plan.offset*CELL-size/2,size),plan.turns)
		return
	if game.roads.has(p): return
	var variation = hash(p)
	var ground_type = game.ground(p)
	var offset = Vector2((variation >> 12)%5-2,(variation >> 15)%5-2)*CELL*0.045
	match ground_type:
		0:
			if sparse or variation%23!=0: return
			var size = CELL*0.48
			sprite("scrub",(variation >> 5)%2,Rect2(center-Vector2.ONE*size/2,Vector2.ONE*size))
		2:
			# Cada sprite reúne varias copas en un solo cuadrilátero.
			if variation%8 < (5 if sparse else 1): return
			var index = (variation >> 3)%4
			var size = CELL*(0.90+float((variation >> 5)%4)*0.045)
			sprite("trees",index,Rect2(center+offset-Vector2.ONE*size/2,Vector2.ONE*size))
		3,4:
			# Las crestas alternan con laderas. Los antiguos roquedos siempre tienen un pico.
			if ground_type==3 and variation%5>1: return
			var size = Vector2(1.08,1.24+float((variation >> 5)%3)*0.07)*CELL
			sprite("mountains",(variation >> 8)%3,Rect2(center+offset*0.5-size/2,size))
