extends RefCounted
## Una sola vía de entrada: pulsaciones por flanco, zona muerta y repetición controlada.
const PRESS_ZONE = 0.65
const RELEASE_ZONE = 0.38
const FIRST_REPEAT = 0.32
const REPEAT = 0.14
var g
var active_device = -1
var axes: Dictionary = {}
var held: Dictionary = {}
var stick = Vector2i.ZERO
var navigation = Vector2i.ZERO
var repeat_left = FIRST_REPEAT
var last_context = ""
var last_face = -1
var face_time = -1000000
var muted_keys: Dictionary = {}

func _init(game) -> void: g=game

func choose_device(device: int) -> void:
	if device==active_device: return
	active_device=device;axes.clear();held.clear();stick=Vector2i.ZERO;navigation=Vector2i.ZERO

func digit(value: float, previous: int) -> int:
	if absf(value)>=PRESS_ZONE: return int(sign(value))
	return previous if absf(value)>RELEASE_ZONE else 0

func direction() -> Vector2i:
	var x=stick.x
	var y=stick.y
	if held.get(JOY_BUTTON_DPAD_LEFT,false): x=-1
	if held.get(JOY_BUTTON_DPAD_RIGHT,false): x=1
	if held.get(JOY_BUTTON_DPAD_UP,false): y=-1
	if held.get(JOY_BUTTON_DPAD_DOWN,false): y=1
	# Una sola dirección por paso; no saltar por una diagonal o por dos ejes simultáneos.
	if x!=0 and y!=0:
		if absf(float(axes.get(JOY_AXIS_LEFT_Y,0)))>=absf(float(axes.get(JOY_AXIS_LEFT_X,0))): x=0
		else: y=0
	return Vector2i(x,y)

func menu_context() -> bool: return g.at_title or not g.panel.is_empty() or g.cheats.is_open()

func move_once(value: Vector2i) -> void:
	if g.cheats.is_open(): g.cheats.move_selection(value.x+value.y*2)
	elif g.panel=="map" and not g.at_title: pass # El desplazamiento del mapa es continuo.
	elif menu_context(): g.menu_focus.navigate(value)

func refresh_direction() -> void:
	var next=direction()
	if next==navigation: return
	navigation=next;repeat_left=FIRST_REPEAT
	if next!=Vector2i.ZERO: move_once(next)

func handle(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		if active_device>=0 and active_device!=event.device: return true
		if active_device<0 and absf(event.axis_value)<(0.12 if event.axis in [JOY_AXIS_TRIGGER_LEFT,JOY_AXIS_TRIGGER_RIGHT] else PRESS_ZONE): return true
		choose_device(event.device)
		axes[event.axis]=event.axis_value
		if absf(event.axis_value)>PRESS_ZONE: g.last_pad=true;g.hover_cell=g.NO_CELL
		if event.axis==JOY_AXIS_LEFT_X: stick.x=digit(event.axis_value,stick.x)
		elif event.axis==JOY_AXIS_LEFT_Y: stick.y=digit(event.axis_value,stick.y)
		refresh_direction()
		return true
	if not event is InputEventJoypadButton: return false
	if not event.pressed:
		if event.device==active_device:
			held.erase(event.button_index)
			last_face=event.button_index;face_time=Time.get_ticks_msec()
			refresh_direction()
		return true
	choose_device(event.device)
	if held.get(event.button_index,false): return true
	held[event.button_index]=true
	last_face=event.button_index
	face_time=Time.get_ticks_msec()
	g.last_pad=true;g.hover_cell=g.NO_CELL
	if event.button_index in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT]:
		refresh_direction();return true
	button(event.button_index)
	return true

func button(index: int) -> void:
	if g.cheats.is_open(): g.cheats.pad_button(index);return
	if g.at_title:
		match index:
			JOY_BUTTON_A: g.menu_focus.activate()
			JOY_BUTTON_B:
				if g.title_confirm_new: g.title_confirm_new=false;g.menu_focus.sync("title:new")
			JOY_BUTTON_X: if not g.title_confirm_new: g.gameplay_ui.cycle_mode()
		return
	if index in [JOY_BUTTON_A,JOY_BUTTON_B] and not g.event_notices.pending.is_empty():
		g.event_notices.respond(g.event_notices.pending[0].id,index==JOY_BUTTON_A);return
	match index:
		JOY_BUTTON_START: g.toggle_menu()
		JOY_BUTTON_BACK: g.toggle_map()
		JOY_BUTTON_B: g.cancel_or_back()
		JOY_BUTTON_LEFT_STICK: g.toggle_pause()
		JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER:
			var delta=-1 if index==JOY_BUTTON_LEFT_SHOULDER else 1
			if g.panel.is_empty(): g.cycle_world_tool(delta)
			else: g.panel_bumper(delta);g.menu_focus.sync()
		JOY_BUTTON_A:
			if g.panel=="map": g.travel_to(g.navigator.target)
			elif not g.panel.is_empty(): g.menu_focus.activate()
			else: g.apply_action()
		JOY_BUTTON_Y:
			if g.panel.is_empty(): g.open_road_selector()
			else: g.panel_secondary(true)
		JOY_BUTTON_X:
			if not g.panel.is_empty(): g.panel_secondary(false)
			elif g.TOOLS[g.tool].id=="build_road": g.horizontal=not g.horizontal
			elif g.TOOLS[g.tool].id=="repair_route": g.upgrade_current()
		JOY_BUTTON_RIGHT_STICK: if g.panel.is_empty(): g.focus_next_city()

