# Spike: in-editor syntax highlighting

Status: plan only. `plugin.gd` registers nothing, and `tools/vscode-wyrd/` is a placeholder.

## Question

Can Godot 4.7 color a `.wyrd` file in the built-in text editor with `EditorSyntaxHighlighter`?

## Plan

1. Read the 4.7 `EditorSyntaxHighlighter` API and note how a highlighter is attached to a `CodeEdit`.
2. On a throwaway branch, register one highlighter from the Wyrd plugin for buffers whose path ends in `.wyrd`.
3. Color only the frozen lexical set from `docs/grammar-v1.md`: `//` comments, double-quoted titles (including `\"` and `\\`), `#line:` tags, the `language` header, and the reserved words `document`, `publishes_by`, `tier`, `await_host`, `believe`, `declare`, and `retract`.
4. Type a comment in a buffer and check that the color changes without a restart. Then reload the file and check that the highlighter is still attached.
5. Leave the VS Code grammar unwritten until this result is known. A TextMate grammar must follow the frozen lexical rules and must not invent the statement syntax. Quest, scene, and facts forms are still illustrations.

## Open questions

- Does `EditorSyntaxHighlighter` run for a non-script file opened from the FileSystem dock, or only for GDScript?
- If it does not, is a `CodeEdit` inside the future Wyrd dock the path that actually works?
- How much of the statement grammar has to be frozen before a highlighter is worth keeping?
- Once a lexer exists, should the highlighter and the compiler share it, so the colors cannot drift from the parser?
