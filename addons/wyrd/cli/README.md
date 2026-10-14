# cli

`wyrd_cli.gd` is the command-line entry. With no arguments it prints the addon version and the command list. The text and the exit status come from `WyrdCli`, so tests can call it without starting another process.

```bash
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- check <file-or-dir>
```

`check` lexes and parses every `.wyrd` file and prints diagnostics. It exits 0 when there are no errors and 1 when there are. `test`, `tag-lines`, and `export-json` print `not implemented`.
