# rng

`WyrdRng` is an in-script PCG32 (XSH-RR 64/32). For a given seed and stream, the full sequence, `stream_id`, `for_decision`, and `to_state` stay the same across Godot versions. Wyrd never uses Godot's built-in generator.

`WyrdHash` is FNV-1a 64, including `combine`. Godot's `hash()` is not used.

S2 saves each named stream's `to_state()`. This package does not register streams or wire `Wyrd.save_state()` yet.
