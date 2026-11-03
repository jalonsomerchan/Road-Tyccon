extends RefCounted
## Vistas y acciones compartidas por ratón, teclado y mando.
var g
var focus_index = 0
var actions: Array = []
var tab = 0
var pending_scenario = ""
var route_page = 0
var v

func _init(game) -> void:
	g=game

func cycle_mode() -> void:
	var modes = ["progression","free","budget","winter","network"]
	var current = g.selected_scenario if g.selected_mode=="scenario" else g.selected_mode
	var next: String = modes[(modes.find(current)+1)%modes.size()]
	g.selected_mode="scenario" if next in ["budget","winter","network"] else next
	if g.selected_mode=="scenario": g.selected_scenario=next

func mode_label() -> String:
	if g.selected_mode=="scenario":
		for item in g.gameplay.SCENARIOS:
			if item.id==g.selected_scenario: return item.name
	return "Progresión" if g.selected_mode=="progression" else "Libre · Todas las carreteras"

func starting_money() -> float:
	if g.selected_mode=="scenario":
		for item in g.gameplay.SCENARIOS:
			if item.id==g.selected_scenario: return item.money
	return g.WorldSettings.STARTING_MONEY

func cycle_overlay() -> void:
	var layers = ["none","traffic","condition","profit"]
	g.gameplay.overlay=layers[(layers.find(g.gameplay.overlay)+1)%layers.size()]

func move_focus(amount: int) -> void:
	if not actions.is_empty(): focus_index=posmod(focus_index+amount,actions.size())

func accept() -> void:
	if not actions.is_empty(): action(actions[clampi(focus_index,0,actions.size()-1)])

func action(value: String) -> void:
	var command = value.get_slice(":",1)
	match command:
		"claim": g.gameplay.claim(int(value.get_slice(":",2)))
		"tab": tab=int(value.get_slice(":",2)); focus_index=0
		"layer": g.gameplay.overlay=value.get_slice(":",2)
		"overlay": cycle_overlay()
		"segment": g.services.select_segment(g.cursor)
		"repair": g.services.repair(g.services.cells(),g.services.repair_mode=="partial")
		"repair_mode": g.services.repair_mode="closed" if g.services.repair_mode=="partial" else "partial"
		"auto": g.services.auto_enabled=not g.services.auto_enabled
		"threshold": g.services.auto_threshold=35 if g.services.auto_threshold>=75 else g.services.auto_threshold+20
		"reserve": g.services.reserve()
		"undo": g.services.undo_build()
		"detour": g.services.detour_armed=not g.services.detour_armed; g.close_panels(); g.select_tool(0); g.tell("El próximo tramo será un desvío temporal de 5 minutos" if g.services.detour_armed else "Desvío cancelado")
		"fire","snow": g.services.deploy(command,g.cursor)
		"weather":
			if g.inside(g.incidents.last_alert): g.travel_to(g.incidents.last_alert)
			else: g.tell("Todavía no hay fenómenos meteorológicos activos.")
		"alert":
			if g.inside(g.gameplay.alert_cell): g.travel_to(g.gameplay.alert_cell)
			else: g.tell("La red no tiene puntos problemáticos detectados.")
		"car": g.gameplay.select_car_at(g.cursor)
		"follow":
			var car = g.gameplay.inspected_car()
			if not car.is_empty(): g.travel_to(g.traffic.position(car))
		"route_page": route_page+=1
		"scenario":
			pending_scenario=value.get_slice(":",2)
		"cancel_scenario": pending_scenario=""
		"start":
			if pending_scenario.is_empty(): return
			g.selected_mode="scenario"
			g.selected_scenario=pending_scenario
			pending_scenario=""
			g.start_new_session()
		"continue":
			g.gameplay.scenario_id=""
			g.gameplay.scenario_done=false
			g.gameplay.mode="free"
			g.speed_index=1
			g.close_panels()

