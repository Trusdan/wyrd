# Wyrd

Wyrd is a generic narrative and dialogue engine for Godot 4, written in typed GDScript. It is itself the dialogue manager. A host vendors `addons/wyrd` and implements the adapters.

This repository is the S0 skeleton: no compiler, runtime, or editor tools yet. There is no support guarantee before 1.0.

Godot **4.7.2** stable and GUT **9.7.1** (git tag `v9.7.1`, branch `godot_4_7`) are pinned in `tools/pins.env`. The addon version is `0.0.1` (`addons/wyrd/VERSION`).

## Tests

Install that Godot so `godot` is on your `PATH`, then run `tools/run_tests.sh`. It imports the project and runs GUT.

```bash
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd
godot --headless --path . -s res://tests/bench/bench.gd -- --iterations 1000 --out res://tests/bench/out/latest.json
```

`addons/wyrd` is the folder a host copies. `example/` is the Gullhaven placeholder. `tests/fake_host` is the scripted host. The grammar draft is `docs/grammar-v1.md`. Examples use only that invented village. See `docs/CONTRIBUTING.md`.

License: [MIT](LICENSE). Copyright (c) 2026 Corey Jones.
