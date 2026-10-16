# Changelog

## Unreleased

- A host event may name witnesses and leave a world fact. `saw` learns that fact, and `heard` or `inferred` believes it. `witnesses: auto` asks the spatial adapter. `leaves: <fact> = <value> decays <minutes>` writes the fact and clears it on a later tick. The deadline is saved on schema 2. One `event_witness` line and one `evidence` line are logged. `addons/wyrd/VERSION` stays `0.3.0-m5`.
- The 07:00 UTC nightly performance run skips when the default branch SHA matches the last successful scheduled run. Pull requests no longer run `perf-smoke`. Tag and manual runs still use the full scale and the 20% gate.
- A seeded Gullhaven scale pack and a same-job performance bench. Tags, the nightly run, and a manual dispatch run the full scale and fail a metric that is more than 20% slower or larger than the base build in that job. Absolute budgets warn until they are confirmed. The tag run commits `bench/results/<tag>.json` and regenerates `bench/TREND.md`.
- Deed axes walk the actor index. Reputation, belief lookup, and call-name dirty marks are cached and dropped when the underlying rows, beliefs, membership, or config change. A pure quest start is considered when its recheck becomes true. Save schema stays 2: deed export omits fields the loader already defaults. `addons/wyrd/VERSION` stays `0.3.0-m5`.

## 0.3.0-m5 - 2026-10-16

M5 deeds and social. `addons/wyrd/VERSION` is `0.3.0-m5`. Corey cuts the tag. Save schema is 2.

- Gullhaven's toll tale: the harbor council declares the toll lost at sea, a fisher believes it was stolen, and `dock_hand` inherits that council line. The council member is unwilling while that belief is the official line, and barred while the player believes it was stolen. One witness hears the tale through a wall. One statement fails credibility. The role × belief matrix writes and retracts each of those conditions.
- `W_STALE_BELIEF` warns when a scene `learn` writes `known/<agent>` and that agent still has a contradicting `believed/` value that no `unbelieve` clears.
- Player-visible text may interpolate `belief`, `believes`, and `held`. That interpolation warns `W_CLAIM`. Interpolating a stored fact's world value while a gate reads that fact from the world, and the gate does not also `knows` it, is `E_FACT_LEAK`.
- Save schema is 2. A schema 1 save gains empty `facts.believed` and `facts.held` bags. New saves write those bags sparse, one map per agent or group.
- `~ believe <agent> <fact> = <expr>`, `~ unbelieve <agent> <fact>`, `~ declare <group> <fact> = <expr>`, and `~ retract <group> <fact>` write schema stored facts. A resolved fact is `E_WRITE_RESOLVED`. A type mismatch is `E_WRITE_TYPE`. A belief write does not change `world` or `known`. One `belief` trace line is logged when a value changes.
- `knows(agent, key)` reads a role reveal or `known/<agent>`. `known` is the same read and warns `W_KNOWN_DEPRECATED`. `believes(agent, key)` is truthy of the agent's belief, then each group's `held` value in `groups_of` order. An explicit false stops the walk. `belief(agent, key)` and `believes(...) == v` read the value. `held(group, key)` reads that group only. None of them fall back to `known` or `world`. `register_group_precedence` replaces the membership order. `invalidate_groups`, or emitting `groups_changed`, drops the cache and wakes conditions that read `group.membership`. A lookup logs one `belief_lookup` line. `unwilling`, `barred`, eligibility, and `cast` may call these, and a belief write re-checks slot state on the next tick.
- `conflicted(agent, key)` is the WFR9 group-position check. The M4 slot state stays `contested`. It is true when two of the agent's groups hold different present values. Absence is not a position. Explicit false is. The agent's own belief, `known:`, and `world:` are not positions. `believes` still follows precedence. One `conflict` trace line is logged per resolution.
- `~ learn <agent> <fact> = <expr>` and `~ forget <agent> <fact>` write `known/<agent>`. A resolved fact is `E_WRITE_RESOLVED`. A type mismatch is `E_WRITE_TYPE`. Learning does not change `world` or a belief, and it does not clear one. One `knowledge` line is logged when the value changes. A role reveal logs the same line.
- A deed witness stores a perception mode, `saw`, `heard`, or `inferred`, from `WyrdSpatialAdapter.perceive`. The default is `saw`. `reveals` and `claim` write that stored fact for each witness: `saw` learns it, and `heard` or `inferred` believes it. Other agents are not copied. `perceived(agent, verb)` returns the latest mode. One `perception` line is logged per witness.
- `statement: true` on `record deed` is a statement deed. Perception modes are still stored, and the mode does not write the fact. Each witness is a listener. The default score is `disposition(listener, speaker) / 100`, and the listener accepts when that score is at least `credibility_threshold` (default 0.5). `register_credibility` replaces the score and is not saved. Acceptance writes `believed/<listener>` only. One `credibility` line is logged per listener, including a rejection.
- A kind the observer holds toward the subject multiplies that axis's deed delta by `WyrdConfig.kind_scale`. Several kinds multiply. The baseline is not scaled. `reputation(subject, group)` is the mean disposition of the group's members toward the subject. The subject is excluded. The value is derived, not saved. One `reputation` line is logged per call.
- `deeds.compact` merges rows that share a minute and the same witnesses, and drops weight that has rounded to zero without moving `perceived`. Scores stay within that rounding. `deed_count` may fall. `compact_after` of 0 does not compact on tick. One `compact` line is logged per call.