func button(area: Rect2, label: String, value: String) -> void:
	v.button(area,label,value,actions.size()==focus_index)
	actions.append(value)

func draw_panel(visuals) -> void:
	v=visuals
	actions.clear()
	match g.panel:
		"objectives": draw_objectives()
		"network": draw_network()
		"scenarios": draw_scenarios()
	focus_index=clampi(focus_index,-1,maxi(0,actions.size()-1))
	v.text(Vector2(160,683),"↑ ↓ / stick elegir · A / Enter activar · B / Esc volver · L3 / Espacio pausa",13,v.MUTED)

func draw_objectives() -> void:
	var gp = g.gameplay
	v.text(Vector2(160,175),"CONTRATOS · Recompensas y próximos objetivos",14,v.MUTED)
	for i in gp.contracts.size():
		var contract = gp.contracts[i]
		var value = mini(contract.goal,gp.contract_value(contract))
		var y = 190+i*112
		v.card(Rect2(160,y,958,100),Color("243c35"))
		v.text(Vector2(177,y+28),gp.contract_title(contract),20,v.PAPER)
		v.text(Vector2(177,y+53),"%d / %d · %s · +%d reputación"%[value,contract.goal,g.cash(contract.reward),contract.rep],14,v.MUTED)
		v.rect(Rect2(177,y+72,690,7),Color("132926"))
		v.rect(Rect2(177,y+72,690*float(value)/contract.goal,7),v.GREEN)
		button(Rect2(902,y+32,198,40),"Cobrar" if value>=contract.goal else "En marcha","play:claim:"+str(i))
	v.text(Vector2(160,559),"Reputación %d · Nivel %d / 3 · %s"%[gp.reputation,gp.tier,"Desbloqueos activos" if gp.mode=="progression" else "Catálogo completo"],18,v.GREEN)
	v.text(Vector2(160,587),"Niveles: 20 → vías secundarias · 80 → autovías · 180 → grandes autopistas",14,v.MUTED)
	if not gp.improvements.is_empty():
		var entry = gp.improvements[0]
		v.text(Vector2(160,622),"Última mejora: "+entry.label,16,v.PAPER)
		v.text(Vector2(160,646),"Demora %.0f → %.0f s · Cola %d → %d coches"%[entry.before.delay,entry.after.delay,entry.before.queue,entry.after.queue],14,v.GREEN)
	elif not gp.review.is_empty(): v.text(Vector2(160,634),"Evaluando tu intervención: se comparará tras 60 s y al menos 5 viajes.",15,v.MUTED)

func draw_network() -> void:
	for i in 3:
		var area = Rect2(160+i*322,156,310,36)
		v.button(area,["Tramos y mantenimiento","Tráfico y emergencias","Economía de la red"][i],"play:tab:"+str(i),i==tab)
		if actions.size()==focus_index: v.canvas.draw_rect(area.grow(2),v.PAPER,false,1)
		actions.append("play:tab:"+str(i))
	match tab:
		0: draw_services()
		1: draw_traffic()
		2: draw_economy()

