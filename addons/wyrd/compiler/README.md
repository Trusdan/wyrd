# compiler

Lexer, block parser, fact-schema check, condition compiler, and statement compiler. No editor dependency: nothing here uses `EditorInterface` or any other editor-only API.

Pipeline for one file:

1. **Lex.** `WyrdLexer` tokenizes one UTF-8 source: two-space indent, `//` comments, `#line:` tags, quoted titles, and prose escapes.
2. **Block parse.** `WyrdParser` builds a file node, top-level `facts`, `events`, `role`, `quest`, `scene`, and `storylet` blocks, and a generic statement-line tree. A `role` block is code, like `facts`. Its fields are compiled by `WyrdStatements` into a `WyrdRoleDef`. A `storylet` block is code except for dash prose lines, and compiles to a `WyrdStoryletDef`. `wyrd check` prints each storylet's specificity as `info[I_STORYLET_SCORE]`. Ranking is runtime.
3. **Facts check.** Each `facts` entry becomes a `WyrdFact` on a `WyrdFactSchema`: type, stored or resolved, optional invalidation, and an optional trailing `doc` string. `lookup` finds a concrete key first, then a `{id}` pattern.
4. **Conditions.** `WyrdCondition` lexes, parses, type-checks, and emits one expression to a `WyrdCompiledCondition` (a flat instruction array, constants, reads, and specificity). `nearby`, `can_perceive`, and `can_reach` are `E_SPATIAL_CONTEXT` in a wait unless the caller allows them. The draft language is `docs/conditions-draft.md`. It is not frozen. `WyrdInterp` compiles the raw `{...}` spans the block lexer already kept.
5. **Statements.** `WyrdStatements` walks the quest and scene tree into plain records (`WyrdQuestDef`, `WyrdSceneDef`, `WyrdEffectDef`, and the rest under `stmt/`). Prose goes through `WyrdInterp`. The draft is `docs/statements-draft.md`. It is not frozen.
6. **Link.** `WyrdPack` merges fact schemas, then `WyrdLinker` checks cross-file quests, scenes, speakers, commands, and line ids. A slot used by a reachable stage with no `variant <slot>.empty` and no quest `on_empty` warns `W_EMPTY_UNCOVERED`. A `locked_at` slot with no reachable `locked_gone` variant warns `W_LOCKED_GONE_UNCOVERED`. A branch whose every reachable outcome is `route_closed` warns `W_ROUTE_CLOSED`. Prose that interpolates `holder(slot)` where that slot can be empty warns `W_HOLDER_UNGUARDED`, unless a `when` requires `filled(slot)` or an empty variant replaces that branch. A pair of storylets that can tie warns `W_STORYLET_TIE`. `WyrdFactXref` builds the fact cross-reference. A directory with no manifest is one pack named after the folder. `WyrdContentManifest` lists the files of a real pack.

`WyrdSource` maps a code-point offset to a line and column. `WyrdDiagnostics` formats lines as `path:line:col: error[CODE]: message`, and the same shape for `warning` and `info`.

```bash
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- check --manifest example/content/gullhaven/harbor.wyrdmanifest.tres
```

`check` compiles and links the pack. It exits 1 on an error. Warnings exit 0 unless `--strict`.
