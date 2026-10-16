# save

`WyrdSave.capture` / `apply` implement `WyrdRuntime.save_state` and `load_state`.

Schema version is 2. `WyrdSave.migrations` has one step. It fills `facts.believed` and `facts.held` when a schema 1 save is missing them. A version below 1, or a version this table cannot reach, is `E_SAVE_VERSION`. Load content first.

The document holds pack id and manifest hash, language version, world, known, believed, and held facts, the deed log, relationship baselines and kinds, role bindings, definitions, frozen casts, and told sets, quest status, stage, outcomes, slots, host-step fields, frozen journal rows, and region leaves when a stage has them, effect provenance, play minutes, the game seed, and each named RNG stream's `to_state()`. `sequences`, when present, holds partial or finished sequence rows (`count`, `done`, and `started` or `matched` when set). A missing `sequences` key clears that bag only. An unknown sequence id is kept. Believed and held bags are sparse: an agent or group appears only when it has keys. `storylets`, when present, holds line-set draw rows and director `seen` / `last_minute`. `bark_speakers`, when present, holds bark speaker clocks (`cooldown` and `last_minute`). A missing `bark_speakers` key clears those clocks and leaves storylet rows. `why-not` reads those bags and does not add a key. An id the pack does not declare is kept and ignored. An unknown speaker id is kept.

64-bit values are lowercase hex so `JSON.stringify` does not round them. Other integers are coerced back to int on load. A scene must be closed. A hash mismatch adds `W_SAVE_MANIFEST` when `OS.is_debug_build()` is true and stays silent in a release. The load still applies.
