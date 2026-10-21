# Gullhaven

Generic example village for Wyrd.

Gullhaven is a fishing village invented for Wyrd. Its people and places are not from any host game.

`content/gullhaven/` is the example pack `harbor`:

- `facts.wyrd` declares the shared facts, including one pattern and one resolved season.
- `harbor_roles.wyrd` defines the tavern owner, ferry master, storm watcher, harbor factor, harbor reeve, and dock runner.
- `ferry_toll.wyrd` is the ferry quest: live, locked, and cast slots, a deed-count start, a wait, a journal, `locked_gone`, and the six slice effects.
- `harbor_guild.wyrd` is The Harbor Guild. It starts on `asked_guild` and runs a guild-assigned factor, an elected reeve, a barred visitor, an unwilling factor, and abolish.
- `harbor_scenes.wyrd` is `toll.offer_room` (slot, entity, and narrator lines, choices, a nested `do`, and `on_abort`). After `-> scene toll.depart` the success path is `-> end`, so it does not fall into `no_room`. The choice that starts `dock_errand` also adjusts the tavern affinity baseline and assigns `dock_runner`. Another choice advances the errand.
- `dock_errand.wyrd` is a two-stage quest with `start when false`. Reaching `sent` vacates `dock_runner`.
- `harbor_storylets.wyrd` includes `harbor_gossip.storm` (`scope: topic storm_rumour`, speaker `any`). Its effect starts `dock_rumour`.
- `dock_rumour.wyrd` is the dock rumour. It starts with `start when false`, casts the tavern slot from `tavern_owner`, and runs `dock.rumour_talk`, which locks `storm_rumour`.
- `dock_crate.wyrd` is the dock crate. It starts with `start when false` and runs `dock.crate_talk`. Lifting the crate is a `strength` check. `wyrd_commands.json` lists that skill.
- `harbor_documents.wyrd` is the ferry schedule (live) and the reeve's letter (frozen). `dock_letter` starts with `start when false`, copies the letter, and shows one tavern line after `has_read`. `on_empty: wait` keeps the empty-slot lint quiet.
- `dock_scenes.wyrd` is `toll.depart`, reached with `-> scene` from the other file.
- `harbor_bell.wyrd` is the harbor bell quest.
- `harbor_gazette.wyrd` is the harbor gazette. It publishes `harbor.gazette` once a day after a one-hour delay.
- `harbor_templates.wyrd` is seven generated templates: `net_delivery` delivers a net to the harbor factor, `stolen_catch` recovers a stolen catch, `cut_line` investigates a cut mooring, `night_walk` escorts a visitor, and `tavern_stew_low`, `tavern_stew_mid`, and `tavern_stew_high` are one recurring stew favor tiered by pressure.
- `harbor.wyrdmanifest.tres` lists those files. `wyrd_commands.json` names `assign_lodging` and `post_notice`, and the skill `strength`. `playtest/harbor_election.gd` is the no-op election adapter New game registers. New game also registers the rumor policy `harbor_whisper` (kind `apprentice`, two hops, verb `whispered`).

```bash
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- check --manifest example/content/gullhaven/harbor.wyrdmanifest.tres
```

That check reports `warning[W_CLAIM]` and `info[I_STORYLET_SCORE]` and no other diagnostic. `check example/content` uses pack id `content`, so `requires: [pack.harbor]` warns and command schemas are skipped. Journal text is unquoted prose, so `{...}` interpolates. Quest titles stay quoted. Every file starts with an `[EXAMPLE CONTENT]` comment.

## Playtest

`playtest/gullhaven_playtest.tscn` is the project main scene. F5 opens a plain window: dialogue, choices, a journal dated `day N, HH:MM`, and a live fact and quest table. Toggles reach each ferry route. Voice plays a generated tone and leaves the text on screen. Save and Load use an in-memory slot and `user://playtest_save.json`. How to install Godot and walk the routes is [docs/playtest.md](../docs/playtest.md).