func draw_services() -> void:
	var service = g.services
	var targets = service.cells()
	var condition = 0.0
	var reserve_count = 0
	for p in targets:
		condition+=g.roads[p].hp
		if g.roads[p].get("reserve",false): reserve_count+=1
	v.text(Vector2(160,230),"TRAMO DEL CURSOR · %d casillas"%targets.size(),21,v.GREEN)
	v.text(Vector2(160,260),"Conservación media %.1f %% · %d casillas en reserva"%[condition/maxi(1,targets.size()),reserve_count],15,v.MUTED)
	button(Rect2(160,286,454,40),"Seleccionar hasta los cruces","play:segment")
	button(Rect2(638,286,480,40),"Reserva: activar / retirar (+35 % coste)","play:reserve")
	button(Rect2(160,340,454,40),"Reparación: "+("parcial · tráfico al 50 %" if service.repair_mode=="partial" else "cierre · reapertura automática"),"play:repair_mode")
	button(Rect2(638,340,480,40),"Reparar tramo · "+g.cash(service.quote(targets,service.repair_mode=="partial")),"play:repair")
	button(Rect2(160,394,454,40),"Mantenimiento automático: "+("SÍ" if service.auto_enabled else "NO"),"play:auto")
	button(Rect2(638,394,480,40),"Intervenir por debajo del %d %%"%service.auto_threshold,"play:threshold")
	button(Rect2(160,448,454,40),"Construir desvío temporal · 5 min","play:detour")
	button(Rect2(638,448,480,40),"Deshacer última construcción"+(" · disponible" if service.can_undo() else " · sin uso pendiente"),"play:undo")
	v.text(Vector2(160,528),"La reparación parcial cuesta 1,5× y tarda el doble; mantiene circulación reducida.",15,v.MUTED)
	v.text(Vector2(160,558),"Los desvíos se retiran al vencer su plazo y quedar vacíos. Las reservas no desaparecen.",15,v.MUTED)
	v.text(Vector2(160,593),"%d obras activas · %d desvíos · Conservación estimada: %s / min"%[service.service_jobs.size(),service.detours.size(),g.cash(g.gameplay.upkeep_per_minute())],16,v.GREEN)
	v.text(Vector2(160,628),"Ctrl+Z deshace durante 60 s y antes del primer coche. El reembolso queda registrado.",14,v.MUTED)

func draw_traffic() -> void:
	var gp = g.gameplay
	var layer_names = {"none":"Sin capa","traffic":"Congestión","condition":"Conservación","profit":"Rentabilidad"}
	var i = 0
	for layer in layer_names:
		button(Rect2(160+i*241,208,231,36),layer_names[layer],"play:layer:"+layer)
		i+=1
	v.text(Vector2(160,278),gp.alert_text.substr(0,91),16,v.GREEN)
	button(Rect2(160,297,300,36),"Ir al punto del diagnóstico","play:alert")
	var eta = maxf(0,g.incidents.rules.weather_interval-g.incidents.weather_clock)
	v.text(Vector2(160,371),("PREVISIÓN · %s en %.0f s"%["Nieve" if gp.weather_kind()=="snow" else "Incendio",eta]) if g.incidents.rules.weather_enabled else "PREVISIÓN · Clima desactivado",19,v.GREEN)
	button(Rect2(160,393,300,38),"Bomberos · 250 € · radio 12","play:fire")
	button(Rect2(475,393,310,38),"Quitanieves · 180 € · radio 12","play:snow")
	button(Rect2(800,393,318,38),"Ir a última alerta","play:weather")
	button(Rect2(160,460,454,38),"Inspeccionar / siguiente coche · C","play:car")
	button(Rect2(638,460,480,38),"Ir al vehículo seleccionado","play:follow")
	var car = gp.inspected_car()
	if car.is_empty():
		v.text(Vector2(160,541),"Selecciona un coche con C o Ctrl+clic sobre una carretera.",17,v.PAPER)
	else:
		v.text(Vector2(160,537),"#%d · %s → %s"%[car.ticket,g.cities[car.origin].name,g.cities[car.dest].name],19,v.PAPER)
		v.text(Vector2(160,567),gp.car_reason(car),16,v.GREEN)
		v.text(Vector2(160,596),"Tiempo %.0f s · Referencia %.0f s · %s"%[car.age,car.ideal,gp.PROFILES[gp.profile(g.cities[car.origin])]],15,v.MUTED)
	v.text(Vector2(160,640),"L alterna capas · Verde: situación favorable · Rojo: congestión, desgaste o pérdidas",14,v.MUTED)

