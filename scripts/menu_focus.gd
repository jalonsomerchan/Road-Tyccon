extends RefCounted
## El foco existe antes del dibujo y abarca todas las acciones visibles de cada menú.
var g
var current = ""
var context = ""
var items: Array = []

func _init(game) -> void: g=game
func entry(action: String, area: Rect2, enabled: bool = true) -> Dictionary:
	return {"action":action,"rect":area,"enabled":enabled}

func model() -> Array:
	var result: Array = []
	if g.at_title:
		if g.title_confirm_new:
			return [entry("title_confirm",Rect2(334,426,290,52)),entry("title_cancel",Rect2(642,426,302,52))]
		return [entry("title:new",Rect2(66,520,316,44)),entry("title:load",Rect2(66,575,316,44),g.title_has_save),entry("title:quit",Rect2(66,630,316,44)),entry("play:mode",Rect2(66,286,400,40))]
	match g.panel:
		"menu":
			for i in g.MENU_ACTIONS.size(): result.append(entry(g.MENU_ACTIONS[i],Rect2(166+i%2*486,164+int(i/2)*104,462,92)))
			for i in 4: result.append(entry(["save","load","help","speed"][i],Rect2(166+i*194,592,180,40),i!=1 or FileAccess.file_exists(g.save_path)))
			result.append(entry("event:open",Rect2(942,592,180,40)))
		"notices": result=g.event_notices.model()
		"catalog": result=g.construction_catalog.model()
		"cities":
			var start=int(g.city_list_index/6)*6
			for i in range(start,mini(start+6,g.cities.size())):
				result.append(entry("city_select:"+str(i),Rect2(160,187+(i-start)*67,830,61)))
				result.append(entry("city_go:"+str(i),Rect2(1003,197+(i-start)*67,100,39)))
			result.append(entry("cities_prev",Rect2(160,608,166,38),start>0))
			result.append(entry("cities_next",Rect2(340,608,166,38),start+6<g.cities.size()))
		"map": return [] # Stick y cruceta desplazan el destino; A viaja.
		"accounts":
			result=[entry("account_filter",Rect2(548,264,570,34)),entry("account_prev",Rect2(548,602,172,36)),entry("account_next",Rect2(732,602,172,36))]
		"objectives":
			for i in 3: result.append(entry("play:claim:"+str(i),Rect2(902,222+i*112,198,40)))
		"network":
			for i in 3: result.append(entry("play:tab:"+str(i),Rect2(160+i*322,156,310,36)))
			match g.gameplay_ui.tab:
				0:
					var names=["segment","reserve","repair_mode","repair","auto","threshold","detour","undo"]
					for i in names.size(): result.append(entry("play:"+names[i],Rect2(160+i%2*478,286+int(i/2)*54,454 if i%2==0 else 480,40)))
				1:
					for i in 4: result.append(entry("play:layer:"+["none","traffic","condition","profit"][i],Rect2(160+i*241,208,231,36)))
					result.append(entry("play:alert",Rect2(160,297,300,36)))
					for i in 3: result.append(entry("play:"+["fire","snow","weather"][i],Rect2([160,475,800][i],393,[300,310,318][i],38)))
					result.append(entry("play:car",Rect2(160,460,454,38)))
					result.append(entry("play:follow",Rect2(638,460,480,38)))
				2: result.append(entry("play:route_page",Rect2(160,604,290,36)))
		"scenarios":
			if not g.gameplay_ui.pending_scenario.is_empty():
				result=[entry("play:start",Rect2(160,578,454,40)),entry("play:cancel_scenario",Rect2(638,578,480,40))]
			else:
				for i in 3: result.append(entry("play:scenario:"+g.gameplay.SCENARIOS[i].id,Rect2(910,251+i*100,190,38)))
				if g.gameplay.scenario_done: result.append(entry("play:continue",Rect2(160,578,454,40)))
		"signal":
			for i in 3: result.append(entry("signal:"+["ns+","ew+","toggle"][i],Rect2(224,195+i*92,680,60)))
		"infrastructure":
			for i in 3: result.append(entry("mode:"+["road","roundabout","signal"][i],Rect2(200,190+i*92,880,64)))
		"info": result.append(entry("map",Rect2(166,606,264,44)))
	if not g.panel.is_empty(): result.append(entry("close",Rect2(1015,105,110,36)))
	return result

func key() -> String:
	if g.at_title: return "confirm" if g.title_confirm_new else "title"
	if g.panel=="catalog": return "catalog:%d:%d"%[g.construction_catalog.tab,g.construction_catalog.page]
	return g.panel+":"+str(g.gameplay_ui.tab if g.panel=="network" else (int(g.city_list_index/6) if g.panel=="cities" else ""))+":"+g.gameplay_ui.pending_scenario

