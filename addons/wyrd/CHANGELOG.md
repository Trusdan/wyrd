# Changelog

## Unreleased

S2 slice runtime. S2 exit met. Draft. Saves, replay, `await_host`, and the Gullhaven playtest scene are in this slice. See `docs/playtest.md`.

- `save_state` / `load_state` round-trip facts, deeds, roles, quests, journal text, and every named RNG stream. Schema version 1. Hex for 64-bit values. No save while a scene is open.
- `WyrdTrace` records and replays inputs. A changed host answer is visible in the diff.
- `await_host` is parsed and pauses the remaining entry steps until `complete_host_step`.

S2c quest runner, scene runner, and the six slice effects. Draft.

- The six slice effects run at play time, including `do` failure divert and outcome signals.
- Quest stages, waits, variants, outcomes, and a frozen journal. Default date `day N, HH:MM`.
- Scene playback keeps text on screen with or without `line_audio`. `can_save()` is false while a scene is open.
- Host-modal step is `request_host_step` / `complete_host_step`. The statement form is approved in S2d.

S2b deeds, disposition, and roles. Draft. Quests, scenes, and saves are later slices.

- Deed log stores packed rows, decays by the hour bucket, and keeps memorable rows. No compaction.
- `deed_count` and `deed_score` replace the zero stub. Sums round to 6 decimal places.
- Relationship baselines plus a verb-to-axis table. Default disposition is `disposition_default + affinity / 2`. Hostile is that disposition toward `player` below `hostile_threshold` (default 20).
- `live` follows the role. `locked_at` freezes when the stage is entered. `cast` binds once at quest start and logs that casting is M4.
- Succession is `relation(kind|kind)` or `none`. Secret holders are written to `known/<agent>` only through `tell`.
- Linker warning `W_EMPTY_UNCOVERED` when a slot has no empty variant and no `on_empty`.
- Linker warning `W_HOLDER_UNGUARDED` when prose interpolates `holder(slot)` and that slot can be empty without `filled(slot)` or an empty variant on that branch.

S2a runtime core and fact store. Draft. Deeds, quests, scenes, and saves are later slices.

- `load_content` compiles a manifest's `.wyrd` sources into a runtime `WyrdContent` and refuses the load on any error.
- Fact store: stored types, `world` and `known/<agent>`, resolver cache (`on_event`, `poll`, `per_query`), `fact_changed` for subscribed prefixes.
- `tick` advances game minutes, refreshes due polls, and re-checks dirty conditions up to `scheduler_work_per_tick`.
- A concrete key under a `{id}` pattern still loads that key. `reads` stays the pattern.

PCG32 swap: `WyrdRng` is now an in-script PCG32 (XSH-RR 64/32) with streams, per-decision seeding and saveable state; sequences no longer depend on the Godot version. Seeded bench fixtures were regenerated.

- New `tag-lines` ids follow this sequence. An id already written on a line is not rewritten.

S1d slice compiler, part 4 of 4: linking and the pack CLI. Draft, not frozen (`docs/statements-draft.md`). S1 exit met.

- `check` links a pack: merged facts, quests, scenes, speakers, commands, line ids, and the fact cross-reference.
- `WyrdContentManifest` plus optional `wyrd_commands.json`. A directory with no manifest is one pack named after the folder.
- `tag-lines`, `export-json`, and `facts`. `export-json` is a debug document, not the runtime load format. `test` stays unimplemented.
- Gullhaven is a four-file slice. `check --manifest` on `harbor.wyrdmanifest.tres` is clean.

S1b-perf: dependency index, dirty-set benchmark, and the condition-evaluator speed pass. Draft, not a CI gate (`docs/spikes/s0-condition-speed.md`).

- `WyrdDepIndex` maps exact keys and `{id}` patterns to condition indexes. A pattern depends on the whole key. The index is rebuilt from `reads` and is never saved.
- The seeded 10k-fact / 5k-condition bench times dirty-set ticks at 1, 10, and 100 changed facts. Incremental results must match a full scan. Timings stay informational.
- `WyrdRpnEval` lives in `runtime/conditions`. `tests/support/wyrd_rpn_eval.gd` is a thin shim. Saved opcodes are unchanged.
- The measured speed pass kept fact-slot loads, frequency-ordered dispatch, and load-time superinstructions. A fixed stack, hoisting consts, and an inlined jump pop were slower or not reliable, and were dropped. Numbers are in the spike doc.

S1c slice compiler, part 3 of 4: statements and effects. Draft, not frozen (`docs/statements-draft.md`).

- Quest, stage, slot, variant, scene, line, choice, and effect records, compiled from the block tree.
- Slice effects: `set`, `inc`, `record deed`, `unlock topic`, `do`, and `outcome`. Stored facts only.
- `#line:` required on spoken lines, journal entries, and choice labels.
- `check` runs the single-file pipeline through statements. Linking, `tag-lines`, and `export-json` stay in PR 5. The S1b-perf pass is a separate change.

S1b slice compiler, part 2 of 4: condition language. Draft, not frozen (`docs/conditions-draft.md`).

- Expression lexer, parser, type checker, and flat instruction emit, including prose interpolation spans.
- `WyrdFactSchema.lookup` and a signature registry (belief names registered and marked M5).
- Specificity, fact reads (including short-circuit arms), and a test-only stack walker.
- 10k-fact / 5k-condition benchmark recorded beside the placeholder runner. Not a CI gate.
- S1b left quest and scene statements uncompiled. Linking, `tag-lines`, and `export-json` stayed for later.

S1a slice compiler, part 1 of 4: lexer, block parser, diagnostics, and parse-level `check`.

- Lexical and block rules from grammar v1 sections 1–6, with golden cases for each rule.
- `facts` entries are parsed into a `WyrdFactSchema` (stored, resolved, invalidation, and a trailing `doc` string).
- CLI `check` prints `path:line:col: error[CODE]: message` and exits 1 when a file has errors.
- Gullhaven example `example/content/gullhaven/ferry_toll.wyrd`.
- Conditions, quest and scene statement semantics, linking, `tag-lines`, and `export-json` stay later.
- Grammar v1 §4 example corrected so source `{{two coins}` displays as `{two coins}`. Quoted titles are never interpolated, and a trailing `//` comment may follow `language 1`. Example corrected and clarifications approved by Corey, 2026-10-14.

## 0.0.1 - 2026-10-14

S0 skeleton. No runtime features yet.

- Godot project layout, editor-plugin stub, and versioned runtime facade.
- Typed adapter stubs, a seeded RNG wrapper, and a stable hash.
- Fake host, GUT 9.7.1, a placeholder benchmark runner, and CI.
- Grammar v1: lexical and block rules approved (Corey, 2026-10-14) and frozen. Quest, scene, and facts examples stay illustrations.
