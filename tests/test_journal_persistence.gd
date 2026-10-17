extends SceneTree
## Headless regression tests for Journal persistence through GameState.
##
## Run from the project root (no editor needed):
##   godot --headless --path . -s res://tests/test_journal_persistence.gd
## Exit code 0 = all passed, 1 = at least one failure.
##
## Uses the real autoloads and the real user:// save path, so it deletes the
## save in that user data dir. Point XDG_DATA_HOME at a temp dir in CI.

const SaveSandbox := preload("res://tests/save_sandbox.gd")

var _failures := 0
var _checks := 0
var _sandbox := SaveSandbox.new()

# Autoload singletons aren't globals when a `-s` script compiles, so fetch
# them from the tree once it's up.
var _gs: Node
var _jr: Node
var _dm: Node


func _init() -> void:
	# Autoloads are registered after the main loop is created; run on frame 1.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_gs = root.get_node("GameState")
	_jr = root.get_node("Journal")
	_dm = root.get_node("DialogueManager")
	if not _sandbox.enter():
		quit(2)
		return
	var tests := [
		test_journal_survives_save_and_continue,
		test_legacy_save_without_journal_restores_empty,
		test_legacy_save_does_not_reconstruct_from_flags,
		test_authentic_v1_save_from_original_code_loads,
		test_new_game_clears_journal,
		test_malformed_journal_block_restores_safely,
		test_malformed_journal_alongside_valid_scene_and_flags,
		test_empty_entry_id_is_ignored,
		test_dialogue_discover_records_entry_without_touching_flags,
		test_radio_node_discovers_entry_radio_at_runtime,
		test_repeated_discovery_after_continue_is_a_no_op,
		test_corrupt_root_json_fails_without_touching_memory,
	]
	for t in tests:
		_reset()
		var name: String = (t as Callable).get_method()
		var before := _failures
		t.call()
		print("%s  %s" % ["PASS" if _failures == before else "FAIL", name])

	_reset()
	if not _sandbox.leave():
		_failures += 1
	print("\n%d checks, %d failure(s)" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


# --- helpers ------------------------------------------------------------------

func _reset() -> void:
	_gs.delete_save()
	_gs.flags.clear()
	_gs.current_scene = "res://scenes/game.tscn"
	_jr.clear()


## Play a started dialogue to its end, taking choice 0 at every branch, so
## DialogueManager.is_active is false before the next test.
func _drain_dialogue() -> void:
	while _dm.is_active:
		_dm.advance()   # no-op on a choice node
		if _dm.is_active:
			_dm.choose(0)  # no-op on a linear node


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("  assertion failed: " + msg)


func _write_save(text: String) -> void:
	var f := FileAccess.open(_gs.SAVE_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read_save() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_gs.SAVE_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


# --- tests --------------------------------------------------------------------

func test_journal_survives_save_and_continue() -> void:
	_gs.set_flag("skeptic", true)
	_gs.set_flag("trusted_edith", false)
	_jr.discover("entry_logbook")
	_jr.discover("entry_radio")
	_jr.discover("entry_logbook")  # duplicate discovery is a no-op
	_ok(_gs.save_game(), "save_game returns true")
	_ok(_read_save().get("journal", null) == ["entry_logbook", "entry_radio"],
		"journal written in discovery order, deduped")

	_gs.flags.clear()
	_jr.clear()
	_ok(_gs.load_game(), "load_game returns true")
	_ok(_jr.entries() == ["entry_logbook", "entry_radio"], "journal restored in order")
	_ok(_gs.get_flag("skeptic") == true, "skeptic flag unchanged by journal persistence")
	_ok(_gs.flags.has("trusted_edith") and _gs.get_flag("trusted_edith") == false,
		"trusted_edith=false unchanged by journal persistence")


func test_legacy_save_without_journal_restores_empty() -> void:
	# Exactly what the shipped vertical-slice / demo build writes: no journal key.
	_write_save("""{
	"flags": {
		"believer": true,
		"trusted_edith": true,
		"radioed_tom": true
	},
	"scene": "res://scenes/game.tscn",
	"version": 1
}""")
	_jr.discover("entry_stale")  # in-memory state before Continue must not leak
	_ok(_gs.load_game(), "legacy save loads")
	_ok(_jr.entries().is_empty(), "legacy save restores an empty journal")
	_ok(_gs.get_flag("believer") == true and _gs.get_flag("radioed_tom") == true,
		"legacy flags still load")
	_ok(_gs.current_scene == "res://scenes/game.tscn", "legacy scene still loads")


func test_legacy_save_does_not_reconstruct_from_flags() -> void:
	# Flags that would correspond to every journal entry; still no backfill.
	_write_save('{"flags": {"skeptic": true, "trusted_edith": false, "radioed_tom": true}, "scene": "res://scenes/game.tscn", "version": 1}')
	_ok(_gs.load_game(), "legacy save loads")
	_ok(not _jr.has("entry_logbook"), "entry_logbook not inferred from logbook flags")
	_ok(not _jr.has("entry_radio"), "entry_radio not inferred from radioed_tom")
	# Saving again writes an explicit empty journal rather than inventing one.
	_gs.save_game()
	_ok(_read_save().get("journal", null) == [], "re-save writes an explicit empty journal")


func test_authentic_v1_save_from_original_code_loads() -> void:
	# tests/fixtures/save_v1_8c9b1e4.json was written by GameState.save_game()
	# at commit 8c9b1e4 (the Next Fest demo candidate, before this branch)
	# after playing: logbook -> believer -> keep quiet; radio -> ask about Edith.
	# It is the real on-disk shape a demo playtester's save has.
	var fixture := FileAccess.get_file_as_string("res://tests/fixtures/save_v1_8c9b1e4.json")
	_ok(not fixture.is_empty(), "fixture present")
	_ok(not fixture.contains("journal"), "fixture has no journal key (sanity)")
	_write_save(fixture)
	_jr.discover("entry_stale")
	_ok(_gs.load_game(), "authentic v1 save loads")
	_ok(_gs.flags == {"believer": true, "radioed_tom": true, "trusted_edith": false},
		"all three flags load with their exact values (trusted_edith=false kept as false)")
	_ok(_gs.current_scene == "res://scenes/game.tscn", "scene loads")
	_ok(_jr.entries().is_empty(), "journal is empty: nothing inferred from believer/radioed_tom")
	# Round-trip: re-save writes the same flags/scene plus an explicit empty journal,
	# and the result loads again identically.
	_gs.save_game()
	var resaved := _read_save()
	_ok(resaved.get("journal", null) == [], "re-save adds journal: []")
	_ok(resaved.get("flags", {}) == {"believer": true, "radioed_tom": true, "trusted_edith": false}, "re-save keeps flags")
	_ok(int(resaved.get("version", 0)) == 1, "re-save keeps version 1")
	_gs.flags.clear()
	_ok(_gs.load_game() and _gs.flags.size() == 3 and _jr.entries().is_empty(), "re-saved file loads identically")


func test_new_game_clears_journal() -> void:
	_gs.set_flag("skeptic", true)
	_jr.discover("entry_logbook")
	_gs.new_game()
	_ok(_gs.flags.is_empty(), "new_game clears flags (unchanged behaviour)")
	_ok(_jr.entries().is_empty(), "new_game clears journal")


func test_malformed_journal_block_restores_safely() -> void:
	_write_save('{"flags": {}, "scene": "res://scenes/game.tscn", "version": 1, "journal": ["entry_logbook", 7, "", null, "entry_logbook", "entry_radio"]}')
	_ok(_gs.load_game(), "load succeeds despite junk journal items")
	_ok(_jr.entries() == ["entry_logbook", "entry_radio"], "junk dropped, duplicates collapsed, order kept")

	_write_save('{"flags": {}, "scene": "res://scenes/game.tscn", "version": 1, "journal": "oops"}')
	_ok(_gs.load_game(), "load succeeds with non-array journal")
	_ok(_jr.entries().is_empty(), "non-array journal restores empty")


func test_dialogue_discover_records_entry_without_touching_flags() -> void:
	var added: Array[String] = []
	var cb := func(id: String): added.append(id)
	_jr.entry_added.connect(cb)
	_ok(_dm.start("res://data/dialogue/keeper_intro.json", "logbook"), "logbook dialogue starts")
	_ok(_jr.has("entry_logbook"), "entering the logbook node discovers entry_logbook")
	_ok(added == ["entry_logbook"], "entry_added emitted exactly once")
	_ok(_gs.flags.is_empty(), "discovery sets no story flags")
	_dm.advance()  # logbook_2
	_dm.advance()  # logbook_choice1
	_dm.choose(1)  # believer
	_ok(_gs.get_flag("believer") == true, "choice still sets its story flag")
	_ok(not _gs.flags.has("skeptic"), "other branch's flag not set")
	_jr.entry_added.disconnect(cb)
	_drain_dialogue()


func test_corrupt_root_json_fails_without_touching_memory() -> void:
	# The player has live progress in memory and then Continues over a save
	# whose root is unusable. load_game() must return false and leave flags,
	# journal and scene exactly as they were.
	var corrupt_roots := {
		"truncated mid-object": '{"flags": {"skeptic": tr',
		"empty file": "",
		"not JSON at all": "keeper's log, page 1",
		"JSON array root": '[{"flags": {}}]',
		"JSON string root": '"save"',
		"JSON number root": "42",
		"JSON null root": "null",
	}
	for label in corrupt_roots:
		_gs.flags = {"believer": true, "trusted_edith": false}
		_gs.current_scene = "res://scenes/game.tscn"
		_jr.clear()
		_jr.discover("entry_logbook")
		_jr.discover("entry_radio")
		var changed := [false]
		var cb := func(): changed[0] = true
		_gs.state_changed.connect(cb)
		_write_save(corrupt_roots[label])
		var loaded: bool = _gs.load_game()
		_gs.state_changed.disconnect(cb)
		_ok(not loaded, "%s: load_game returns false" % label)
		_ok(_gs.flags == {"believer": true, "trusted_edith": false}, "%s: flags untouched" % label)
		_ok(_jr.entries() == ["entry_logbook", "entry_radio"], "%s: journal untouched" % label)
		_ok(_gs.current_scene == "res://scenes/game.tscn", "%s: scene untouched" % label)
		_ok(not changed[0], "%s: state_changed not emitted" % label)
		_ok(FileAccess.get_file_as_string(_gs.SAVE_PATH) == corrupt_roots[label], "%s: corrupt file left as-is for inspection" % label)


func test_malformed_journal_alongside_valid_scene_and_flags() -> void:
	# Junk in the journal block must not cost the player their flags or scene.
	_write_save("""{
	"version": 1,
	"scene": "res://scenes/game.tscn",
	"flags": { "skeptic": true, "trusted_edith": false, "radioed_tom": true },
	"journal": { "entry_logbook": true }
}""")
	_ok(_gs.load_game(), "load succeeds with an object where the array should be")
	_ok(_jr.entries().is_empty(), "journal restores empty")
	_ok(_gs.get_flag("skeptic") == true, "skeptic flag intact")
	_ok(_gs.flags.has("trusted_edith") and _gs.get_flag("trusted_edith") == false, "trusted_edith=false intact")
	_ok(_gs.get_flag("radioed_tom") == true, "radioed_tom flag intact")
	_ok(_gs.current_scene == "res://scenes/game.tscn", "scene intact")

	_write_save("""{
	"version": 1,
	"scene": "res://scenes/game.tscn",
	"flags": { "believer": true },
	"journal": [ 42, "entry_radio", null, "", { "id": "entry_logbook" }, "entry_radio" ]
}""")
	_ok(_gs.load_game(), "load succeeds with mixed junk in the array")
	_ok(_jr.entries() == ["entry_radio"], "only the valid id survives, once")
	_ok(_gs.get_flag("believer") == true and _gs.flags.size() == 1, "flags exactly as saved")
	_ok(_gs.current_scene == "res://scenes/game.tscn", "scene intact")


func test_empty_entry_id_is_ignored() -> void:
	var added: Array[String] = []
	var cb := func(id: String): added.append(id)
	_jr.entry_added.connect(cb)
	_jr.discover("")
	_ok(_jr.entries().is_empty(), "discover(\"\") adds nothing")
	_ok(added.is_empty(), "discover(\"\") emits nothing")
	_ok(not _jr.has(""), "has(\"\") is false")
	_jr.discover("entry_logbook")
	_jr.discover("")
	_ok(_jr.entries() == ["entry_logbook"], "empty id after a real one still ignored")
	_gs.save_game()
	_ok(_read_save().get("journal", null) == ["entry_logbook"], "empty id never reaches the save file")
	_jr.entry_added.disconnect(cb)


func test_radio_node_discovers_entry_radio_at_runtime() -> void:
	var added: Array[String] = []
	var cb := func(id: String): added.append(id)
	_jr.entry_added.connect(cb)
	_ok(_dm.start("res://data/dialogue/keeper_intro.json", "radio"), "radio dialogue starts")
	_ok(_jr.has("entry_radio"), "entering the radio node discovers entry_radio")
	_ok(not _jr.has("entry_logbook"), "logbook entry not discovered by the radio")
	_ok(added == ["entry_radio"], "entry_added emitted exactly once")
	_ok(_gs.flags.is_empty(), "no flags set on entry; radioed_tom comes from the choice")
	_dm.advance()  # radio_2 (choice node)
	_dm.choose(0)  # "Ask him about Edith."
	_ok(_gs.get_flag("radioed_tom") == true, "radioed_tom still set by the choice")
	_ok(added == ["entry_radio"], "walking the rest of the graph discovers nothing more")
	_gs.save_game()
	_ok(_read_save().get("journal", null) == ["entry_radio"], "entry_radio persisted")
	_jr.entry_added.disconnect(cb)
	_drain_dialogue()


func test_repeated_discovery_after_continue_is_a_no_op() -> void:
	# Session 1: read the logbook, save.
	_ok(_dm.start("res://data/dialogue/keeper_intro.json", "logbook"), "session 1: logbook starts")
	_drain_dialogue()
	_ok(_jr.entries() == ["entry_logbook"], "session 1: entry recorded")
	_gs.save_game()

	# Session 2: fresh state, Continue, read the logbook again.
	_gs.flags.clear()
	_jr.clear()
	_ok(_gs.load_game(), "session 2: Continue")
	var added: Array[String] = []
	var cb := func(id: String): added.append(id)
	_jr.entry_added.connect(cb)
	_ok(_dm.start("res://data/dialogue/keeper_intro.json", "logbook"), "session 2: logbook starts again")
	_ok(added.is_empty(), "re-reading after Continue does not emit entry_added")
	_ok(_jr.entries() == ["entry_logbook"], "journal unchanged after re-read")
	_drain_dialogue()
	_jr.entry_added.disconnect(cb)
	_gs.save_game()
	_ok(_read_save().get("journal", null) == ["entry_logbook"], "re-save still holds one entry")
