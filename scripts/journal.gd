extends Node
## Journal — discovered-logs system.
##
## Autoloaded as `Journal`. A dialogue node with a `"discover": "<entry_id>"`
## key records an entry here when entered (see DialogueManager._goto). Entries
## are persisted by GameState.save_game() and restored by GameState.load_game().
## Discovery order is preserved. No reader UI yet.

signal entry_added(id: String)

var _entries: Array[String] = []


func discover(id: String) -> void:
	if id.is_empty():
		push_warning("Journal: ignoring empty entry id.")
		return
	if id in _entries:
		return
	_entries.append(id)
	entry_added.emit(id)


func entries() -> Array[String]:
	return _entries.duplicate()


func has(id: String) -> bool:
	return id in _entries


func clear() -> void:
	_entries.clear()


## Replace the journal with the ids from a save file. Anything that isn't a
## non-empty string is dropped; duplicates collapse; order is kept. Does not
## emit `entry_added` — a restore is not a discovery.
func restore(raw: Variant) -> void:
	_entries.clear()
	if typeof(raw) != TYPE_ARRAY:
		if raw != null:
			push_warning("Journal: save 'journal' block is not an array; starting empty.")
		return
	for item in raw:
		if typeof(item) != TYPE_STRING or (item as String).is_empty():
			push_warning("Journal: dropping invalid entry %s from save." % str(item))
			continue
		if item not in _entries:
			_entries.append(item)
