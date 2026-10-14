# Wyrd addon

Generic narrative and dialogue engine for Godot 4. This folder is what a host game copies.

Version `0.0.1` (see `VERSION`). License: MIT, copyright (c) 2026 Corey Jones (`LICENSE`).

S0 is a skeleton. S1 adds the compiler and the linker. S2a loads a manifest into a runtime fact store and evaluates conditions. The editor plugin registers nothing. Adapter methods are stubs except where a host or the fake host overrides them. `runtime/rng` has the seeded RNG wrapper and the stable hash. The command-line entry is `cli/wyrd_cli.gd`. `check` compiles and links a pack. `test` stays unimplemented.

Examples in the repository use only the invented village Gullhaven.
