# Contributing to Wyrd

Wyrd is a generic narrative engine. Pull requests are small, typed, and tested. Corey reviews them.

## Generic only

Do not put a host game's names, lore, places, factions, or spoilers in code, comments, tests, docs, commit messages, or pull request text.

The only example setting is Gullhaven, a fishing village invented for this repo. Its people and places belong to no game. If a sentence only makes sense for one host, it belongs in that host's repo, not here.

CI greps the pull request diff against a private deny-list. The list is the repository secret `WYRD_HYGIENE_DENYLIST`. The check skips with a warning when the secret is unset, and it never prints the list or the matched text.

## Coding

- GDScript is statically typed: variables, parameters, and return types.
- Engine classes use the `Wyrd` prefix (`WyrdRuntime`, `WyrdRng`).
- Put logic in plain `RefCounted` classes. `plugin.gd` and anything under `editor/` stay thin, because the editor is hard to test.
- No C#, no .NET, and no native extensions.
- Unfinished API is marked `@experimental` in the doc comment. The stable surface is frozen for 1.0: the facade calls and signals, adapter bases, `WyrdConfig`, the `language` version, and the value types named in [docs/stability.md](stability.md). From 1.0.0 those change only in add-only ways in 1.x. Everything else stays `@experimental`. See [docs/stability.md](stability.md).
- Version with SemVer. `0.x` lasts until 1.0. The addon version is the single line in `addons/wyrd/VERSION`.
- Commits use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).
- A behavior change arrives with a GUT test. Golden snapshots live under `tests/golden/`. See `tests/golden/README.md`.

Godot and GUT versions are pinned in `tools/pins.env`. An upgrade is its own pull request. `WyrdRng` sequences do not depend on the Godot version.

## Tests

```bash
tools/run_tests.sh
```

Grammar snapshots live in `tools/vscode-wyrd/tests/snap/`. From `tools/vscode-wyrd/`, `npx vscode-tmgrammar-snap 'tests/snap/*.wyrd'` checks them and `npx vscode-tmgrammar-snap -u 'tests/snap/*.wyrd'` updates them.

Details are in the repository `README.md`.

## How to read a Wyrd PR

1. Read the description first: files touched, the pinned Godot and GUT versions, how to run the tests, and anything deferred.
2. Read the tests next. They are the contract. A runtime or compiler change should be visible in a test without a tour of the engine.
3. `addons/wyrd/runtime` is the engine. If a change puts logic in `plugin.gd` or `editor/`, ask for it to move to a plain class.
4. A grammar change updates `docs/grammar-v1.md` and names the open choices. Do not treat an example in that doc as a parser.
5. Example prose belongs in `example/` or in docs, and it stays in Gullhaven.
6. Skip `addons/gut` unless the pull request is a planned GUT upgrade. That tree is vendored.
7. CI imports the project, runs GUT, runs the benchmark as information only, and runs the content-hygiene check. A red hygiene step means a deny-listed term is in the diff. The log will not show the term.

## Recorded rule for later milestones

Dialogue text is always displayed. A line's words are presented whether or not the line has audio. Audio is optional and plays on top of the text. Audio never hides text, and audio never advances a line. Advancing is the player's input. A scene does not wait on audio merely because a clip exists.

S0 does not implement scenes or audio. The rule is recorded here so the slice runtime does not skip text or auto-advance when audio is missing.

## License

MIT. Copyright (c) 2026 Corey Patrick Jones (github.com/Trusdan). See the repository `LICENSE`.
