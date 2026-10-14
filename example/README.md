# Gullhaven

Generic example village for Wyrd.

Gullhaven is a fishing village invented for Wyrd. Its people and places are not from any host game.

`content/gullhaven/` is the S1 slice, pack `harbor`:

- `facts.wyrd` declares the shared facts, including one pattern and one resolved season.
- `ferry_toll.wyrd` is the quest: live, locked, and cast slots, a deed-count start, a wait, a journal, a variant, and the six slice effects.
- `harbor_scenes.wyrd` is `toll.offer_room` (slot, entity, and narrator lines, choices, a nested `do`, and `on_abort`). After `-> scene toll.depart` the success path is `-> end`, so it does not fall into `no_room`.
- `dock_scenes.wyrd` is `toll.depart`, reached with `-> scene` from the other file.
- `harbor.wyrdmanifest.tres` lists those files. `wyrd_commands.json` names `assign_lodging` and `post_notice`.

```bash
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- check --manifest example/content/gullhaven/harbor.wyrdmanifest.tres
```

That check is empty. `check example/content` uses pack id `content`, so `requires: [pack.harbor]` warns and command schemas are skipped. Journal text is unquoted prose, so `{...}` interpolates. Quest titles stay quoted. Every file starts with an `[EXAMPLE CONTENT]` comment.
