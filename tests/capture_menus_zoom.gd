extends SceneTree
var g
func _initialize() -> void: call_deferred("run")
func shot(name: String, frames: int = 3) -> void:
	for i in frames:
		g.queue_redraw();await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/review-"+name+".png")
func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false)
	root.size=Vector2i(1280,800);g.last_pad=true
	g.menu_focus.sync("title:new");await shot("title")
	g.start_new_session();g.speed_index=0;g.incidents.rules.weather_enabled=false
	g.open_menu();g.menu_focus.pick("help");await shot("menu-footer")
	for panel in ["catalog","cities","accounts","objectives","scenarios","info","help","infrastructure"]:
		g.close_panels();g.open_panel(panel);await shot(panel)
	for tab in 3:
		g.close_panels();g.gameplay_ui.tab=tab;g.open_panel("network")
		await shot("network-"+str(tab))
	g.close_panels();g.roads[g.cursor]=g.city_road(3,true);g.install_signal();g.menu_focus.sync();await shot("signal")
	g.close_panels()
	for zoom in [8.0,2.0,0.5]:
		g.tile=zoom;g.set_zoom(zoom)
		await shot("zoom-"+str(zoom),12)
		if zoom<8:
			assert(g.visuals.overview.texture!=null and not g.visuals.terrain_cache.ground_root.visible)
			assert(g.visuals.overview.labels.size()<=32)
			var count: int = g.visuals.overview.builds
			await shot("zoom-stable-"+str(zoom),3)
			assert(g.visuals.overview.builds==count,"Stable regional frames reuse their terrain texture")
	g.tile=32;g.set_zoom(32);await shot("zoom-detail",3)
	assert(g.visuals.terrain_cache.ground_root.visible and g.terrain.chunks.size()<=g.World.MAX_CACHED_CHUNKS)
	print("PASS: title, all panels, visible footer focus, three network tabs, signal controls, regional zoom 2/0.5, stable texture reuse, bounded labels/terrain cache and return to detail rendered")
	g.free();quit()
