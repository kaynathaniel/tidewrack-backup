# Tidewrack — Game Design Document

Concise and living. For story canon see [`narrative-bible.md`](narrative-bible.md);
for schedule see [`milestones.md`](milestones.md).

## Pillars

1. **The fog keeps its secrets.** Discovery is slow, earned, and atmospheric.
2. **Words over combat.** The game is exploration + reading + choices. No fail
   states, no timers, no death.
3. **A place you tend.** The lighthouse is a home and a job; verbs are keeper's
   verbs — light the lamp, log the night, work the radio.

## Core loop

Explore a location → find a document, recording, or object → read/hear it in a
branching conversation → make a choice that sets a flag → the world (and later,
who answers you) responds. Repeat across locations toward the water.

## Systems

| System | State | Notes |
|--------|-------|-------|
| Branching dialogue | ✅ vertical slice | JSON graphs, choices set flags. |
| Save / load        | ✅ vertical slice | Single slot, `user://save.json`. |
| Menus + settings   | ✅ vertical slice | Title, pause, volume, fullscreen. |
| Player movement    | ✅ vertical slice | Top-down; wall collision pending. |
| Journal            | 🔶 demo (storage + persistence) | Discoveries recorded and saved; reader UI pending. See [Journal](#journal). |
| Second location    | ⏳ demo           | The lamp room. |
| Controller + remap  | ⏳ demo          | Currently keyboard-only, built-in actions. |
| Localization        | ⏳ press build    | String extraction + translation tables. |
| Accessibility       | ⏳ press build    | Text scale, dyslexia-friendly font, no-flash. |
| Steam integration   | ⏳ launch         | Achievements, cloud saves. |

## Journal

The journal collects the logs, recordings and objects the keeper has examined
so they can be re-read later. It is an ordered list of entry ids (`Journal`
autoload, `scripts/journal.gd`); the reader UI is still to come.

**Discovery.** A dialogue node carries `"discover": "<entry_id>"`; entering that
node records the entry. The first discovery of an id emits `entry_added`;
repeats are ignored, so re-reading the logbook does not duplicate it. Ids are
`entry_<thing>` by convention (`tests/validate_dialogue.py` warns otherwise).
Current entries: `entry_logbook` (the `logbook` node), `entry_radio` (the
`radio` node).

**Persistence.** `GameState.save_game()` writes the entry list as the
`"journal"` key of `user://save.json`, in discovery order; `load_game()` restores
it. The journal is saved and restored together with story flags but is
independent of them — flags are never used to infer entries, and discovery
never sets flags.

**Legacy saves.** Saves written before this key existed (vertical slice and the
Next Fest demo) have no `"journal"`; they load with an empty journal. The same
applies to a malformed `"journal"` block: anything that is not an array is
treated as empty, and non-string or empty ids inside an array are dropped.
Nothing else in the save is affected.

**New Game** clears the journal along with flags.

**Contract.** Entry ids live in players' save files, so — like the canonical
story flags in `narrative-bible.md` — rename only with a migration. Regression
coverage: `docs/journal-save-regression.md`.

## Interaction design

Proximity-based: walk near an object, a prompt appears, press Enter. Dialogue
uses a typewriter reveal with press-to-skip; choices are keyboard-navigable and
focus the first option automatically. Movement is locked during conversation.

## Art & audio direction

Placeholder primitives today. Target: muted, desaturated palette (slate, kelp,
lamp-gold as the one warm accent — `#ffd466`); hand-painted 2D; a sound bed of
foghorn, surf, and radio static carrying most of the mood. Concept art and
final assets are produced per-milestone (see the tracker's `art` label).

## Out of scope (YAGNI)

No inventory economy, no crafting, no procedural generation, no multiplayer.
