# Migration fixtures

Fixtures are generated, never edited. To change one, regenerate it at its tag and update this file.

Each file is `JSON.stringify(runtime.save_state(), "\t", true)`: tab indent, sorted keys, no trailing newline. The generator script is untracked in a detached worktree. Nothing at the tag is modified. Generation was run twice on 2026-10-23 and the two outputs were byte-identical (`cmp`). Godot was the pin below (`4.7.2.stable.official.ed1daf0bf`). GUT is pinned at every tag and is not invoked while generating.

Schema 2, 3, and 4 fixtures live in `tests/fixtures/` and are documented by `test_m8_schema3.gd` and `test_ai_cache_save.gd`.

## schema1_harbor.json

- Tag: `v0.2.0-m4` (lightweight), commit `d2dd5f420a9d6fa7a5ee77f53604981ab7eca75e`
- Pins: Godot `4.7.2-stable`, GUT `9.7.1` (`tools/pins.env` at that commit)
- Generated: 2026-10-23
- `schema_version`: 1
- Pack hash: `886d9ba3e5447ff4`
- sha256: `b35415f44ec95881d2d00e9204a783f32d905868fe13a4dab33271cd2d7f6357`

```bash
git worktree add --detach /tmp/wyrd-wt/m4 v0.2.0-m4
cd /tmp/wyrd-wt/m4
godot --headless --path . --import
# write the untracked script below as _gen_fixture.gd
godot --headless --path . -s res://_gen_fixture.gd
cp /tmp/wyrd-gen/schema1_harbor.json /tmp/wyrd-gen/twice/schema1_a.json
godot --headless --path . -s res://_gen_fixture.gd
cp /tmp/wyrd-gen/schema1_harbor.json /tmp/wyrd-gen/twice/schema1_b.json
cmp /tmp/wyrd-gen/twice/schema1_a.json /tmp/wyrd-gen/twice/schema1_b.json
```

```gdscript
extends SceneTree

func _init() -> void:
	var harness = load("res://tests/scenario/s2c_harness.gd").new()
	var opened: Dictionary = harness.open_pack(harness.HARBOR)
	var report = opened["report"]
	if not report.ok:
		push_error(report.diagnostics.format())
		quit(1)
		return
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.tick(1)
	var state: Dictionary = runtime.save_state()
	if state.is_empty():
		push_error("empty save")
		quit(1)
		return
	var text := JSON.stringify(state, "\t", true)
	var path := "/tmp/wyrd-gen/schema1_harbor.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % path)
		quit(1)
		return
	file.store_string(text)
	file.close()
	print("SCHEMA %s MINUTES %s HASH %s" % [
		state.get("schema_version"),
		state.get("minutes"),
		state.get("content", {}).get("packs", [{}])[0].get("hash", ""),
	])
	quit(0)
```

## gullhaven_v0.7.0-m9.json

- Tag: `v0.7.0-m9` (annotated), commit `fbbd24bf8d169c00a721c06216d4b92be8e9dee7`
- Pins: Godot `4.7.2-stable`, GUT `9.7.1`
- Generated: 2026-10-23
- `schema_version`: 4
- Pack hash: `8bf113c14f107242`
- sha256: `335a23408d1626b77839151d0eed066a8fa568e03ccbeae264d23addf47e7b04`
- After `tick(30)`: `ferry_toll` is `active` at stage `cross`, clock minutes 30, `player.coins` 2, journal row `j_ft_01`. `pay_toll` is already satisfied when the room is taken, so the tick advances it.

```bash
git worktree add --detach /tmp/wyrd-wt/m9 v0.7.0-m9
cd /tmp/wyrd-wt/m9
godot --headless --path . --import
# write the untracked script below as _gen_fixture.gd
godot --headless --path . -s res://_gen_fixture.gd -- /tmp/wyrd-gen/twice/m9_a.json
godot --headless --path . -s res://_gen_fixture.gd -- /tmp/wyrd-gen/twice/m9_b.json
cmp /tmp/wyrd-gen/twice/m9_a.json /tmp/wyrd-gen/twice/m9_b.json
```

## gullhaven_v0.8.0-m10.json

- Tag: `v0.8.0-m10` (annotated), commit `b63f16e7a9653e78c38c838bbaaefe66be04cf01`
- Pins: Godot `4.7.2-stable`, GUT `9.7.1`
- Generated: 2026-10-23
- `schema_version`: 4
- Pack hash: `f003b6b54c91ad8e`
- sha256: `ab7de50501d18884087757efcb78f02179b19e4072baafd765441eee8d8c669b`
- Same steps and the same resulting quest state as the v0.7.0-m9 fixture. The pack hash is this tag's Gullhaven manifest.

```bash
git worktree add --detach /tmp/wyrd-wt/m10 v0.8.0-m10
cd /tmp/wyrd-wt/m10
godot --headless --path . --import
# same untracked _gen_fixture.gd as v0.7.0-m9
godot --headless --path . -s res://_gen_fixture.gd -- /tmp/wyrd-gen/twice/m10_a.json
godot --headless --path . -s res://_gen_fixture.gd -- /tmp/wyrd-gen/twice/m10_b.json
cmp /tmp/wyrd-gen/twice/m10_a.json /tmp/wyrd-gen/twice/m10_b.json
```

The Gullhaven script, identical at both tags:

```gdscript
extends SceneTree

func _init() -> void:
	var harness = load("res://tests/scenario/s2c_harness.gd").new()
	var opened: Dictionary = harness.boot_gullhaven()
	var report = opened["report"]
	if not report.ok:
		push_error(report.diagnostics.format())
		quit(1)
		return
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.dialogue.open_scene("toll.offer_room")
	harness.line_rows(runtime)
	harness.choose_text(runtime, "Take the room")
	harness.line_rows(runtime)
	runtime.tick(30)
	if not runtime.can_save():
		push_error("scene still open")
		quit(1)
		return
	var state: Dictionary = runtime.save_state()
	var text := JSON.stringify(state, "\t", true)
	var args := OS.get_cmdline_user_args()
	var path := "/tmp/wyrd-gen/gullhaven.json"
	if args.size() > 0:
		path = str(args[0])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % path)
		quit(1)
		return
	file.store_string(text)
	file.close()
	var ferry: Dictionary = state.get("quests", {}).get("ferry_toll", {})
	var coins = state.get("facts", {}).get("world", {}).get("player.coins", null)
	print("SCHEMA %s STAGE %s STATUS %s COINS %s MINUTES %s HASH %s" % [
		state.get("schema_version"),
		ferry.get("stage"),
		ferry.get("status"),
		coins,
		state.get("minutes"),
		state.get("content", {}).get("packs", [{}])[0].get("hash", ""),
	])
	print("JOURNAL %s" % JSON.stringify(ferry.get("journal", [])))
	quit(0)
```

## tests/fixtures

Schema 2, 3, and 4 live in `tests/fixtures/`. Their sha256 values are pinned here. Nothing else about those files changes.

### schema2_harbor.json

- sha256: `8741bdc5271e36f7ff3de18e83a2f301230cf8657a931df25b23faa46182a79e`

### schema3_harbor.json

- sha256: `e960c957fec978eb529cf45c4bf8776185f118bdd711a9600865178ec81004a1`

### schema4_ai_harbor.json

- sha256: `2a44e414481e98ec04d7582c238e0330afa1aa40bc301584b5e5847470903972`
