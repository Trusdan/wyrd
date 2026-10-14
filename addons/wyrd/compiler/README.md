# compiler

Lexer, block parser, and fact-schema check. No editor dependency: nothing here uses `EditorInterface` or any other editor-only API.

Pipeline for this slice:

1. **Lex.** `WyrdLexer` tokenizes one UTF-8 source: two-space indent, `//` comments, `#line:` tags, quoted titles, and prose escapes.
2. **Block parse.** `WyrdParser` builds a file node, top-level `facts`, `quest`, and `scene` blocks, and a generic statement-line tree. Quest and scene statements are not interpreted yet.
3. **Facts check.** Each `facts` entry becomes a `WyrdFact` on a `WyrdFactSchema`: type, stored or resolved, optional invalidation, and an optional trailing `doc` string.

`WyrdSource` maps a code-point offset to a line and column. `WyrdDiagnostics` formats errors as `path:line:col: error[CODE]: message`.

The CLI runs this pipeline:

```bash
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- check example/content
```

Next: conditions (PR 3).
