extends SceneTree
func _initialize() -> void: call_deferred("run")
func press(game, key: int, pad: bool = true) -> void:
	var event
	if pad:
		event = InputEventJoypadButton.new()
		event.button_index = key
	else:
		event = InputEventKey.new()
		event.physical_keycode = key
	event.pressed = true
	game._unhandled_input(event)
func run() -> void:
	var path = "res://tests/title_save.bin"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.save_path = path
	game.title_has_save = false
	assert(game.at_title and not game.session_active)
	assert(game.cities.is_empty() and game.terrain.chunks.is_empty(),"Opening the title doesn't generate the world")
	var random_state: int = game.rng.state
	game._process(200)
	assert(game.elapsed==0 and game.money==80000 and game.cities.is_empty() and game.rng.state==random_state)
	press(game,JOY_BUTTON_DPAD_DOWN)
	assert(game.title_index==2,"No save: disabled Load is skipped")
	press(game,JOY_BUTTON_DPAD_UP)
	assert(game.title_index==0)
	press(game,JOY_BUTTON_A)
	assert(not game.at_title and game.session_active and game.cities.size()==game.INITIAL_CITY_COUNT)
	assert(game.elapsed==0 and game.money==80000 and not FileAccess.file_exists(path))
	game.transact(-120,"construction","Prueba de guardado")
	game.save_game(false)
	game.free()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.save_path = path
	game.title_has_save = true
	assert(game.at_title and game.cities.is_empty())
	# Browsing and cancelling a new game never modifies the saved file.
	var bytes = FileAccess.get_file_as_bytes(path)
	press(game,KEY_ENTER,false)
	assert(game.title_confirm_new and not game.title_confirm_accept)
	press(game,JOY_BUTTON_B)
	assert(not game.title_confirm_new and FileAccess.get_file_as_bytes(path)==bytes)
	press(game,JOY_BUTTON_DPAD_DOWN)
	assert(game.title_index==1)
	press(game,JOY_BUTTON_A)
	assert(not game.at_title and game.session_active and game.money==79880)
	assert(game.cities.size()==game.INITIAL_CITY_COUNT and game.accounts.totals.construction==-120)
	game.free()
	# Confirmed new region resets progress, but doesn't immediately overwrite the save.
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.save_path = path
	game.title_has_save = true
	press(game,JOY_BUTTON_A)
	press(game,JOY_BUTTON_DPAD_LEFT)
	assert(game.title_confirm_accept)
	press(game,JOY_BUTTON_A)
	assert(not game.at_title and game.money==80000 and game.elapsed==0 and game.accounts.entries.is_empty())
	assert(FileAccess.get_file_as_bytes(path)==bytes)
	game.free()
	# An incompatible save leaves the player on the title with a useful message.
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_var({"version":0})
	file.close()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.save_path = path
	game.title_has_save = true
	press(game,KEY_F9,false)
	assert(game.at_title and not game.session_active and game.title_message.contains("incompatible"))
	game.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PASS: title at boot, paused/unallocated world, disabled Load, keyboard/gamepad navigation, new game confirmation, saved game load, safe cancellation, incompatible save feedback")
	quit()
