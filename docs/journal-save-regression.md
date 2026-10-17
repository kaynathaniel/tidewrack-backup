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
Main Menu, Continue and New Game buttons by their labels. It runs
**headless**: scenes are instantiated and buttons are pressed, but nothing is
rendered and nothing has been looked at on screen. Every ✅ it produces is a
claim about state, not about what a player would see.

### Running the suites safely

Both suites use the real autoloads and therefore the real `user://` data dir
— Godot 4.3 has no command-line switch to redirect it. They are safe to run
on a machine with a developer save because every suite goes through
`tests/save_sandbox.gd`:

1. **Before the first test**, an existing `user://save.json` is moved to
   `user://save.json.pretest` and its SHA-256 recorded. If there is no save,
   nothing is moved.
2. **Tests run** against a scratch `save.json` that they create and delete.
3. **After the last test**, the scratch file is removed, the original is
   moved back, and re-hashed. A mismatch counts as a test failure and is
   printed.
4. **If a previous run crashed** between steps 1 and 3, `save.json.pretest`
   is still on disk. The next run refuses to start (exit code 2) and prints
   the absolute path, so nothing is overwritten.

**Recovering from a crashed run.** `save.json.pretest` is your real save
from before the crashed run. Look in the printed directory first:

- **Only `save.json.pretest` exists** — rename it to `save.json`. Done.
- **Both files exist** — do not overwrite either. `save.json` is *either* the
  scratch file the crashed run was using (if you have not played since) *or*
  a newer real save (if you launched the game in between). Decide which one
  you want to keep, rename the other to something like
  `save.json.YYYY-MM-DD.bak`, and only then rename `save.json.pretest` to
  `save.json` if that is the one you chose. If in doubt, keep both renamed
  copies; a scratch file is recognisable by its contents (a handful of test
  flags such as `"a"`, `"count"`, `"stale"`, or an `entry_stale` journal
  id).

Never run the suites again until `.pretest` is gone; they will refuse anyway.

Expected console lines when a save exists:

```
SaveSandbox: existing save moved aside (sha256 806cd997f9a8…)
…
SaveSandbox: original save restored and verified byte-identical (sha256 806cd997f9a8…)
```

Verified on 2026-10-17: a hand-written `save.json` with a distinctive
`"dev_note"` field was byte-identical (external `sha256sum`) after both
suites ran back-to-back; the same with the authentic `8c9b1e4` fixture as the
developer save; a planted `.pretest` alone, and a planted `.pretest` plus a
`save.json`, each made the suite exit 2 with neither file touched and the
console pointing at the recovery steps above; with no save present the
suites left the directory empty.

Exit codes: `0` all passed · `1` a check failed or the original save could
not be restored · `2` refused to run because a `.pretest` file exists.

For a fully separate data dir on Linux CI, `XDG_DATA_HOME=$(mktemp -d)` in
front of the command also works (macOS: `HOME`, Windows: `APPDATA`), but the
sandbox makes that optional rather than required.

**Status key** — ✅ asserted by an automated test, passing on Godot
4.3.stable (Linux, headless) · 👁 observed in a headless run's console
output, not asserted by any test · 🟡 manual check, not yet performed ·
⬜ not covered.

## 1. Normal Continue

The in-game rows below are covered by the headless flow suite: real scenes,
real input event, real buttons, no rendering. Nothing in this section has
been checked visually.

