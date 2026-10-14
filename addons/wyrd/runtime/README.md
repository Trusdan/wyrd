# runtime

Engine code with no editor dependency. `wyrd_runtime.gd` is the instanceable runtime. `wyrd.gd` is the facade over one runtime. Tests construct a `WyrdRuntime` directly. The plugin does not register the autoload.

## Load

`load_content(manifest)` compiles the manifest's `.wyrd` sources with `WyrdPack.compile` and, when that reports no errors, builds a runtime-only `WyrdContent` (quests, scenes, lines, condition table, dependency index, `manifest_hash`). Any compile error refuses the load and leaves the runtime empty. Warnings do not refuse it. `export-json` stays a debug format.

Exported games must include `*.wyrd` and the manifest in the export filter. There is no import plugin in this slice.

## Facade

`configure`, `register_adapter`, `register_function`, `start_new_game`, `load_content`, and `tick` forward to the runtime. Sub-objects:

- `facts` — `set(key, value)` and `get(key)` for the world perspective, `set_in` / `get_in` when the perspective is `known/<agent>`, `invalidate(prefix)`, `subscribe(prefix)`, signal `fact_changed(key, old_value, new_value)`. Godot's `Object.set` and `Object.get` already own those names, so the store implements them with `_set` and `_get`. A perspective argument cannot be added, and `set` cannot return a bool.
- `events` — `emit(name, payload)`. The payload is kept for a later host-event schema. `emit` drops `on_event` resolver caches.
- `roles` — `assign(role, entity)` and `holder(slot_or_role)` until the role runner exists.

`believed/` and `held/` perspectives exist as empty maps and refuse writes (M5).

Dialogue text is always shown, whether or not a line is voiced. This slice does not run scenes. Audio, when it arrives, must not hide text or advance a line.

Deeds, quests, scene playback, and saves are later slices. The folders are still placeholders.
