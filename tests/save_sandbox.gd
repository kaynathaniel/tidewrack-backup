extends RefCounted
## SaveSandbox — keeps a developer's real save out of the test suites' way.
##
## Godot has no CLI switch to redirect `user://`, so a headless test run uses
## the same data dir as the game. Before any test touches the save, `enter()`
## moves an existing `user://save.json` aside to `user://save.json.pretest`
## and records its SHA-256. `leave()` removes whatever the tests wrote, moves
## the original back, and re-hashes it to prove it is byte-identical.
##
## If a previous run crashed between enter() and leave(), the `.pretest`
## file is still on disk; enter() then refuses to run rather than overwrite
## it. Recover with:  mv save.json.pretest save.json  in the user data dir
## (printed by `OS.get_user_data_dir()`, or by `godot --path . -s` with any
## script that prints it).
##
## Usage from a `-s` SceneTree test script:
##   const SaveSandbox := preload("res://tests/save_sandbox.gd")
##   var _sandbox := SaveSandbox.new()
##   ...in _run(): if not _sandbox.enter(): quit(2); return
##   ...at the end: if not _sandbox.leave(): <count as a failure>

const SAVE_PATH := "user://save.json"
const ASIDE_PATH := "user://save.json.pretest"

var _had_save := false
var _original_sha256 := ""
var _entered := false


## Returns false (and prints why) when it is not safe to proceed.
func enter() -> bool:
	if FileAccess.file_exists(ASIDE_PATH):
		printerr("SaveSandbox: %s already exists — a previous test run did not finish." % _abs(ASIDE_PATH))
		printerr("SaveSandbox: it is your real save. Move it back to %s before running tests again." % _abs(SAVE_PATH))
		return false
	if FileAccess.file_exists(SAVE_PATH):
		_had_save = true
		_original_sha256 = FileAccess.get_sha256(SAVE_PATH)
		var err := DirAccess.rename_absolute(SAVE_PATH, ASIDE_PATH)
		if err != OK:
			printerr("SaveSandbox: could not move the existing save aside (%s); refusing to run." % error_string(err))
			return false
		print("SaveSandbox: existing save moved aside (sha256 %s…)" % _original_sha256.substr(0, 12))
	else:
		print("SaveSandbox: no existing save in %s" % OS.get_user_data_dir())
	_entered = true
	return true


## Cleans up test output and restores the original save. Returns false if the
## original could not be restored or does not match its original hash.
func leave() -> bool:
	if not _entered:
		return true
	_entered = false
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	if not _had_save:
		print("SaveSandbox: test save removed; no original to restore.")
		return true
	var err := DirAccess.rename_absolute(ASIDE_PATH, SAVE_PATH)
	if err != OK:
		printerr("SaveSandbox: FAILED to restore the original save (%s). It is still at %s." % [error_string(err), _abs(ASIDE_PATH)])
		return false
	var restored_sha256 := FileAccess.get_sha256(SAVE_PATH)
	if restored_sha256 != _original_sha256:
		printerr("SaveSandbox: restored save hash differs from the original (%s vs %s)." % [restored_sha256, _original_sha256])
		return false
	print("SaveSandbox: original save restored and verified byte-identical (sha256 %s…)" % restored_sha256.substr(0, 12))
	return true


func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)
