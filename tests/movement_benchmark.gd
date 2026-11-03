extends SceneTree
## Ejecutar con una sesión gráfica y -- --test-mode; --warm carga primero toda la zona.
var g
func _initialize() -> void: call_deferred("run")
func report(label:String,values:Array) -> void:
	values.sort()
	print("%s: mediana %.2f ms · p95 %.2f ms · máximo %.2f ms"%[label,values[values.size()/2],values[int(values.size()*.95)],values.back()])
func run() -> void:
	g=load("res://scenes/main.tscn").instantiate();root.add_child(g);g.set_process(false)
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	g.tile=.5;g.zoom_target=.5;g.notice_time=0;g.incidents.rules.weather_enabled=false
	if "--warm" in OS.get_cmdline_user_args():
		g.explore_around(Vector2(g.cursor),true)
		g.explore_around(Vector2(g.cursor+Vector2i(480,0)),true);g.rebuild_graph()
		while not g.world_stream.jobs.is_empty(): g.world_stream.update(20000)
		for i in 100:
			g._process(1.0/60);await process_frame;RenderingServer.force_draw(false)
	var cpu:Array=[];var frames:Array=[]
	for i in 150:
		if i%5==0: g.cursor.x+=16
		var begin=Time.get_ticks_usec();g._process(1.0/60)
		cpu.append((Time.get_ticks_usec()-begin)/1000.0)
		await process_frame;RenderingServer.force_draw(false)
		frames.append((Time.get_ticks_usec()-begin)/1000.0)
	report("Simulación",cpu);report("Fotograma",frames)
	print("Ciudades %d · Carreteras %d · Coches %d · Mosaicos %d/%d · Regiones pendientes %d"%[g.cities.size(),g.roads.size(),g.cars.size(),g.visuals.overview.tiles.size(),g.visuals.overview.MAX_TILES,g.world_stream.jobs.size()])
	print("PASS: movimiento con simulación activa, zoom mínimo y descubrimiento progresivo medidos")
	g.free();quit()
