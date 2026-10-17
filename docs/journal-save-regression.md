# Journal save/load — regression coverage

Reference for the journal persistence path (`scripts/journal.gd`,
`scripts/autoload/game_state.gd`, `scripts/autoload/dialogue_manager.gd`).
Each scenario lists the expected behaviour, how it is covered, and whether
that coverage has actually been run.

Automated suites, run from the project root:

```
godot --headless --path . -s res://tests/test_journal_persistence.gd      # unit: GameState + Journal
godot --headless --path . -s res://tests/test_pause_save_continue_flow.gd  # scene-level: real buttons
```

The flow suite loads the real `game.tscn` and `main_menu.tscn`, sends a real
`ui_cancel` input to open the pause overlay, and presses the actual Save,
Main Menu, Continue and New Game buttons by their labels.

Exit code 0 means every check passed. The suite uses the real autoloads and the
real `user://` save path, so it deletes `save.json` in Tidewrack's user data
dir — set `XDG_DATA_HOME` (or `--user-data-dir`) to a scratch location in CI.

**Status key** — ✅ automated and passing on Godot 4.3.stable (Linux, headless)
· 🟡 manual check, not yet performed · ⬜ not covered.

## 1. Normal Continue

| Expectation | Coverage | Status |
|---|---|---|
| After examining the logbook and radio, Save then Continue restores both entries in discovery order. | `test_journal_survives_save_and_continue` | ✅ |
| The `"journal"` key is written as a JSON array of ids. | same test, reads the file back | ✅ |
| Story flags set in the same session (`skeptic`, `trusted_edith=false`) are unchanged by journal persistence. | same test | ✅ |
| In-game: Esc → pause overlay → [Save] writes `scene`, `flags` and `journal`; Save button reads "Saved ✓". | `test_pause_save_continue_flow.gd` | ✅ |
| [Main Menu] returns to `main_menu.tscn`; [Continue] resumes into `game.tscn` with journal and flags restored **from disk**, discarding stale in-memory state. | same flow test (dirties the autoloads before pressing Continue) | ✅ |
| Re-reading the logbook after Continue emits no `entry_added` and changes neither journal nor flags. | same flow test | ✅ |
| A dialogue run in the resumed scene raises no `Callable is invalid` errors from the freed session-1 `game.gd` signal lambdas. | same flow test; checked by inspecting console output, not asserted | ✅ |
| The journal entries are *visible* after Continue. | manual, once the reader UI exists | 🟡 |
| Save from the lamp room. | not applicable — the lamp room has no pause menu yet | ⬜ |

## 2. Legacy saves (no `"journal"` key)

Vertical-slice and Next Fest demo builds write `{"version": 1, "scene", "flags"}` only.

| Expectation | Coverage | Status |
|---|---|---|
| A save without `"journal"` loads successfully. | `test_legacy_save_without_journal_restores_empty` | ✅ |
| It restores an **empty** journal, even if the in-memory journal held entries before Continue. | same test | ✅ |
| Its flags and scene load exactly as before. | same test | ✅ |
| Entries are **not** reconstructed from flags, even when every journal-relevant flag is set. | `test_legacy_save_does_not_reconstruct_from_flags` | ✅ |
| Re-saving such a game writes an explicit empty `"journal": []`. | `test_legacy_save_does_not_reconstruct_from_flags` | ✅ |
| A real playtester save file from the demo build loads on this branch. | manual — the test fabricates the v1 shape rather than using a captured file | 🟡 |
| An old build opening a save written by this branch ignores the extra key. | by inspection of `load_game()` at `8c9b1e4` (it only reads `scene` and `flags`); not executed | 🟡 |

## 3. New Game reset

| Expectation | Coverage | Status |
|---|---|---|
| `GameState.new_game()` empties the journal. | `test_new_game_clears_journal` | ✅ |
| It still clears flags and resets the scene (unchanged behaviour). | same test | ✅ |
| New Game after a Continue does not carry restored entries into the fresh game; the existing save file is left alone. | `test_pause_save_continue_flow.gd` (second flow) | ✅ |

## 4. Duplicate discoveries

| Expectation | Coverage | Status |
|---|---|---|
| Discovering an id already in the journal is a no-op; the saved array has no duplicates. | `test_journal_survives_save_and_continue` (discovers `entry_logbook` twice) | ✅ |
| Entering the logbook node emits `entry_added` exactly once. | `test_dialogue_discover_records_entry_without_touching_flags` | ✅ |
| Duplicate ids in a save file collapse to one on restore, order kept. | `test_malformed_journal_block_restores_safely` | ✅ |
| Re-examining the logbook after Continue does not re-emit `entry_added`, and a re-save still holds one entry. | `test_repeated_discovery_after_continue_is_a_no_op` | ✅ |

## 5. Malformed data

| Expectation | Coverage | Status |
|---|---|---|
| `"journal"` is not an array (e.g. a string) → empty journal, load still succeeds, warning logged. | `test_malformed_journal_block_restores_safely` | ✅ |
| Non-string items (`7`, `null`) and empty strings inside the array are dropped, warning logged. | same test | ✅ |
| Valid entries in the same array survive. | same test | ✅ |
| `"journal"` is a JSON object, or an array mixing numbers, `null`, empty strings and objects, **alongside** valid flags and scene → journal degrades, flags and scene untouched. | `test_malformed_journal_alongside_valid_scene_and_flags` | ✅ |
| `Journal.discover("")` adds nothing, emits nothing, and never reaches the save file. | `test_empty_entry_id_is_ignored` | ✅ |
| Corrupt `save.json` overall (not valid JSON) → `load_game()` returns false, journal untouched. | pre-existing `load_game()` behaviour; not covered here | ⬜ |

## 6. Dialogue wiring

| Expectation | Coverage | Status |
|---|---|---|
| Entering `logbook` records `entry_logbook` and sets no flags. | `test_dialogue_discover_records_entry_without_touching_flags` | ✅ |
| The `believer` choice still sets its flag and not `skeptic`. | same test | ✅ |
| Entering `radio` records `entry_radio` once, sets no flags on entry, and the "Ask him about Edith" choice still sets `radioed_tom`. | `test_radio_node_discovers_entry_radio_at_runtime` | ✅ |
| Every `"discover"` value in `data/dialogue/*.json` is a non-empty string. | `python3 tests/validate_dialogue.py` | ✅ |

## Running the suite yourself

Last verified run (branch `fix/journal-save-persistence`, Godot 4.3.stable
Linux headless, 2026-10-17):

```
PASS  test_journal_survives_save_and_continue
PASS  test_legacy_save_without_journal_restores_empty
PASS  test_legacy_save_does_not_reconstruct_from_flags
PASS  test_new_game_clears_journal
PASS  test_malformed_journal_block_restores_safely
PASS  test_malformed_journal_alongside_valid_scene_and_flags
PASS  test_empty_entry_id_is_ignored
PASS  test_dialogue_discover_records_entry_without_touching_flags
PASS  test_radio_node_discovers_entry_radio_at_runtime
PASS  test_repeated_discovery_after_continue_is_a_no_op

56 checks, 0 failure(s)
```

```
godot --headless --path . -s res://tests/test_pause_save_continue_flow.gd

-- flow: pause → Save → Main Menu → Continue
-- flow: Main Menu → New Game after a Continue

33 checks, 0 failure(s)
```

Warnings printed during the malformed-data test are expected; they are the
`push_warning` calls under test. Only Linux headless has been run; nothing in
the path is platform-specific, but a Windows/macOS run before launch would
close that gap.
