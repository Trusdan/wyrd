# Spike: in-editor syntax highlighting

Status: Closed 2026-10-19: no in-Godot highlighter; M3 uses a VS Code TextMate grammar and the CLI.

## Question

Can Godot 4.7 color a `.wyrd` file in the built-in text editor with `EditorSyntaxHighlighter`?

## Plan

Kept as history. Step 5 is superseded: the grammar follows the implemented lexer and parser, with snapshot tests. It does not wait on a frozen statement grammar.

1. Read the 4.7 `EditorSyntaxHighlighter` API and note how a highlighter is attached to a `CodeEdit`.
2. On a throwaway branch, register one highlighter from the Wyrd plugin for buffers whose path ends in `.wyrd`.
3. Color only the frozen lexical set from `docs/grammar-v1.md`: `//` comments, double-quoted titles (including `\"` and `\\`), `#line:` tags, the `language` header, and the reserved words `document`, `publishes_by`, `tier`, `await_host`, `believe`, `declare`, and `retract`.
4. Type a comment in a buffer and check that the color changes without a restart. Then reload the file and check that the highlighter is still attached.
5. Leave the VS Code grammar unwritten until this result is known. A TextMate grammar must follow the frozen lexical rules and must not invent the statement syntax. Quest, scene, and facts forms are still illustrations.

## Open questions

- Does `EditorSyntaxHighlighter` run for a non-script file opened from the FileSystem dock, or only for GDScript? Only by a per-file pick, so this was not pursued.
- If it does not, is a `CodeEdit` inside the future Wyrd dock the path that actually works? A dock editor is possible, and it would mean building an editor, which is not planned.
- How much of the statement grammar has to be frozen before a highlighter is worth keeping? The VS Code grammar tracks the implementation. Snapshots guard it.
- Once a lexer exists, should the highlighter and the compiler share it, so the colors cannot drift from the parser? TextMate cannot run the GDScript lexer. The keyword parity test and the snapshots guard drift.

## Findings

1. An `EditorImportPlugin` for `.wyrd` would make the editor open it in the Inspector, not the text editor. The editor tries `ResourceLoader` first (godot PR #53025, "The system favours the ResourceLoader"), and `TextFile` isn't exposed to scripts.
2. `EditorSyntaxHighlighter` has no association by file extension; a user picks it per file (godot-proposals discussion #11195).
3. Godot 4.7 can't generate POT files headless (godot PR #98422 is still open), so Wyrd's POT comes from the CLI (a later PR).
