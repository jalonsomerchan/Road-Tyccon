extends RefCounted
## Sincroniza el plano sin acumular calles de radios anteriores ni tocar obras del jugador.
const Design = preload("res://scripts/city_design.gd")
const Settings = preload("res://scripts/world_settings.gd")

static func sync(g) -> void:
	g.retired_city_cells.clear()
	var desired: Dictionary = {}
	var generated: Dictionary = {}
	for p in g.roads:
		if g.roads[p].has("generated_city"): generated[p]=g.roads[p].generated_city
	for i in g.cities.size():
		var c = g.cities[i]
		# Migración de la primera red urbana, que todavía no guardaba procedencia.
		if not c.has("road_plan_version"):
			for y in range(-c.radius,c.radius+1):
				for x in range(-c.radius,c.radius+1):
					var p = c.pos+Vector2i(x,y)
					if g.roads.has(p) and g.roads[p].has("urban_city") and g.roads[p].kind in [Settings.RESIDENTIAL_ROAD_KIND,Settings.AVENUE_ROAD_KIND]: generated[p]=i
			for a in c.accesses:
				for step in Settings.CITY_ACCESS_LENGTH:
					var p = a.gate+a.dir*step
					if g.roads.has(p) and g.roads[p].kind in [Settings.RESIDENTIAL_ROAD_KIND,Settings.AVENUE_ROAD_KIND]: generated[p]=i
		for y in range(-c.radius,c.radius+1):
			for x in range(-c.radius,c.radius+1):
				var offset = Vector2i(x,y)
				if Design.is_street(c,offset):
					desired[c.pos+offset]={"owner":i,"kind":Design.street_kind(c,offset),"axis":Design.local_cell(c,offset).y==0,"role":"street"}
		for d in Design.exit_directions(c):
			var edge = c.pos+d*c.radius
			for step in range(1,Settings.CITY_ACCESS_LENGTH+1):
				var p = edge+d*step
				if g.city_at(p)>=0: continue
				desired[p]={"owner":i,"kind":Design.street_kind(c,edge-c.pos),"axis":d.x!=0,"role":"access"}
		c.road_plan_version=2
	# Proteger los corredores que conectan con carreteras del jugador, y cualquier
	# obra, cierre, semáforo o modificación explícita de la vía generada.
	var retained: Dictionary = {}
	for p in generated:
		if not g.roads.has(p): continue
		var r = g.roads[p]
		var owner: int = generated[p]
		if owner<0 or owner>=g.cities.size(): continue
		var keep: bool = r.get("player_modified",false) or r.closed or r.work>0 or g.incidents.signals.has(p) or r.kind not in [Settings.RESIDENTIAL_ROAD_KIND,Settings.AVENUE_ROAD_KIND]
		for d in g.DIRS:
			var q = p+d
			if g.roads.has(q) and not generated.has(q) and g.city_at(q)!=owner: keep=true
		if keep:
			for q in corridor(g,p,owner,generated,desired): retained[q]=true
			retained[p]=true
	for p in generated:
		if not g.roads.has(p): continue
		if retained.has(p):
			g.roads[p].player_modified=true
			g.roads[p].generated_city=generated[p]
			g.roads[p].generated_role="street" if g.city_at(p)>=0 else "access"
		if desired.has(p) or retained.has(p): continue
		g.retired_city_cells[p]=generated[p]
		g.roads.erase(p);g.road_nodes.erase(p)
	for p in desired:
		var plan = desired[p]
		var created = false
		if not g.roads.has(p) and not g.demolished_access_tiles.has(p):
			g.roads[p]=g.city_road(plan.kind,plan.axis)
			created=true
		if not g.roads.has(p): continue
		var r = g.roads[p]
		if created or generated.has(p):
			r.generated_city=plan.owner
			r.generated_role=plan.role
			if not r.get("player_modified",false): r.kind=plan.kind;r.axis=plan.axis
		if plan.role=="street": r.urban_city=plan.owner
		else:
			r.erase("urban_city")
			g.terrain.set_cell(p,0)
		g.road_nodes[p]={"kind":r.kind,"axis":r.axis}
	for p in g.roads:
		var owner = g.city_at(p)
		if owner>=0: g.roads[p].urban_city=owner
		else: g.roads[p].erase("urban_city")
	# Si una migración retira la antigua calle, sus coches conservan su viaje.
	for car in g.cars:
		var p = g.traffic.position(car)
		if not g.retired_city_cells.has(p): continue
		var at = nearest_street(g,p,g.retired_city_cells[p])
		car.path=PackedVector2Array([Vector2(at)]);car.step=0;car.t=0.0;car.route_revision=-1
	g.refresh_city_connectors()

static func corridor(g, start: Vector2i, owner: int, generated: Dictionary, desired: Dictionary) -> Array:
	var queue: Array[Vector2i] = [start]
	var previous: Dictionary = {start:start}
	var index = 0
	while index<queue.size():
		var p = queue[index];index+=1
		if desired.has(p) and desired[p].owner==owner and desired[p].role=="street":
			var path: Array = [p]
			while p!=start: p=previous[p];path.append(p)
			return path
		for d in g.DIRS:
			var q = p+d
			if previous.has(q) or not g.roads.has(q): continue
			if generated.get(q,-1)!=owner and g.city_at(q)!=owner: continue
			previous[q]=p;queue.append(q)
	return [start]

static func nearest_street(g, at: Vector2i, owner: int) -> Vector2i:
	var nearest = at
	var distance = INF
	for p in g.roads:
		if g.city_at(p)!=owner: continue
		var candidate = Vector2(p).distance_squared_to(Vector2(at))
		if candidate<distance: nearest=p;distance=candidate
	return nearest