func draw_economy() -> void:
	var gp = g.gameplay
	var upkeep = gp.upkeep_per_minute()
	var income = gp.income_per_minute()
	v.text(Vector2(160,234),"CONSERVACIÓN / MIN",13,v.MUTED)
	v.text(Vector2(160,272),g.cash(upkeep),27,v.GREEN)
	v.text(Vector2(488,234),"INGRESO RECIENTE / MIN",13,v.MUTED)
	v.text(Vector2(488,272),g.cash(income),27,v.GREEN)
	v.text(Vector2(818,234),"CAJA ESTIMADA EN 5 MIN",13,v.MUTED)
	v.text(Vector2(818,272),g.cash(g.money+(income-upkeep)*5),27,v.GREEN)
	v.text(Vector2(160,308),"Previsión sin nuevas obras, reparaciones ni accidentes; ingresos de minutos completos.",14,v.MUTED)
	v.text(Vector2(160,355),"CONEXIÓN                      VIAJES       INGRESO/MIN       CONSERV./MIN       MARGEN/MIN",13,v.MUTED)
	var keys = gp.routes.keys()
	keys.sort_custom(func(a,b): return gp.routes[a].income>gp.routes[b].income)
	var page_count = maxi(1,ceili(keys.size()/5.0))
	route_page=posmod(route_page,page_count)
	for row in range(route_page*5,mini(keys.size(),route_page*5+5)):
		var key: Vector2i = keys[row]
		if key.x>=g.cities.size() or key.y>=g.cities.size(): continue
		var report = gp.route_report(key)
		var y = 393+(row%5)*43
		v.text(Vector2(160,y),(g.cities[key.x].name+" → "+g.cities[key.y].name).substr(0,27),14,v.PAPER)
		v.text(Vector2(459,y),str(report.trips),14,v.PAPER)
		v.text(Vector2(568,y),g.cash(report.income),14,v.GREEN)
		v.text(Vector2(758,y),g.cash(report.upkeep),14,v.PAPER)
		v.text(Vector2(955,y),g.cash(report.net),14,v.GREEN if report.net>=0 else Color("efac95"))
	if keys.is_empty(): v.text(Vector2(160,411),"Completa viajes para comparar conexiones.",17,v.PAPER)
	button(Rect2(160,604,290,36),"Siguiente página · %d / %d"%[route_page+1,page_count],"play:route_page")
	v.text(Vector2(470,627),"Coste completo de cada ruta; las vías compartidas no se suman.",13,v.MUTED)

func draw_scenarios() -> void:
	var gp = g.gameplay
	if gp.scenario_done:
		var result = gp.scenario_result
		v.text(Vector2(160,179),("RETO SUPERADO" if result.success else "TIEMPO TERMINADO")+" · %d puntos"%result.score,21,v.GREEN)
		v.text(Vector2(160,205),"%d viajes · %d ciudades conectadas · %s%s"%[result.trips,result.connected,g.cash(result.money)," · Sin récord por usar trucos" if not result.ranked else ""],14,v.MUTED)
	elif not gp.scenario_id.is_empty():
		v.text(Vector2(160,188),"Reto activo: %s · %.0f s restantes"%[gp.scenario().name,maxf(0,gp.scenario().duration-g.elapsed)],18,v.GREEN)
	else: v.text(Vector2(160,188),"SEMILLAS FIJAS · 15–30 minutos · Récords guardados en este equipo",16,v.MUTED)
	for i in gp.SCENARIOS.size():
		var definition = gp.SCENARIOS[i]
		var y = 226+i*100
		v.card(Rect2(160,y,958,88),Color("243c35"))
		v.text(Vector2(178,y+27),definition.name,20,v.PAPER)
		v.text(Vector2(178,y+53),definition.description,14,v.MUTED)
		v.text(Vector2(178,y+74),"Semilla %d · %s iniciales · Récord local %d"%[definition.seed,g.cash(definition.money),int(gp.scores.get(definition.id,{}).get("score",0))],12,v.GREEN)
		button(Rect2(910,y+25,190,38),"Preparar reto","play:scenario:"+definition.id)
	if not pending_scenario.is_empty():
		v.text(Vector2(160,559),"Se creará una región nueva; el próximo guardado reemplazará la partida actual.",14,Color("efac95"))
		button(Rect2(160,578,454,40),"Iniciar el reto seleccionado","play:start")
		button(Rect2(638,578,480,40),"Cancelar","play:cancel_scenario")
	elif gp.scenario_done: button(Rect2(160,578,454,40),"Seguir esta región en modo libre","play:continue")
	else: v.text(Vector2(160,578),"Completa el objetivo y termina con caja positiva. Los trucos desactivan el récord.",15,v.MUTED)