## 0.2.0-m4 - 2026-10-15

M4 roles and casting. `addons/wyrd/VERSION` is `0.2.0-m4`. Corey cuts the tag. Save schema stays 1.

- `wyrd roles` prints a sorted table of every role: holder, status, strategy, pending or abolished, and frozen slots. `--prefix` keeps ids that start with that text. `--save` loads a JSON save first. The same table is `WyrdRoles.render_table`.
- Gullhaven adds the harbor guild: a guild-assigned factor, an elected reeve, a barred visitor, an unwilling factor, abolish when the guild has no successor, and a `locked_gone` variant on the ferry lock. The lookout cast slot stays.
- The Gullhaven acceptance matrix kills, replaces, or vacates every role holder at every stage, checks the fallback, and save/loads back to the same state.
- `cast(<condition>)` picks once at quest start from `WyrdWorldAdapter.candidates`, keeps the entities the condition accepts, and freezes a seeded pick. No candidate leaves the slot `empty`. The freeze is saved on the existing roles blob. One filterable `cast` line is logged. A constant cast condition uses the existing always/never slot warning.
- Slot states `unwilling($h)`, `barred`, `locked_gone`, and `contested` resolve live. Precedence is `locked_gone`, `contested`, `empty`, then `barred`, `hostile`, `unwilling`, `successor`, and `default`, and the first covered variant wins. `outcome = route_closed` keeps the quest open and is readable with `outcome(quest, branch)`. Coverage warns for a used slot with no `empty` variant, a `locked_at` slot with no `locked_gone` variant, a constant `unwilling` or `barred` condition, and a branch whose every reachable route closes. A quest resolution logs one filterable `slot_state` line.
- A `role <id>` block compiles `scope`, `eligibility`, `default_holder`, `visibility`, `succession`, and `vacancy`. `roles.define()` stores the same definition. `eligible(role, entity)` tests `candidate`. `relation` succession also requires eligibility. `faction_assigns` picks a living eligible member by `faction_rank` and a seeded tie-break. `host_decides` and `election` stay `contested` until `assign`. `election` emits `election_needed` and calls `WyrdElectionAdapter.start_election`. `vacancy: abolish` runs when a strategy finds nobody.
- Slot state `contested` sits after `locked_gone` and before `empty`. A missing `contested` variant uses the `empty` variant and the state stays `contested`. A `contested` variant does not cover the empty lint.
- `line_ready` carries the speaker entity and the role ids they hold in that scene. A successor records `role_changed` and is never the departed holder. Each succession step logs one filterable `succession` line.

## 0.1.0-s3 - 2026-10-15

Packaging for a host pin. `tools/vendor_wyrd.sh` copies `addons/wyrd` and writes `VERSION`. See `docs/host-checklist.md`. Tags before 1.0 are for the host check only.

WFR13 host world events. A pack declares an `events` block. `Wyrd.events.emit` type-checks the payload, drops `on_event` caches (a pattern key drops every concrete cache), and re-checks dirty conditions before it returns. `begin_batch` / `end_batch` coalesce that re-check. A missing invalidate mode on a resolved fact is `E_RESOLVER_NO_INVALIDATE`. A wait that reads a resolved fact with an empty or `per_query` mode is `E_WAIT_RESOLVER_MODE`. The event log is not part of `save_state`. See `docs/events-draft.md`.

S2 slice runtime. S2 exit met: a save loads back to the same state, a recorded trace replays the same decisions, and the Gullhaven playtest scene is the project main scene (`docs/playtest.md`).

- `save_state` / `load_state` store schema version 1, language version, pack ids and manifest hashes, facts, the deed log, relationship baselines and kinds, role bindings and history, quest status, stage, outcomes, slot locks, and frozen journal text, plus every named RNG stream. 64-bit values are hex. A save during an open scene is refused. A hash mismatch warns in a debug build and is silent in a release. The migration table is empty.
- `WyrdTrace` records host answers and Wyrd decisions. Replaying the inputs on a fresh runtime reproduces the decisions. A changed host answer shows up in the diff.
- `await_host <screen_id> returns { <field>, ... }` is approved and parsed. It pauses the remaining stage-entry steps until `complete_host_step`.

S2c quest runner, scene runner, and the six slice effects.

- `set`, `inc`, `record deed`, `unlock topic`, `do` / `on_fail`, and `outcome` run at play time. Provenance stores scene, choice, and game minutes.
- Quest statuses include unavailable when `requires` names another pack. `start when` and `waits_until` advance only after a dirty re-check. A stage offers a scene; the host opens it. An aborted scene stays pending.
- A quest completes when every declared outcome is resolved and the current body has no transition. A `failed` outcome fails the quest.
- Journal text and its date freeze at the write. The default date is `day N, HH:MM` from game minutes. A host may register another formatter.
- Dialogue text is always on screen. `line_audio` may be null. Audio does not hide a line or advance it. `advance()` is the only way on. `can_save()` is false while a scene is open.
- `request_host_step` / `complete_host_step` are the runtime API a host step uses. The statement form is approved in S2d.

S2a runtime core and fact store. The Gullhaven manifest loads into a runtime, facts and conditions evaluate against the fake host, and a dirty re-check matches a full scan. Deeds, quests, scenes, and saves are later slices.

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
