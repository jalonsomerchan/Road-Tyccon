extends SceneTree
class IncomeRecorder extends RefCounted:
	var strings: Array = []
	var circles = 0
	func draw_string(_font,_at,value,_alignment,_width,_size,_color) -> void: strings.append(value)
	func draw_circle(_at,_radius,_color) -> void: circles+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	assert(game.explored.bounds.size==Vector2i.ONE*game.WorldSettings.INITIAL_SIDE and game.cities.size()==game.INITIAL_CITY_COUNT)
	assert(game.MIN_CITY_DISTANCE==100 and game.START_CITY_DISTANCE==100)
	var before=game.cities.size()
	var initial_bounds: Rect2i=game.explored.bounds
	game.travel_to(Vector2i(initial_bounds.end.x-1,initial_bounds.get_center().y))
	assert(game.explored.bounds.end.x>initial_bounds.end.x)
	assert(game.cities.size()>before,"Exploring new regions creates towns")
	var revealed: Dictionary=game.explored.regions.duplicate()
	var cities=game.cities.size()
	for i in 3: game.explore_around(Vector2(game.cursor))
	assert(game.cities.size()==cities and game.explored.regions==revealed,"Revisiting never duplicates cities")
	for i in range(before,game.cities.size()):
		for j in range(0,i):
			assert(Vector2(game.cities[i].pos).distance_to(Vector2(game.cities[j].pos))>=game.MIN_CITY_DISTANCE)
	game.travel_to(Vector2i(-1,-1))
	assert(game.cursor==Vector2i(-1,-1) and game.inside(game.cursor) and game.explored.contains(game.cursor))
	for p in [Vector2i(-1,-1),Vector2i(-32,-33),Vector2i(-1025,4),Vector2i(16400,-18000)]:
		assert(game.terrain.get_cell(p)==game.terrain.sample_cell(p),"Negative chunks use floor coordinates")
	assert(game.terrain.chunks.has(Vector2i(-1,-1)))
	var ids: Dictionary={}
	for p in [Vector2i(0,1),Vector2i(16384,0),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-16384,1)]:
		var id: int=game.point_id(p)
		assert(id>=0 and not ids.has(id),"Point IDs must not collide beyond the old world edge")
		ids[id]=true
	game.select_tool(0);game.kind=0
	game.anchor=Vector2i(-30,-20);game.cursor=Vector2i(-20,-20)
	for x in range(-30,-19):game.terrain.set_cell(Vector2i(x,-20),0)
	game.apply_action()
	assert(game.anchor==game.NO_CELL and game.roads.has(Vector2i(-25,-20)))
	game._process(2.0)
	assert(not game.graph.get_point_path(game.point_id(Vector2i(-30,-20)),game.point_id(Vector2i(-20,-20))).is_empty())
	game.cars=[{"path":PackedVector2Array([Vector2(-25,-20),Vector2(-24,-20)]),"step":0,"t":0.37,"ticket":91,"sprite_id":7,"color":7,"heading":Vector2.RIGHT,"born":game.elapsed,"age":0.0,"dest":0,"origin":0,"ideal":1.0,"accident_clock":0.0,"crash_left":0.0,"route_revision":game.road_revision}]
	game.save_path="res://tests/expanding_save.bin"
	game.save_game(false)
	var file=FileAccess.open(game.save_path,FileAccess.READ)
	var saved: Dictionary=file.get_var(false);file.close()
	var expected_regions: Dictionary=game.explored.regions.duplicate()
	var expected_cities=game.cities.size()
	var sample=game.terrain.get_cell(Vector2i(-40,-40))
	game.explored.reset()
	game.load_game()
	assert(game.explored.regions==expected_regions and game.cities.size()==expected_cities)
	assert(game.cars[0].sprite_id==7 and game.cars[0].heading==Vector2.RIGHT and is_equal_approx(game.cars[0].t,.37),"Saving preserves vehicle identity and segment progress")
	assert(game.terrain.get_cell(Vector2i(-40,-40))==sample and game.roads.has(Vector2i(-25,-20)))
	# A legacy save opens its original region and can expand beyond it.
	saved.erase("explored")
	file=FileAccess.open(game.save_path,FileAccess.WRITE);file.store_var(saved);file.close()
	game.load_game()
	assert(game.explored.bounds==Rect2i(0,0,16384,16384))
	game.travel_to(Vector2i(16410,8000))
	assert(game.explored.bounds.end.x>16384)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.save_path))
	# Stable models, standalone textures, and no overlapping vehicle drawings.
	for texture in game.visuals.sheets.vehicles:assert(not texture is AtlasTexture)
	game.camera=Vector2.ZERO;game.tile=32.0
	game.cars=[]
	for i in 3:
		game.cars.append({"path":PackedVector2Array([Vector2.ZERO,Vector2.RIGHT]),"step":0,"t":0.0,"ticket":i+1,"sprite_id":i,"heading":Vector2.RIGHT,"color":i})
	assert(game.visuals.car_draw_list().size()==1)
	for step in 13:
		game.cars[0].t=step/12.0
		var items=game.visuals.car_draw_list()
		for i in items.size():
			assert(items[i].sprite==items[i].car.sprite_id)
			for j in range(i+1,items.size()):assert(not items[i].bounds.intersects(items[j].bounds))
	game.cars[0].path=PackedVector2Array([Vector2.ZERO]);game.cars[0].step=0
	assert(game.visuals.car_direction(game.cars[0])==Vector2.RIGHT,"Stopped vehicles keep their heading")
	var driver={"path":PackedVector2Array([Vector2.ZERO,Vector2.RIGHT]),"step":0,"t":0.45,"ticket":90,"sprite_id":7,"color":7,"born":game.elapsed,"age":0.0,"dest":1,"origin":0,"ideal":1.0,"accident_clock":0.0,"crash_left":0.0,"route_revision":-1,"heading":Vector2.RIGHT}
	game.cars=[driver]
	game.route_cache[Vector3i(0,0,1)]=driver.path
	game.traffic.step_traffic(.001)
	assert(driver.t>=.45 and driver.sprite_id==7,"An unchanged route preserves in-cell progress and model")
	game.cars.clear();game.traffic.reset()
	game.cities=[{"unlocked":[1],"pop":1040,"accesses":[]},{"unlocked":[0],"pop":1040,"accesses":[]}]
	game.traffic.spawn_demand()
	assert(game.traffic.queued==2 and game.traffic.DEMAND_INTERVAL==6.0)
	game.cities[0].pop=10000;game.cities[1].pop=10000
	game.traffic.spawn_demand()
	assert(game.traffic.queued==8,"Large cities emit at most three trips per batch")
	var recorder=IncomeRecorder.new()
	game.visuals.canvas=recorder
	game.money_popups=[{"pos":Vector2.ZERO,"amount":100.0,"age":0.2}]
	game.visuals.draw_income()
	assert(recorder.circles==0 and "+100 €" in recorder.strings,"Income draws text only")
	game.visuals.canvas=game
	print("PASS: growing world, new/revisited regions, negative terrain/roads, unique graph IDs, region save/load and legacy expansion; calmer demand, stable standalone cars without overlap, income text only")
	game.free()
	quit()