func draw_world(visuals) -> void:
	var gp = g.gameplay
	var colors = [Color("80c98c",0.55),Color("efb25e",0.6),Color("e86255",0.65)]
	if gp.overlay!="none":
		for p in g.roads:
			var at = g.screen(Vector2(p))
			if not Rect2(-g.tile,60,1280+g.tile*2,630).has_point(at): continue
			var ratio = 0.0
			match gp.overlay:
				"traffic": ratio=float(g.density.get(p,0))/maxi(1,g.traffic.capacity(p))
				"condition": ratio=1-g.roads[p].hp/100.0
				"profit":
					var cost = g.Catalog.ROADS[g.roads[p].kind].cost*0.0008
					if not gp.is_player_road(p): continue
					var revenue = float(gp.road_income.get(p,0.0))/maxf(1,g.elapsed/60.0)
					ratio=clampf(1-revenue/maxf(0.01,cost),0,1)
			visuals.rect(Rect2(at-Vector2.ONE*g.tile*0.5,Vector2.ONE*g.tile),colors[2 if ratio>0.75 else (1 if ratio>0.4 else 0)])
	for p in g.services.selected:
		var at = g.screen(Vector2(p))
		if Rect2(0,84,1280,604).has_point(at): visuals.canvas.draw_rect(Rect2(at-Vector2.ONE*g.tile*0.45,Vector2.ONE*g.tile*0.9),Color("97dbea"),false,2)
	var car = gp.inspected_car()
	if not car.is_empty():
		for i in range(car.step,car.path.size()-1):
			var a = g.screen(car.path[i])
			var b = g.screen(car.path[i+1])
			if Rect2(0,84,1280,604).has_point(a) and Rect2(0,84,1280,604).has_point(b): visuals.canvas.draw_line(a,b,Color("96dcf0"),3)

func draw_hud(visuals) -> void:
	var gp = g.gameplay
	var metric = gp.metrics()
	visuals.text(Vector2(260,24),"%s · Nivel %d · %d reputación"%[{"free":"Libre","progression":"Progresión","scenario":"Reto"}.get(gp.mode,"Libre"),gp.tier,gp.reputation],13,visuals.MUTED)
	visuals.text(Vector2(260,46),"Demora %.0f s · Conservación %s/min"%[metric.delay,g.cash(gp.upkeep_per_minute())],14,visuals.PAPER)
	visuals.icon_button(Rect2(680,12,178,36),"Objetivos · K","objectives","goals",g.panel=="objectives")
	if g.panel!="": return
	visuals.icon_button(Rect2(20,116,350,30),"Red y servicios · C inspeccionar","network","network")
	if not gp.scenario_id.is_empty():
		visuals.text(Vector2(386,138),"%s · %.0f s"%[gp.scenario().name,maxf(0,gp.scenario().duration-g.elapsed)],15,visuals.GREEN)
	if gp.overlay!="none":
		visuals.text(Vector2(22,175),"Capa: "+{"traffic":"Congestión","condition":"Conservación","profit":"Rentabilidad estimada"}.get(gp.overlay,"")+" · L cambiar",14,visuals.PAPER)
	if gp.celebration_left>0:
		visuals.card(Rect2(250,622,780,50),Color("243e34"))
		visuals.text(Vector2(267,654),gp.celebration,18,visuals.GREEN)
