# Determinism replay suite

`test_replay_suite.gd` records a run and replays it twice inside the same test. Nothing here writes a trace file. The suite's own recordings leave `trace.prefix` empty. One M6 case sets `trace.prefix` to `harbor.alpha` because that case is the prefix filter; the driver does not clear that prefix after the step that sets it.

Boot uses `scheduler_frame_warn_usec = 0`, so the frame-warning row is not logged. Comparison is `WyrdTrace.diff` plus `JSON.stringify` of the rows with `timing` rows removed. The gameplay save (`gameplay_hash`, the save with `ai` removed) is compared as well.

## What is replayed

- All 32 Gullhaven routes in `tests/scenario/m10_gullhaven.gd`, with no provider and with the `echo` provider. The driver's uninterrupted trace must equal `play()` on the same spec.
- The M4 matrix (`MATRIX_SIZE`, 39 cases): reach, the role action, and `tick(0)`, with the same people and election adapter.
- The M5 matrix (`MATRIX_SIZE`, 6 cases).
- The runtime calls in `tests/unit/test_m6_matrix.gd`. Reads are repeated steps. Inline packs are compiled to `user://` the way that file's pack boot does. The voiced-line case is CLI only and is not included.
- The 13 M7 console kills, run in-process through `WyrdConsole.exec` (`kill <role>`, `time 0`), plus the coverage play and the choice-summary play (that play also has a load run).
- The M9 stew-tier, cap-and-retry, and save-mid-generation plays, beyond the eight generated routes already in the 32.

M3 is left out: its exit checks compiler and editor rows and makes no runtime play. M8 is left out: it has no exit or matrix file.

## Replayed and repeated

Each step is an op from the m10 vocabulary, or a matrix op in `replay_cases.gd`. An op has up to three parts: a host part (fake world, spatial, inventory, clock, action results), a setup part (an adapter or callback; not saved), and a Wyrd part.

The driver records the trace length after the step's action and again after its pump. That is the action segment and the pump segment.

- **Replayed.** Every Wyrd call in the step is a recorded input. The host and setup parts run first, then `WyrdTrace.replay` runs the action segment. The step is not pumped.
- **Repeated.** The step calls something that is not a recorded input (an `unrecorded` call, or a debug read that logs a compared row). The whole step runs again from the step list. Its action segment is not replayed.

The pump segment is always replayed from its rows. A replay never pumps. `replay_driver.gd` `MODE` is the table, and the report test prints it.

`emit` and `emit_rejected` share one arm in `WyrdTrace.replay` and one method, `WyrdEvents.emit`. The inventory lists that method as `input:emit`. An arm counts as covered when any kind in it has an `input` entry. Kinds on the skip arm do not need an entry.

## Split points

A boundary after step k is a split point when `can_save()` is true, the AI module has no open request, the generator's queued-offer count (`generator.pending_count()`) is 0, and no proposal made at or before step k is accepted after it. Load drops the offer queue, so a boundary with a queued offer is not a split point. A step that already saves and loads in place (`save_load`, `save_hold`, `load_held`) is repeated.

Every tested split point, for no provider and for `echo`, and for each matrix case, checks three things.

The prefix is replayed on runtime A and saved. The save is round-tripped through `JSON.stringify` and `JSON.parse_string`. Runtime B is a fresh boot with the host and setup parts of the prefix applied, then `load_state`. Godot's parser turns integers into floats, so the load baseline is the canonical text of the save that was written (`JSON.stringify` with sorted keys) against `save_state()` immediately after the load. The load is `ok`. Its report rows are exactly the `kept` rows from `WyrdSave._note_kept` on that prefix runtime: ids the content does not declare and, for roles, ids the host has not passed to `roles.define()`. Every row logged during `load_state` is an `ai_*` row.

The tail is then played live on B and that trace is the split recording. The same load and tail are replayed twice more, each into a fresh runtime: host and setup, load, then `WyrdTrace.replay` of the recording. Each of those replays has an empty `WyrdTrace.diff` and byte-identical rows with `timing` rows removed.

`gameplay_hash` after the live tail equals the uninterrupted run. That comparison stays strict.

The live tail is not required to match the uninterrupted tail row for row. A load may restart AI request ids, proposal ids, and emit ids. The report prints the first mismatching rows of the middle split of each route, for each provider. That section is `SPLIT VS UNINTERRUPTED`.

An unrestricted local run of this script took 226 seconds, so `ReplayDriver.limit_plain_splits` is on: no-provider route splits use only the first, middle, and last split point of each route. Case splits stay complete. Echo route splits stay complete.

## Call inventory

`test_call_inventory` scans `WyrdRuntime`, the facade script, every facade sub-object, and `WyrdConsole` with `get_script_method_list()`. Names that begin with `_` are skipped. `WyrdFactStore.set` is added by hand, because world facts are written through `Object._set`.

Each public call is one entry in `replay_inventory.gd`, written as `<class>.<method>`, with a category and a one-line reason:

- `input:<kind>` records that replay input.
- `read` does not change state.
- `setup` is registration or config, done the same way at boot in both runtimes.
- `boundary` is `start_new_game`, `load_content`, `save_state`, `load_state`, or an export or import.
- `debug` is the inspector, coverage, and trace control.
- `internal` is public only so Wyrd's own classes can call it.
- `unrecorded` changes state and records no replay input.

The test fails when a scanned method has no entry, an entry names a method that no longer exists, an `input:<kind>` names a kind `WyrdTrace.replay` does not handle, or a kind that `replay` handles has no `input` entry. A kind that no run exercises is listed, not failed.

To add a public call, add its entry. If it can change a saved value, a later decision, or a compared trace row, record an input or list it as `unrecorded` with a reason. Do not leave it out.
