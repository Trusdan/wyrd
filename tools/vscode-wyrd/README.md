# vscode-wyrd

A local VS Code extension that colors `.wyrd` files and matches `check` diagnostics. It is not published.

The TextMate grammar is a draft. It follows the lexer and parser on `main`, not only the frozen lexical set in `docs/grammar-v1.md`. Snapshot tests under `tests/snap/` record every scope.

## What it contributes

- A language for `.wyrd` (`source.wyrd`).
- The `$wyrd` problem matcher, which reads today's `check` lines (`path:line:col: severity[CODE]: message`) unchanged.
- The setting `wyrd.godotPath` (default `godot`), the Godot 4.7 executable the tasks run.

There is no JavaScript, no activation event, and no build step. Packaging with vsce is only a smoke test.

## Install

The VS Code workspace folder must be the Godot project root, the folder that contains `project.godot`. Click-through from a problem uses that folder.

Two local routes:

1. Symlink this folder into the per-user extensions directory, then restart VS Code.

   ```bash
   ln -s "$PWD/tools/vscode-wyrd" ~/.vscode/extensions/wyrd-local.wyrd-0.1.0
   ```

   On Windows the same unpacked folder goes under `%USERPROFILE%\.vscode\extensions`.

2. Build a VSIX and install it. From `tools/vscode-wyrd/`:

   ```bash
   npx @vscode/vsce package
   code --install-extension wyrd.vsix
   ```

   Or use Extensions: Install from VSIX… and pick `wyrd.vsix`.

## Tasks

`.vscode/tasks.json` in this repo is the same file as `tasks.sample.json`. It runs Gullhaven `check`, example-content `check`, and `tag-lines` (dry run and write) through `wyrd.godotPath`.

To use the tasks in another project, copy `tasks.sample.json` to that project's `.vscode/tasks.json` and change the manifest path in the arguments.

## Snapshots

From `tools/vscode-wyrd/`:

```bash
npx vscode-tmgrammar-snap 'tests/snap/*.wyrd'
npx vscode-tmgrammar-snap -u 'tests/snap/*.wyrd'
```

The first command fails when a scope changes. The second rewrites the `.snap` files.