func update(delta: float) -> void:
	var context="cheats" if g.cheats.is_open() else g.menu_focus.key()
	if context!=last_context: repeat_left=FIRST_REPEAT;last_context=context
	if active_device>=0 and not g.test_mode and not Input.is_joy_known(active_device) and not active_device in Input.get_connected_joypads():
		axes.clear();held.clear();stick=Vector2i.ZERO;navigation=Vector2i.ZERO;active_device=-1
	if navigation!=Vector2i.ZERO and menu_context():
		repeat_left-=delta
		if repeat_left<=0: move_once(navigation);repeat_left=REPEAT
	if not g.at_title and not g.cheats.is_open() and g.panel in ["","map"]:
		var zoom=clampf(float(axes.get(JOY_AXIS_TRIGGER_RIGHT,0)),0,1)-clampf(float(axes.get(JOY_AXIS_TRIGGER_LEFT,0)),0,1)
		if absf(zoom)>0.12: g.zoom_control(exp(zoom*delta*1.4))

func keyboard_down(code: int) -> bool:
	return Input.is_physical_key_pressed(code) and not muted_keys.has(code)

func duplicate_alias(event: InputEvent) -> bool:
	var code=0
	if event is InputEventKey:
		code=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if not event.pressed: muted_keys.erase(code);return false
	if not g.last_pad: return false
	var candidates: Array = []
	var duplicate=false
	if event is InputEventKey:
		if code in [KEY_ENTER,KEY_KP_ENTER,KEY_E]: candidates=[JOY_BUTTON_A]
		elif code==KEY_ESCAPE: candidates=[JOY_BUTTON_B,JOY_BUTTON_START,JOY_BUTTON_BACK]
		elif code==KEY_B: candidates=[JOY_BUTTON_B]
		elif code in [KEY_F10,KEY_6]: candidates=[JOY_BUTTON_START]
		elif code in [KEY_X,KEY_R]: candidates=[JOY_BUTTON_X]
		elif code in [KEY_Y,KEY_V]: candidates=[JOY_BUTTON_Y]
		elif code==KEY_Q: candidates=[JOY_BUTTON_LEFT_SHOULDER]
		elif code==KEY_TAB: candidates=[JOY_BUTTON_RIGHT_SHOULDER,JOY_BUTTON_BACK]
		elif code==KEY_M: candidates=[JOY_BUTTON_BACK]
		elif code==KEY_G: candidates=[JOY_BUTTON_RIGHT_STICK]
		elif code==KEY_SPACE: candidates=[JOY_BUTTON_A,JOY_BUTTON_LEFT_STICK]
		elif code in [KEY_UP,KEY_W]: candidates=[JOY_BUTTON_DPAD_UP];duplicate=stick.y<0
		elif code in [KEY_DOWN,KEY_S]: candidates=[JOY_BUTTON_DPAD_DOWN];duplicate=stick.y>0
		elif code in [KEY_LEFT,KEY_A]: candidates=[JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_A];duplicate=stick.x<0
		elif code in [KEY_RIGHT,KEY_D]: candidates=[JOY_BUTTON_DPAD_RIGHT];duplicate=stick.x>0
		elif code in [KEY_MINUS,KEY_KP_SUBTRACT,KEY_PAGEDOWN]: duplicate=float(axes.get(JOY_AXIS_TRIGGER_LEFT,0))>.12
		elif code in [KEY_PLUS,KEY_EQUAL,KEY_KP_ADD,KEY_PAGEUP]: duplicate=float(axes.get(JOY_AXIS_TRIGGER_RIGHT,0))>.12
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_LEFT: candidates=[JOY_BUTTON_A]
		elif event.button_index==MOUSE_BUTTON_RIGHT: candidates=[JOY_BUTTON_B]
		elif event.button_index==MOUSE_BUTTON_WHEEL_UP: duplicate=float(axes.get(JOY_AXIS_TRIGGER_RIGHT,0))>.12
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN: duplicate=float(axes.get(JOY_AXIS_TRIGGER_LEFT,0))>.12
	for face in candidates:
		if held.get(face,false) or (last_face==face and Time.get_ticks_msec()-face_time<150): duplicate=true;break
	if duplicate and event is InputEventKey: muted_keys[code]=true
	return duplicate
