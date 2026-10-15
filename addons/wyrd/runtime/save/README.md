# save

`WyrdSave.capture` / `apply` implement `WyrdRuntime.save_state` and `load_state`.

Schema version is 1. `WyrdSave.migrations` is an empty list of callables, one step per older version. A version below 1, or a version this table cannot reach, is `E_SAVE_VERSION`. Load content first.

The document holds pack id and manifest hash, language version, world and known facts, the deed log, relationship baselines and kinds, role bindings, definitions, frozen casts, and told sets, quest status, stage, outcomes, slots, host-step fields, and frozen journal rows, effect provenance, play minutes, the game seed, and each named RNG stream's `to_state()`. Believed and held facts must be empty.

64-bit values are lowercase hex so `JSON.stringify` does not round them. Other integers are coerced back to int on load. A scene must be closed. A hash mismatch adds `W_SAVE_MANIFEST` when `OS.is_debug_build()` is true and stays silent in a release. The load still applies.
