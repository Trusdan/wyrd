# Host checklist

A host pins a Wyrd tag and vendors `addons/wyrd`. The host's own `.wyrd` content and tests stay in the host repository. Tags before 1.0 are for the host check only. Godot and GUT stay on the pins in `tools/pins.env`.

## Vendor

From a Wyrd checkout:

```bash
tools/vendor_wyrd.sh /path/to/host-project
tools/vendor_wyrd.sh /path/to/host-project <tag-or-commit>
```

`/path/to/host-project` is the directory that will contain `addons/`. The script copies `addons/wyrd` only, writes `addons/wyrd/VERSION`, and prints `git describe` for the commit it used. When that commit is an exact tag, it prints the tag too.

Run the script again to refresh `addons/wyrd`. Files the source no longer has are removed from that folder. The rest of the host project stays. The script is part of this repository. It is not inside the vendored folder. Fixes land here, then the host vendors the new pin.

## Configure

The editor plugin registers no autoload in this pin. Construct the facade in `addons/wyrd/runtime/wyrd.gd` (or a `WyrdRuntime`) and call `configure` with a `WyrdConfig`.

`WyrdConfig` holds the hour bucket, deed half-lives, axis deltas, `disposition_default`, `hostile_threshold`, and `scheduler_work_per_tick`. Fact declarations live in the host's `.wyrd` files. An optional disposition callable is `social.register_formula`. The default is `disposition_default + affinity / 2`.

## Adapters

Subclass each base directly and pass the instance to `register_adapter(base, adapter)`:

- `WyrdWorldAdapter`
- `WyrdInventoryAdapter`
- `WyrdSpatialAdapter`
- `WyrdTimeAdapter`
- `WyrdActionAdapter`
- `WyrdAIProvider` is optional. The null provider is registered by default, and a host that does not use AI does nothing.
- `Wyrd.ai.register_classifier`, `WyrdConfig.ai_banned_terms`, `WyrdConfig.ai_cache_max`, `WyrdConfig.ai_save_cache`, and `WyrdConfig.ai_max_inflight` are optional. With the null provider nothing is cached or requested.

`candidates(filter)` must honor `kind` and `tag`. An item cast asks for kind `item`.

`register_adapter` accepts a script whose parent is that base. An adapter method that stays on the stub reports an error and returns a typed fallback. Typed host functions use `register_function`.

`WyrdActionAdapter.execute` runs commands. `load_content` reads `wyrd_commands.json` beside the manifest.

Dialogue text stays on screen. `dialogue.register_line_audio` is optional and may stay unset. Audio never hides a line and never advances it. `dialogue.advance()` is the only way on.

## Load

`load_content(manifest)` compiles the manifest's `.wyrd` sources. Any error refuses the load. An exported game includes `*.wyrd` and the manifest in the export filter.

Check the pack from the host project with the pinned Godot:

```bash
godot --headless --path /path/to/host-project \
  -s res://addons/wyrd/cli/wyrd_cli.gd -- check --manifest path/to/pack.wyrdmanifest.tres
```

## Translations

Godot's own POT Generation does not read `.wyrd` files. Write a catalog from the pack, then translate it with the usual gettext tools:

```bash
godot --headless --path /path/to/host-project \
  -s res://addons/wyrd/cli/wyrd_cli.gd -- \
  pot --manifest path/to/pack.wyrdmanifest.tres --out wyrd.pot
msginit --input=wyrd.pot --locale=fr --output=wyrd.fr.po
```

Later, `msgmerge` updates `wyrd.<locale>.po` when `wyrd.pot` changes. Add each `wyrd.<locale>.po` under Project Settings → Localization → Translations, next to the game's own `.po` files. Godot loads every translation for the locale, so a Wyrd line and a game string can both resolve.

`msgctxt` is the line id. A line with no `{…}` translates from that rendered text. A line with `{…}` translates by template: the translation must keep exactly the same placeholders, in any order. Otherwise the source line shows, Godot logs a warning, and a `text_translate ok=false` trace row explains why.

## Start and load

`start_new_game(seed)` stores the seed, clears facts, deeds, roles, quests (including generated instances and their counters), RNG streams, and the trace, and sets play minutes to 0.

`load_state(data)` restores a document from `save_state()`. Load content first. `start_new_game` and `load_state` both refuse while a scene is open.

## Save

Call `can_save()` before writing a save. It is false while a scene is open. Embed the dictionary from `save_state()` in the host save and pass that same dictionary to `load_state`. One shape is `save["wyrd"]`.

The document is schema version 4. It holds the pack id, manifest hash, language version, facts, deeds, relationships, roles, quests, frozen journal text, provenance, play minutes, the seed, each named RNG stream, `flight` when a rumor, a document issue, or the scheduler still has work, and `generator` when a generated quest instance exists. 64-bit values are hex. The event log is not included. A schema 2 save loads with empty token queues and a zero slice, and the dirty waits stay armed. A schema 3 save omits `flight` when nothing is in flight, and that load clears the dirty waits. Both load on schema 4, with an empty generator when the save had no instances. An older Wyrd (0.6.x) refuses a schema 4 save. A manifest hash that differs warns in a debug build and stays quiet in a release. The load still applies. Quest signals pass an instance id `<template>#<n>` for a generated quest. See `addons/wyrd/runtime/save/README.md`. An optional `ai` key holds validated cache rows when `ai_save_cache` is true and the cache is not empty; an older loader ignores it.

## Events

When the host world changes, call `events.emit(event_name, payload)`. The payload is checked against the pack's `events` block. A mismatch is an error and leaves caches in place. A match drops `on_event` caches and re-checks dirty conditions before `emit` returns. `events.begin_batch()` and `events.end_batch()` coalesce that re-check.

## Tick

Call `tick(game_minutes)` when the host clock advances. `game_minutes` is how many minutes to add, and it is zero or greater. `tick` moves the play clock, refreshes due polls, re-checks dirty conditions up to `scheduler_work_per_tick`, and advances quests and an open scene.
