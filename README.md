# Wyrd

Wyrd is a generic narrative and dialogue engine for Godot 4, written in typed GDScript. It is itself the dialogue manager. A host vendors `addons/wyrd` and implements the adapters.

This repository is the S0 skeleton through the M5 deed and social runtime, plus typed host world events. Condition and statement drafts are not frozen. `check --manifest` compiles and links a pack. `WyrdRuntime.load_content` compiles that manifest again at runtime. `save_state` / `load_state` round-trip a closed scene, and a recorded trace replays the same decisions. Press F5 to run the Gullhaven playtest. A walkthrough for someone without a Godot setup is [docs/playtest.md](docs/playtest.md). There is no support guarantee before 1.0.

Godot **4.7.2** stable and GUT **9.7.1** (git tag `v9.7.1`, branch `godot_4_7`) are pinned in `tools/pins.env`. The addon version is `0.6.4-m3` (`addons/wyrd/VERSION`).

## Hosts

Pin a tag and run `tools/vendor_wyrd.sh` with the host project directory (the parent of its `addons/` folder). The script copies `addons/wyrd` only. The steps are in [docs/host-checklist.md](docs/host-checklist.md). Tags before 1.0 are for the host check only.

## Tests

Install that Godot so `godot` is on your `PATH`, then run `tools/run_tests.sh`. It imports the project and runs GUT.

```bash
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- check --manifest example/content/gullhaven/harbor.wyrdmanifest.tres
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- roles --manifest example/content/gullhaven/harbor.wyrdmanifest.tres
godot --headless --path . -s res://tests/bench/bench.gd -- --iterations 1000 --out res://tests/bench/out/latest.json
tools/perf_bench.sh --profile smoke --head . --mode warn --out /tmp/wyrd-perf-smoke.json
```

`tests/bench` is informational and does not gate CI. The milestone suite lives in `bench/` and `tools/perf_bench.sh`. Pull requests do not run it. Tags and a manual dispatch run the full scale and apply the 20% regression gate. The 07:00 UTC nightly does the same, and skips when the default branch SHA matches the last successful nightly. See `bench/README.md`.

`addons/wyrd` is the folder a host copies. `example/` is the Gullhaven placeholder. `tests/fake_host` is the scripted host. The grammar draft is `docs/grammar-v1.md`. Examples use only that invented village. See `docs/CONTRIBUTING.md`.

License: [MIT](LICENSE). Copyright (c) 2026 Corey Jones.
