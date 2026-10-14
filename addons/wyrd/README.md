# Wyrd addon

Generic narrative and dialogue engine for Godot 4. This folder is what a host game copies.

Version `0.0.1` (see `VERSION`). License: MIT, copyright (c) 2026 Corey Jones (`LICENSE`).

S0 is a skeleton, and S1a adds the compiler front end under `compiler/`. The editor plugin registers nothing. Adapter methods are stubs. `runtime/rng` has the seeded RNG wrapper and the stable hash. The command-line entry is `cli/wyrd_cli.gd`; `check` parses `.wyrd` files.

Examples in the repository use only the invented village Gullhaven.