| Expectation | Coverage | Status |
|---|---|---|
| After examining the logbook and radio, Save then Continue restores both entries in discovery order. | `test_journal_survives_save_and_continue` | ✅ |
| The `"journal"` key is written as a JSON array of ids. | same test, reads the file back | ✅ |
| Story flags set in the same session (`skeptic`, `trusted_edith=false`) are unchanged by journal persistence. | same test | ✅ |
| In-game: Esc → pause overlay → [Save] writes `scene`, `flags` and `journal`; Save button reads "Saved ✓". | `test_pause_save_continue_flow.gd` | ✅ |
| [Main Menu] returns to `main_menu.tscn`; [Continue] resumes into `game.tscn` with journal and flags restored **from disk**, discarding stale in-memory state. | same flow test (dirties the autoloads before pressing Continue) | ✅ |
| Re-reading the logbook after Continue emits no `entry_added` and changes neither journal nor flags. | same flow test | ✅ |
| A dialogue run in the resumed scene raises no `Callable is invalid` errors from the freed session-1 `game.gd` signal lambdas. | console output of the flow suite was clean; no test asserts it | 👁 |
| The journal entries are *visible* after Continue, and the pause overlay / menus look right while doing it. | manual, with a rendered build; the reader UI does not exist yet | 🟡 |
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
| A save written by the **original** `GameState.save_game()` at `8c9b1e4` (demo candidate) loads on this branch: all three flags exact, scene intact, journal empty; re-save adds `"journal": []`, keeps `version: 1`, and loads again identically. | `test_authentic_v1_save_from_original_code_loads`, using `tests/fixtures/save_v1_8c9b1e4.json` — generated by running the pre-branch code headlessly (logbook → believer → keep quiet; radio → ask about Edith), not hand-written | ✅ |
| A save file captured from an actual Next Fest playtester's machine loads. | not done — the fixture is produced by the demo code, not collected from a player | 🟡 |
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
| Corrupt root (truncated object, empty file, plain text, JSON array / string / number / `null` root) → `load_game()` returns false; in-memory flags, journal and scene are untouched; `state_changed` is not emitted; the corrupt file is left on disk for inspection. | `test_corrupt_root_json_fails_without_touching_memory` (7 shapes) | ✅ |

## 6. Dialogue wiring

| Expectation | Coverage | Status |
|---|---|---|
| Entering `logbook` records `entry_logbook` and sets no flags. | `test_dialogue_discover_records_entry_without_touching_flags` | ✅ |
| The `believer` choice still sets its flag and not `skeptic`. | same test | ✅ |
| Entering `radio` records `entry_radio` once, sets no flags on entry, and the "Ask him about Edith" choice still sets `radioed_tom`. | `test_radio_node_discovers_entry_radio_at_runtime` | ✅ |
| Every `"discover"` value in `data/dialogue/*.json` is a non-empty string. | `python3 tests/validate_dialogue.py` | ✅ |

## Last verified run

Branch `fix/journal-save-persistence` at the commit that added the
authentic-v1 and corrupt-root tests, Godot 4.3.stable Linux
headless, 2026-10-17, with a developer save present (the `SaveSandbox` lines
are what you should see; `push_warning` lines from the malformed-data and
empty-id tests are omitted here but expected):

```
godot --headless --path . -s res://tests/test_journal_persistence.gd

SaveSandbox: existing save moved aside (sha256 806cd997f9a8…)
PASS  test_journal_survives_save_and_continue
PASS  test_legacy_save_without_journal_restores_empty
PASS  test_legacy_save_does_not_reconstruct_from_flags
PASS  test_authentic_v1_save_from_original_code_loads
PASS  test_new_game_clears_journal
PASS  test_malformed_journal_block_restores_safely
PASS  test_malformed_journal_alongside_valid_scene_and_flags
PASS  test_empty_entry_id_is_ignored
PASS  test_dialogue_discover_records_entry_without_touching_flags
PASS  test_radio_node_discovers_entry_radio_at_runtime
PASS  test_repeated_discovery_after_continue_is_a_no_op
PASS  test_corrupt_root_json_fails_without_touching_memory
SaveSandbox: original save restored and verified byte-identical (sha256 806cd997f9a8…)

108 checks, 0 failure(s)
```

```
godot --headless --path . -s res://tests/test_pause_save_continue_flow.gd

SaveSandbox: existing save moved aside (sha256 806cd997f9a8…)
-- flow: pause → Save → Main Menu → Continue
-- flow: Main Menu → New Game after a Continue
SaveSandbox: original save restored and verified byte-identical (sha256 806cd997f9a8…)

33 checks, 0 failure(s)
```

Warnings printed during `test_malformed_journal_block_restores_safely`,
`test_malformed_journal_alongside_valid_scene_and_flags` and
`test_empty_entry_id_is_ignored`, and the `Parse JSON failed` /
`save file is corrupt` errors during
`test_corrupt_root_json_fails_without_touching_memory`, are expected; they are the `push_warning`
calls under test. Only Linux headless has been run; nothing in the path is
platform-specific, but a Windows/macOS run before launch would close that
gap.
