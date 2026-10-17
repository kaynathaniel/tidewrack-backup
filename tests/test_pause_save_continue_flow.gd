extends SceneTree
## Headless integration test for the real player flow:
##   game.tscn → read the logbook → Esc (pause) → [Save] → [Main Menu]
##   → main_menu.tscn → [Continue] → game.tscn, journal + flags restored.
##
## Drives the actual scenes and presses the actual buttons (found by their
## label text) rather than calling GameState directly, so it catches wiring
## between game.gd, main_menu.gd, GameState and Journal.
##
## Run from the project root:
##   godot --headless --path . -s res://tests/test_pause_save_continue_flow.gd
## Exit code 0 = passed. Deletes the real user:// save (see
## test_journal_persistence.gd for the CI note).

const GAME := "res://scenes/game.tscn"
const MENU := "res://scenes/main_menu.tscn"
const DIALOGUE := "res://data/dialogue/keeper_intro.json"

var _failures := 0
var _checks := 0
var _gs: Node
var _jr: Node
var _dm: Node


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_gs = root.get_node("GameState")
	_jr = root.get_node("Journal")
	_dm = root.get_node("DialogueManager")
	_gs.delete_save()
	_gs.flags.clear()
	_jr.clear()

	await _flow_save_then_continue_restores_journal_and_flags()
	await _flow_new_game_after_continue_starts_clean()

	_gs.delete_save()
	print("\n%d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


# --- helpers ------------------------------------------------------------------

func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("  assertion failed: " + msg)


func _settle(frames: int = 3) -> void:
	for i in frames:
		await process_frame


func _goto_scene(path: String) -> Node:
	change_scene_to_file(path)
	await _settle()
	_ok(current_scene != null and current_scene.scene_file_path == path, "scene is %s" % path)
	return current_scene


## Depth-first search for a Button whose text starts with `label`.
func _find_button(from: Node, label: String) -> Button:
	if from is Button and (from as Button).text.begins_with(label):
		return from
	for child in from.get_children():
		var found := _find_button(child, label)
		if found != null:
			return found
	return null


func _press(from: Node, label: String) -> Button:
	var button := _find_button(from, label)
	_ok(button != null, "button '%s' exists" % label)
	if button != null:
		_ok(not button.disabled, "button '%s' is enabled" % label)
		button.pressed.emit()
	await _settle()
	return button


func _read_save() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_gs.SAVE_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Play the logbook graph through DialogueManager exactly as an Interactable
## would, choosing `believer` then `trusted_edith=true`.
func _read_logbook() -> void:
	_ok(_dm.start(DIALOGUE, "logbook"), "logbook dialogue starts")
	_dm.advance()  # logbook -> logbook_2
	_dm.advance()  # logbook_2 -> logbook_choice1
	_dm.choose(1)  # believer -> logbook_believer
	_dm.advance()  # logbook_believer -> logbook_merge
	_dm.advance()  # logbook_merge -> logbook_choice2
	_dm.choose(0)  # trusted_edith = true -> logbook_end_radio
	_dm.advance()  # next == null -> finished
	_ok(not _dm.is_active, "logbook dialogue finished")


# --- flows --------------------------------------------------------------------

func _flow_save_then_continue_restores_journal_and_flags() -> void:
	print("-- flow: pause → Save → Main Menu → Continue")
	var game := await _goto_scene(GAME)

	await _read_logbook()
	_ok(_jr.entries() == ["entry_logbook"], "logbook discovered in session 1")
	_ok(_gs.get_flag("believer") == true and _gs.get_flag("trusted_edith") == true, "flags set in session 1")

	# Esc → pause overlay (game.gd _unhandled_input → _toggle_pause).
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await _settle()
	_ok(game.get_node_or_null("PauseLayer") != null, "pause overlay opened by ui_cancel")

	var save_button := await _press(game, "Save")
	_ok(save_button != null and save_button.text == "Saved ✓", "Save button reports success")
	var on_disk := _read_save()
	_ok(on_disk.get("scene", "") == GAME, "save records game.tscn as the resume scene")
	_ok(on_disk.get("journal", null) == ["entry_logbook"], "save holds the journal")
	_ok(on_disk.get("flags", {}).get("believer", false) == true, "save holds the flags")

	await _press(game, "Main Menu")
	_ok(current_scene.scene_file_path == MENU, "Main Menu button returns to main_menu.tscn")

	# Dirty the in-memory state so we can prove Continue restores from disk,
	# not from whatever was left in the autoloads.
	_jr.discover("entry_stale")
	_gs.set_flag("stale", true)

	await _press(current_scene, "Continue")
	_ok(current_scene.scene_file_path == GAME, "Continue resumes into game.tscn")
	_ok(_jr.entries() == ["entry_logbook"], "journal restored from disk (stale in-memory entry gone)")
	_ok(_gs.flags == {"believer": true, "trusted_edith": true}, "flags restored from disk exactly, stale flag gone")

	# Re-read the logbook after Continue: no new discovery, flags unaffected.
	var added: Array[String] = []
	var cb := func(id: String): added.append(id)
	_jr.entry_added.connect(cb)
	await _read_logbook()
	_jr.entry_added.disconnect(cb)
	_ok(added.is_empty(), "re-reading after Continue emits no entry_added")
	_ok(_jr.entries() == ["entry_logbook"], "journal unchanged after re-read")
	_ok(_gs.flags == {"believer": true, "trusted_edith": true}, "flags unchanged after re-read")

	# The freed session-1 game.gd had lambdas connected to DialogueManager
	# signals; emitting through a dialogue above must not have raised errors.
	# (Godot prints 'Callable is invalid' if it did — visible in the console.)


func _flow_new_game_after_continue_starts_clean() -> void:
	print("-- flow: Main Menu → New Game after a Continue")
	await _goto_scene(MENU)
	_ok(_jr.entries() == ["entry_logbook"], "journal still populated from the Continue before")
	await _press(current_scene, "New Game")
	_ok(current_scene.scene_file_path == GAME, "New Game enters game.tscn")
	_ok(_jr.entries().is_empty(), "New Game starts with an empty journal")
	_ok(_gs.flags.is_empty(), "New Game starts with no flags")
	_ok(FileAccess.file_exists(_gs.SAVE_PATH), "New Game does not delete the existing save (unchanged behaviour)")