func sync(preferred: String = "") -> void:
	var next_context=key()
	var changed=next_context!=context
	context=next_context
	items=model()
	if changed or not preferred.is_empty():
		current=preferred
		if current.is_empty():
			if context=="confirm": current="title_cancel"
			elif context=="title": current="title:"+["new","load","quit"][clampi(g.title_index,0,2)]
			elif g.panel=="menu": current=g.MENU_ACTIONS[clampi(g.menu_index,0,g.MENU_ACTIONS.size()-1)]
			elif g.panel=="catalog": current=g.construction_catalog.selected_action()
			elif g.panel=="cities": current="city_select:"+str(g.city_list_index)
			elif g.panel=="network": current="play:tab:"+str(g.gameplay_ui.tab)
			elif g.panel=="scenarios" and not g.gameplay_ui.pending_scenario.is_empty(): current="play:cancel_scenario"
	for item in items:
		if item.action==current and item.enabled: mirror();return
	current=""
	for item in items:
		if item.enabled: current=item.action;break
	mirror()

func mirror() -> void:
	if g.at_title:
		if g.title_confirm_new: g.title_confirm_accept=current=="title_confirm"
		elif current.begins_with("title:"): g.title_index=["new","load","quit"].find(current.get_slice(":",1))
		else: g.title_index=-1
	elif g.panel=="menu": g.menu_index=g.MENU_ACTIONS.find(current)
	elif g.panel=="catalog" and current.begins_with("catalog:item:"): g.construction_catalog.preview(current.trim_prefix("catalog:item:"))
	elif g.panel=="cities" and current.begins_with("city_"): g.city_list_index=int(current.get_slice(":",1))
	elif g.panel=="signal" and current.begins_with("signal:"): g.signal_index=["ns+","ew+","toggle"].find(current.get_slice(":",1))
	elif g.panel=="infrastructure" and current.begins_with("mode:"): g.infrastructure_index=["road","roundabout","signal"].find(current.get_slice(":",1))
	g.gameplay_ui.focus_index=-1
	var count=0
	for item in items:
		if item.action==current and item.action.begins_with("play:"): g.gameplay_ui.focus_index=count;break
		if item.action.begins_with("play:"): count+=1

func pick(action: String) -> void: sync(action)

func navigate(direction: Vector2i) -> void:
	sync()
	if items.is_empty(): return
	if g.panel=="signal" and direction.x!=0 and current.begins_with("signal:"):
		if current=="signal:toggle": g.incidents.signals[g.cursor].enabled=direction.x>0;g.graph_dirty=true
		else: g.adjust_signal(direction.x)
		return
	var from: Dictionary = {}
	for item in items:
		if item.action==current: from=item;break
	if from.is_empty(): return
	var center: Vector2=from.rect.get_center()
	var best=current
	var score=INF
	for item in items:
		if not item.enabled or item.action==current: continue
		var delta: Vector2=item.rect.get_center()-center
		var ahead=delta.dot(Vector2(direction))
		if ahead<=4: continue
		var across=absf(delta.y if direction.x!=0 else delta.x)
		var overlaps = (from.rect.position.y<item.rect.end.y and item.rect.position.y<from.rect.end.y) if direction.x!=0 else (from.rect.position.x<item.rect.end.x and item.rect.position.x<from.rect.end.x)
		if not overlaps and items.size()>2: continue
		var candidate=ahead+across*2+(0 if overlaps else 10000)
		if candidate<score: score=candidate;best=item.action
	current=best;mirror()

func activate() -> void:
	sync()
	if current.is_empty(): return
	var chosen=current
	if g.at_title: g.title_action(chosen)
	elif g.panel=="catalog" and chosen.begins_with("catalog:item:"): g.construction_catalog.confirm(chosen.trim_prefix("catalog:item:"))
	elif chosen.begins_with("city_select:"): g.travel_city(int(chosen.get_slice(":",1)))
	elif g.panel=="infrastructure" and chosen.begins_with("mode:"):
		g.ui_action(chosen);g.select_tool(0)
	else: g.ui_action(chosen)
	sync()

func focused(action: String, area: Rect2) -> bool:
	if (not g.last_pad and g.panel!="notices") or current!=action or context!=key(): return false
	for item in items:
		if item.action==current: return item.rect.intersects(area)
	return false

func available(action: String) -> bool:
	if action=="load": return FileAccess.file_exists(g.save_path)
	if context!=key(): return true
	for item in items:
		if item.action==action: return item.enabled
	return true
