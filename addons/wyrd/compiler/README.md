# compiler

Lexer, block parser, fact-schema check, condition compiler, and statement compiler. No editor dependency: nothing here uses `EditorInterface` or any other editor-only API.

Pipeline for one file:

1. **Lex.** `WyrdLexer` tokenizes one UTF-8 source: two-space indent, `//` comments, `#line:` tags, quoted titles, and prose escapes.
2. **Block parse.** `WyrdParser` builds a file node, top-level `facts`, `quest`, and `scene` blocks, and a generic statement-line tree.
3. **Facts check.** Each `facts` entry becomes a `WyrdFact` on a `WyrdFactSchema`: type, stored or resolved, optional invalidation, and an optional trailing `doc` string. `lookup` finds a concrete key first, then a `{id}` pattern.
4. **Conditions.** `WyrdCondition` lexes, parses, type-checks, and emits one expression to a `WyrdCompiledCondition` (a flat instruction array, constants, reads, and specificity). The draft language is `docs/conditions-draft.md`. It is not frozen. `WyrdInterp` compiles the raw `{...}` spans the block lexer already kept.
5. **Statements.** `WyrdStatements` walks the quest and scene tree into plain records (`WyrdQuestDef`, `WyrdSceneDef`, `WyrdEffectDef`, and the rest under `stmt/`). Prose goes through `WyrdInterp`. The draft is `docs/statements-draft.md`. It is not frozen. Linking across files is PR 5.

`WyrdSource` maps a code-point offset to a line and column. `WyrdDiagnostics` formats errors as `path:line:col: error[CODE]: message`.

The CLI runs steps 1–5:

```bash
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- check example/content
```

`check` compiles one file. It does not link files, tag lines, or export JSON.
