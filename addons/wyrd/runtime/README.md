# runtime

Engine code with no editor dependency. `wyrd_runtime.gd` is the instanceable runtime. `wyrd.gd` is the facade over one runtime. Tests construct a `WyrdRuntime` directly. The plugin does not register the autoload.

## Load

`load_content(manifest)` compiles the manifest's `.wyrd` sources with `WyrdPack.compile` and, when that reports no errors, builds a runtime-only `WyrdContent` (quests, scenes, lines, condition table, dependency index, `manifest_hash`). Any compile error refuses the load and leaves the runtime empty. Warnings do not refuse it. `export-json` stays a debug format.

Exported games must include `*.wyrd` and the manifest in the export filter. There is no import plugin in this slice.

## Facade

`configure`, `register_adapter`, `register_function`, `start_new_game`, `load_content`, and `tick` forward to the runtime. Sub-objects:

- `facts` — `set(key, value)` and `get(key)` for the world perspective, `set_in` / `get_in` when the perspective is `known/<agent>`, `invalidate(prefix)`, `subscribe(prefix)`, signal `fact_changed(key, old_value, new_value)`. Godot's `Object.set` and `Object.get` already own those names, so the store implements them with `_set` and `_get`. A perspective argument cannot be added, and `set` cannot return a bool.
- `events` — `emit(name, payload)`. The payload is kept for a later host-event schema. `emit` drops `on_event` resolver caches.
- `deeds` — `record(...)`. Decay, `deed_count`, and `deed_score` read the log.
- `social` — baselines, kinds, `axis`, `disposition`, and an optional formula.
- `roles` — `assign`, `vacate`, `define`, `tell`, `begin_quest`, `enter_stage`, `holder`, and `slot_state`.
- `quests` — status, stage, outcome, journal, `abandon`, `request_host_step`, `complete_host_step`, `register_date_formatter`. Signals: `quest_state_changed`, `stage_changed`, `journal_entry_added`, `content_unavailable`, `host_step_requested`.
- `dialogue` — `open_scene`, `advance`, `choose`, `abort`, `register_line_audio`, `can_save`. Signals: `line_ready`, `choices_ready`, `scene_ended`.

`save_state()` returns a JSON-safe dictionary. `load_state(data)` returns a `WyrdLoadReport`. Both refuse while a scene is open (`E_SAVE_OPEN`). `rng_stream(name)` returns a named PCG32 stream seeded from the game seed. `draw_u32(name)` draws from that stream. `trace` is a `WyrdTrace`; turn `enabled` on to record. `start_new_game` clears streams and the trace log. It does not write a save.

`believed/` and `held/` perspectives exist as empty maps and refuse writes (M5). `knows`, `believes`, and `held` stay false.

## Text

Dialogue text is always shown, whether or not a line is voiced. `line_audio` may return null. Audio never hides a line and never advances it. `advance()` is the only way on.

## Quests

`requires` naming a pack other than the loaded pack sets `unavailable` and emits `content_unavailable` when content loads and again on `start_new_game`. `start when` and `waits_until` move only after the tick queue has re-checked them. A stage that names a scene offers it. The host calls `open_scene`. Transitions wait until that scene ends normally. An aborted scene stays offered.

The quest completes when every declared outcome is set and the current body has no transition left. Any outcome value `failed` fails the quest.

Journal text is interpolated once and stored with the game time. The default date is `day N, HH:MM` (day 1 at minute 0, 1440 minutes per day). `register_date_formatter` replaces that for later writes. A stored date does not change.

`await_host <screen> returns { field, ... }` is a stage statement (`docs/grammar-v1.md` section 9). It pauses the remaining entry steps. `complete_host_step` resumes them. A waiting host step is part of the save.

## Save

`runtime/save` writes schema version 1: content pack id and manifest hash, facts, deeds, social baselines and kinds, roles, quests (including frozen journal text), effect provenance, game minutes, the game seed, and every named RNG stream. 64-bit integers are 16 hex digits. The migration table is empty. A manifest hash that does not match warns in a debug build and is silent in a release. See `runtime/save/README.md` and `runtime/trace/README.md`.
