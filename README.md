# Wyrd

Wyrd is a generic narrative and dialogue engine for Godot 4, written in typed GDScript. It is itself the dialogue manager. A host vendors `addons/wyrd` and implements the adapters. Facts, storylets, authored scenes, and role casting live in the addon. The host simulates the world, renders what Wyrd signals, and plays audio.

The docs are published at <https://trusdan.github.io/wyrd/>. The same pages are in `docs/`. Start at [docs/index.md](docs/index.md).

## Quick start

From a Wyrd checkout, vendor the addon, then add `res://addons/wyrd/runtime/wyrd.gd` as the autoload `Wyrd` and call `load_content` with a manifest. The full sequence, including adapters and the first scene, is the site's [quick start](https://trusdan.github.io/wyrd/#quick-start).

```bash
tools/vendor_wyrd.sh /path/to/host-project
```

## Hosts

Pin a tag and run `tools/vendor_wyrd.sh` with the host project directory (the parent of its `addons/` folder). The script copies `addons/wyrd` only. The steps are in [docs/host-checklist.md](docs/host-checklist.md). Pin a 1.x tag. A 1.x upgrade keeps the stable surface and loads 1.x saves; see [docs/stability.md](docs/stability.md).

The stable surface, the save promise, and the deprecation rules are in [docs/stability.md](docs/stability.md).

## Tests

Install that Godot so `godot` is on your `PATH`, then run `tools/run_tests.sh`. It imports the project and runs GUT.

```bash
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- check --manifest example/content/gullhaven/harbor.wyrdmanifest.tres
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- roles --manifest example/content/gullhaven/harbor.wyrdmanifest.tres
godot --headless --path . -s res://tests/bench/bench.gd -- --iterations 1000 --out res://tests/bench/out/latest.json
tools/perf_bench.sh --profile smoke --head . --mode warn --out /tmp/wyrd-perf-smoke.json
```

`tests/bench` is informational and does not gate CI. The milestone suite lives in `bench/` and `tools/perf_bench.sh`. Pull requests do not run it. Tags and a manual dispatch run the full scale and report a metric more than 20% slower or larger than the base build as a warning; benchmark runs never fail on a regression. The 07:00 UTC nightly does the same, and skips when the default branch SHA matches the last successful nightly. See `bench/README.md`.

## Example

`example/` is the Gullhaven playtest. Press F5 to run it. A walkthrough is [docs/playtest.md](docs/playtest.md). `tests/fake_host` is the scripted host. Examples use only that invented village.

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

Godot **4.7.2** stable and GUT **9.7.1** (git tag `v9.7.1`, branch `godot_4_7`) are pinned in `tools/pins.env`. The addon version is `1.0.0` (`addons/wyrd/VERSION`).

Support for 1.x is in [docs/stability.md](docs/stability.md#support).

License: [MIT](LICENSE). Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan).
