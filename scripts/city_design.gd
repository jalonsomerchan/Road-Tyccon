extends RefCounted
## Plano urbano determinista: las calles del plano son carreteras reales.
const Settings = preload("res://scripts/world_settings.gd")
const BUILDINGS = ["villa","slate_house","timber_house","apartment","brick_block","warehouse","civic","park"]
const STYLES = ["Villa mediterránea","Ciudad jardín","Centro urbano","Barrio industrial"]
const PALETTES = [[0,0,0,4,2],[1,1,2,0],[3,3,4,1],[5,5,4,0]]
const DIRECTIONS = [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]

static func ensure(city: Dictionary, index: int, world_seed: int) -> void:
	if not city.has("design_seed"):
		city.design_seed = posmod(world_seed*48271+city.pos.x*73856093+city.pos.y*19349663+str(city.name).hash(),2147483647)
	if not city.has("design_style"): city.design_style = posmod(index+world_seed,STYLES.size())

static func initial_radius(pos: Vector2i, world_seed: int) -> int:
	var variation=Settings.CITY_RADIUS_VARIATION
	var hash_value=posmod(world_seed*48271+pos.x*73856093+pos.y*19349663,2147483647)
	return clampi(Settings.NEW_CITY_RADIUS+posmod(hash_value,variation*2+1)-variation,1,Settings.CITY_MAX_RADIUS)

static func variant(pos: Vector2i, world_seed: int) -> int:
	return posmod(world_seed*71+pos.x*31+pos.y*17,4)

static func noise(city: Dictionary, p: Vector2i) -> int:
	return posmod(int(city.get("design_seed",0)) ^ (p.x*73856093) ^ (p.y*19349663),2147483647)

static func local_cell(city: Dictionary, p: Vector2i) -> Vector2i:
	# La vía principal apunta al acceso preferido; la identidad no cambia al crecer.
	var preferred: Vector2i = city.get("access_dirs",[Vector2i.RIGHT])[0]
	return Vector2i(p.y,p.x) if preferred.y!=0 else p

static func is_street(city: Dictionary, p: Vector2i) -> bool:
	var radius: int = city.radius
	if absi(p.x)>radius or absi(p.y)>radius: return false
	var q = local_cell(city,p)
	if q.y==0: return true # Una única calle principal, nunca una banda de asfalto.
	if radius<2: return false
	var style = int(city.get("design_style",0))
	var seed = int(city.get("design_seed",0))
	var side = 1 if seed%2==0 else -1
	var other_side = 1 if (seed/2)%2==0 else -1
	var spacing = Settings.CITY_STREET_BLOCK_SPACING
	var variant_id=int(city.get("design_variant",0))
	# Ramales separados por una manzana, conectados al eje principal y sin añadir salidas falsas.
	if variant_id>0 and radius>=spacing and style!=1:
		var branch_side=side if style==3 else (1 if variant_id%2 else -1)
		var branch_length=mini(radius-1,1+variant_id)
		if q.y==spacing*branch_side and q.x*other_side>0 and q.x*other_side<=branch_length: return true
	match style:
		0: return q.x==0 # Dos calles con manzanas entre sus brazos.
		1:
			var length = radius if radius>=4 else mini(2,radius-1)
			return q.x==0 and q.y*side>0 and q.y*side<=length
		2:
			if q.x==0: return true
			if radius<=spacing: return false
			return (q.x==spacing*side and absi(q.y)<radius) or (q.y==spacing*other_side and absi(q.x)<radius)
		3:
			if q.x==0 and q.y*side>0: return true
			if radius<=spacing: return false
			# Un patio de servicio conectado, separado por dos parcelas de anchura.
			return (q.x==spacing*other_side and q.y*side>0 and q.y*side<=spacing) or (q.y==spacing*side and q.x*other_side>0 and q.x*other_side<=spacing)
	return false

static func exit_directions(city: Dictionary) -> Array:
	var result: Array = []
	for d in DIRECTIONS:
		if is_street(city,d*int(city.radius)): result.append(d)
	return result

static func cell(city: Dictionary, p: Vector2i) -> Dictionary:
	var hash_value = noise(city,p)
	var style = int(city.get("design_style",0))
	if is_street(city,p):
		var mask = 0
		for i in 4:
			var q = p+DIRECTIONS[i]
			if is_street(city,q): mask |= 1<<i
		return {"role":"street","mask":mask,"kind":street_kind(city,p)}
	var beside_street = false
	for d in DIRECTIONS:
		if is_street(city,p+d): beside_street=true; break
	if not beside_street:
		# Suelo sin urbanizar: no rellenar cada hueco con el mismo parque/fuente.
		if hash_value%100<22:
			return {"role":"garden","sprite":6+hash_value%3,"turns":0,"scale":0.58,"offset":Vector2.ZERO}
		return {"role":"vacant","sprite":0,"turns":0,"scale":0.0,"offset":Vector2.ZERO}
	if p==Vector2i(1,1): return {"role":"civic","sprite":6,"turns":0,"scale":0.86,"offset":Vector2.ZERO}
	var green = [18,38,8,24][style]+int(city.get("design_variant",0))*3
	if hash_value%100<green:
		if hash_value%7!=0:
			return {"role":"garden","sprite":6+hash_value%3,"turns":0,"scale":0.48+float(hash_value%5)*0.025,"offset":Vector2.ZERO}
		return {"role":"park","sprite":7,"turns":int(hash_value/11)%4,"scale":0.88,"offset":Vector2.ZERO}
	var choices: Array = PALETTES[style]
	var scale = [0.84,0.77,0.94,0.89][style]+float(hash_value%7)*0.006
	var shift = Vector2((hash_value%3)-1,(int(hash_value/3)%3)-1)*0.035
	return {"role":"building","sprite":choices[int(hash_value/101)%choices.size()],"turns":int(hash_value/17)%4,"scale":scale,"offset":shift}

static func street_kind(city: Dictionary, p: Vector2i) -> int:
	return Settings.AVENUE_ROAD_KIND if city.radius>=Settings.AVENUE_MIN_CITY_RADIUS and int(city.get("design_style",0))!=1 and local_cell(city,p).y==0 else Settings.RESIDENTIAL_ROAD_KIND

static func signature(city: Dictionary) -> int:
	return int(city.radius)*2147483647+int(city.get("design_seed",0))*5+int(city.get("design_style",0))+int(city.get("design_variant",0))*97
