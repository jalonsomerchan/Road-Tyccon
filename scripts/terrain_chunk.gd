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
	var variation = posmod(p.x*73+p.y*137,13)
	var index = 0
	match ground_type:
		0: index = 3 if variation==0 else 0
		1: index = 5
		2: index = 2
		3,4: index = 10
	sprite("terrain",index,area)
	if ground_type != 1:
		for d in game.DIRS:
			if game.ground(p+d)==1:
				var a = pos+Vector2(maxi(d.x,0),maxi(d.y,0))*CELL
				var b = a+(Vector2(0,CELL) if d.x!=0 else Vector2(CELL,0))
				solid(Rect2(a.min(b)-Vector2.ONE*CELL*0.035,(b-a).abs()+Vector2.ONE*CELL*0.07),Color("c2b780"))
	var ci = game.city_at(p)
	if ci>=0:
		var city = game.cities[ci]
		var offset = p-city.pos
		var plan = game.CityDesign.cell(city,offset)
		match plan.role:
			"street": pass # La capa de carreteras dibuja la vía transitable.
			"civic": sprite("terrain",12,area)
			"building":
				if city.design_style in [0,2,3]: sprite("terrain",12,area)

func draw_prop(p: Vector2i, center: Vector2) -> void:
	var ci = game.city_at(p)
	var variation = posmod(p.x*73+p.y*137,11)
	if ci>=0:
		if game.roads.has(p): return
		var city = game.cities[ci]
		var plan = game.CityDesign.cell(city,p-city.pos)
		if plan.role=="vacant": return
		if plan.role!="street":
			var size = Vector2.ONE*CELL*plan.scale
			sprite("props" if plan.role=="garden" else "buildings",plan.sprite,Rect2(center+plan.offset*CELL-size/2,size),plan.turns)
		return
	if game.roads.has(p) or (sparse and p.x%2==1): return
	match game.ground(p):
		2:
			var index = 8 if variation==0 else (7 if variation%3==0 else 6)
			var size = CELL*(1.03+variation*0.018)
			sprite("props",index,Rect2(center-Vector2.ONE*size/2,Vector2.ONE*size))
		3:
			var size = CELL*1.35
			sprite("props",9 if variation<3 else 10,Rect2(center-Vector2.ONE*size/2,Vector2.ONE*size))
		4: sprite("props",11,Rect2(center-Vector2.ONE*CELL/2,Vector2.ONE*CELL))
