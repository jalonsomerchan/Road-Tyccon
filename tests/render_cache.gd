extends SceneTree
var game
func _initialize() -> void: call_deferred("run")
func frame() -> void:
	game.queue_redraw()
	await process_frame
	RenderingServer.force_draw(false)
func rebuild_count(cache) -> int:
	var result = 0
	for block in cache.blocks.values(): result += block.ground.rebuilds+block.props.rebuilds
	return result
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.tile = 8
	game.zoom_target = 8
	game.notice_time = 0
	for i in 3: await frame()
	var cache = game.visuals.terrain_cache
	assert(cache.blocks.size()<=cache.MAX_BLOCKS)
	assert(cache.ground_root.get_index()<cache.road_layer.get_index())
	assert(cache.road_layer.get_index()<cache.props_root.get_index())
	var count = rebuild_count(cache)
	for i in 5: await frame()
	assert(rebuild_count(cache)==count,"Stable frames reuse geometry")
	game.camera += Vector2(0.25,0.25)
	game.tile = 9
	for i in 2: await frame()
	assert(rebuild_count(cache)==count,"Camera and zoom transform existing geometry")
	# Showing a retained block again reuses its mesh instead of rebuilding it.
	var retained = cache.blocks.values()[0]
	retained.ground.hide()
	await frame()
	assert(rebuild_count(cache)==count)
	# Editing a boundary cell also invalidates the neighboring riverbank block.
	var p = Vector2i(game.cursor.x/32*32,game.cursor.y/32*32)
	var key = cache.key_for(p)
	game.terrain.set_cell(p,1)
	for i in 2: await frame()
	assert(cache.blocks[key].ground.rebuilds>1)
	assert(game.terrain.render_versions.has(key-Vector2i.RIGHT) and game.terrain.render_versions.has(key-Vector2i.DOWN))
	var ground_count: int = cache.blocks[key].ground.rebuilds
	var props_count: int = cache.blocks[key].props.rebuilds
	# Adding a road changes scenery occupancy only; closing it doesn't rebuild terrain.
	game.roads[p] = {"kind":0,"hp":100.0,"closed":false,"work":0.0,"total":1.0,"axis":true,"last_used":game.elapsed}
	game.rebuild_graph()
	for i in 2: await frame()
	assert(cache.blocks[key].ground.rebuilds==ground_count)
	assert(cache.blocks[key].props.rebuilds>props_count)
	assert(p in cache.visible_roads)
	count = rebuild_count(cache)
	game.roads[p].closed = true
	game.rebuild_graph()
	for i in 2: await frame()
	assert(rebuild_count(cache)==count,"Opening/closing roads keeps static geometry")
	# Logging and city growth invalidate their own ground/scenery blocks.
	game.terrain.set_cell(p,0)
	for i in 2: await frame()
	assert(cache.blocks[key].ground.rebuilds>ground_count)
	game.cities[0].pop = 3000
	game.grow_cities()
	game.rebuild_graph()
	for i in 2: await frame()
	assert(cache.city_stamps.size()>0)
	# LRU stays bounded after travelling through many different regions.
	for i in 7:
		game.camera = Vector2(-800-i*1100,-1000-i*900)
		await frame()
		assert(cache.blocks.size()<=cache.MAX_BLOCKS)
	# A new world invalidates old geometry even when it reuses the same coordinates.
	game.camera = Vector2(game.cursor)
	await frame()
	key = cache.key_for(game.cursor)
	count = cache.blocks[key].ground.rebuilds
	game.terrain.fill(0)
	for i in 2: await frame()
	assert(cache.blocks[key].ground.rebuilds>count)
	# Long previews draw the visible intersection, while construction retains its full route.
	var original_cursor: Vector2i = game.cursor
	for along_x in [false,true]:
		game.horizontal = along_x
		for pair in [[Vector2i(0,0),Vector2i(16383,16383)],[original_cursor-Vector2i(200,20),original_cursor+Vector2i(20,200)],[original_cursor+Vector2i(200,20),original_cursor-Vector2i(20,200)]]:
			game.anchor = pair[0]; game.cursor = pair[1]
			var visible = game.visuals.visible_preview_cells()
			assert(visible.size()<400)
			var half = Vector2(660,420)/game.tile
			var low = Vector2i((game.camera-half).floor())
			var high = Vector2i((game.camera+half).ceil())
			var expected: Dictionary = {}
			for cell in game.line_cells(game.anchor,game.cursor):
				if cell.x>=low.x and cell.x<=high.x and cell.y>=low.y and cell.y<=high.y: expected[cell] = true
			assert(visible.size()==expected.size())
			for cell in visible: assert(expected.has(cell))
	game.anchor = game.NO_CELL; game.cursor = original_cursor
	game.queue_redraw()
	await frame()
	root.get_texture().get_image().save_png("res://tests/render-cache.png")
	print("PASS: cached meshes reused during camera/zoom, riverbank and scenery edits, road occupancy and closure, city growth, bounded LRU and new terrain invalidation")
	game.free()
	quit()
