# Golden tests

Golden tests snapshot the compiler. Each family is a `.wyrd` source and a JSON file written by one serializer. CI compares the JSON. It does not regenerate it.

| Family | Sources | Expected | Runner |
|---|---|---|---|
| Lexical/tree | `tests/golden/cases/*.wyrd` | `tests/golden/expected/*.json` | `tests/golden/test_goldens.gd` |
| Conditions | `tests/golden/conditions/*.wyrd` | `tests/golden/conditions/expected/*.json` | `tests/golden/test_condition_goldens.gd` |
| Statements | `tests/golden/statements/*.wyrd` | `tests/golden/statements/expected/*.json` | `tests/golden/test_statement_goldens.gd` |
| Link | `tests/golden/link/<dir>/*.wyrd` and an optional `wyrd_commands.json` | `tests/golden/link/<dir>/expected.json` | `tests/golden/test_link_goldens.gd` |
| Roles | `tests/golden/roles/*.wyrd` | `tests/golden/roles/expected/*.json` | `tests/golden/test_role_goldens.gd` |
| POT | Gullhaven manifest `example/content/gullhaven/harbor.wyrdmanifest.tres` | `tests/golden/pot/gullhaven.pot` | `tests/golden/test_pot_golden.gd` |

Regenerate every family with:

```bash
tools/update_goldens.sh
```

Review the diff before committing. The script is the only writer. CI never calls it.

`tests/golden/test_golden_inventory.gd` fails when an expected file has no source, when a diagnostic code declared in `addons/wyrd/compiler/wyrd_diagnostic.gd` appears in no expected JSON, or when a built-in in `addons/wyrd/compiler/wyrd_signatures.gd` appears in no golden source. A built-in counts when a source contains a call written as `name(`. A bare keyword does not. The allowlist is exactly:

- `E_SAVE_OPEN`, `E_SAVE_POLICY`, `E_SAVE_VERSION`, `W_SAVE_MANIFEST`, `W_SAVE_TEMPLATE`, `W_SAVE_AI`, `W_SAVE_ALIAS` (runtime and save only)
- `E_RESOLVER_INVALIDATION` (declared, never emitted)

## Determinism

- Sources live under `tests/golden/`.
- Paths in the JSON are `res://` paths only.
- No timestamps or locale-dependent text.
- Compile only: `chance` is compiled and never rolled.
- Floats appear only where the encoders already print them, on the pinned Godot (`tools/pins.env`).
- Names, keys, and diagnostics are already sorted by the runners and encoders.
- Line endings are LF (`.gitattributes`, `WyrdSource`).
- `language 1` is at the top of every file.
