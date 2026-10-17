# Changelog

## Unreleased

- A `document` block publishes a frozen issue on the `publish` queue. `deeds_known_to(group, since, filter)` lists deeds a current group member witnessed or believes through a rumor. `saw` counts as `known:`. `heard`, `inferred`, and a rumor believer count as `believed:`. The believer index stores the adoption minute, and `since` uses that minute for the listener. It is rebuilt from the optional `believers` field on each deed row in the schema 2 deeds bag. A plain `believed/` write is not indexed. Compaction moves those listeners onto the newest merged id and drops them with a dropped row. The issue claim prefers a matching fragment slant, then the lowest member's `believed:` value, then `known:`, then the world fact. A mutated belief is that `believed:` value. The deed row stays. After a jump, one visit enqueues at most `publish_catchup_max` missed issues per document, oldest first. The default is 3. Issues past the cap are numbered and stored as `skip <id>#<n> due=<minute>` lines in the document fact, so they are never published later. A save and a load publish the same later issues as a run that did not save. Queued publish tokens are not saved. Load drops them and does not log `wyrd publish`. With tracing on, one `wyrd publish` line is logged per frozen issue. A skip line is not logged.
- A registered `WyrdRumorPolicy` may list `mutations`. Each accepted hop, and each accepted aggregate materialize, rolls `keep_chance_fn` with the rumor hash and either keeps the claim, replaces it, or drops it. The listener stores that copy in `believed/<listener>`. The next hop offers the copy. The deed row, `known:`, and `world:` stay unchanged. There is no `.wyrd` syntax for a policy. The copies are not saved. Schema stays 2. Load drops them and does not continue the chain. With tracing on, each mutation logs `wyrd rumor mutate`. Load does not log it.
- A deed in a coarse place stores a reach level for that deed and place. `WyrdConfig.rumor_coarse_minutes` (default 60) raises it by one rumor unit per crossed game hour. `belief` and `believes` roll that level once for the asked NPC and, on accept, write `believed/<listener>`. A reject is also once. Precise hops are unchanged. Reach rows and the once-set are not saved. Schema stays 2. Load drops them and does not continue. With tracing on, a rise logs `wyrd rumor reach` and a draw logs `wyrd rumor materialize`. Load does not log them.
- A deed with a reveal claim can spread along the relationship kinds in a registered `WyrdRumorPolicy`. One rumor unit offers that deed to one listener. The offer is a seeded roll per deed, speaker, listener, and hop. Adoption uses the credibility threshold and writes `believed/<listener>` only. A `saw` witness still learns through the reveal path. `known:` and `world:` stay unchanged. A coarse deed place does not start a precise hop, and a listener in a coarse place does not adopt one. The in-flight claim table and rumor tokens are not saved. Schema stays 2. Load drops them and does not continue the spread. With tracing on, a hop logs `wyrd rumor hop` and an offer logs `wyrd rumor adopt`. Load does not log them.
- Axes, disposition, reputation, and `path_exists` share one cache for the current time bucket. A read stores a missing entry. `set_cache(false)` recomputes and does not store, and those results match. A relationship, deed, membership, formula, config, or time-bucket change drops the entries. Each dropped entry is one `cache_refresh` unit. `path_exists(a, b, kinds, max_hops)` is a directed search; a step may use any listed kind. The cache is not saved. Schema stays 2. With tracing on, one `wyrd social cache` line is logged for an invalidation, a miss, or a hit. Load does not log one. A full-scale affinity and disposition matrix for 500 NPCs is 21,207,500 bytes by the key-text model.
- `Wyrd.tick` accepts any non-negative slice and runs whole game ticks of `scheduler_tick_minutes` (default 1). A zero slice still runs one tick and does not move the clock. One scheduler spends `scheduler_work_per_tick` units across waits, rumor, publish, and cache refresh. Shares are 40, 12, 8, and 4. Unused share moves to the earliest queue that still has work. Unfinished items stay in order. A debug build can log `wyrd scheduler queue=frame` when a tick's units exceed `scheduler_frame_warn_usec` (default 2000 microseconds, 2 ms; 0 disables it). The line does not change the work. The queues and the leftover slice are not saved. Schema stays 2.
- Deed rows are indexed by witness and by hour bucket. A witness is the knower of that deed, and `saw`, `heard`, and `inferred` share one list. Snapshot deed, social, and precedence reads use the indexes. A prefix visits only names that can start the row key. Precedence reads the name lists and does not walk every deed. The rows match a full scan. The indexes are not saved. Schema stays 2.
- Storylet queries read a link-time index of sorted ids per scope kind, scope id, and speaker, plus a bucket for speaker `any`. The winners match a full scan. A bark query still runs inside the call. The index is not saved. Schema stays 2.
- The proposed `memory.peak` warning budget is 384 MiB, sized for an 8 GB laptop. It still warns only.
- The scale bench times director query, why-not, storylet tie-lint, a full debug snapshot, a filtered snapshot page, a single-section facts page, and the same query with coverage counting on. Budgets warn.
- `Wyrd.debug.snapshot` builds only the requested sections. The prefix filter runs while those rows are collected, and the kept rows are sorted and paged as before. Social rows and precedence agents read deed witness names without building a full deed row.

## 0.5.0-m7 - 2026-10-16

M7 inspector data, choices, coverage, and the console. `VERSION` is `0.5.0-m7`. `plugin.cfg` version is `0.5.0-m7`. Corey cuts the tag `v0.5.0-m7` after the milestone benchmark. Save schema is 2.

- `wyrd console <pack>` runs the playtest commands: set a fact, kill or vacate or replace a role holder, advance time, fire an event, and run a scene in a text UI. Every command records source `console` and, when tracing is on, one `wyrd console` line. A direct `set` stores provenance scene `console`. Release exports exclude `addons/wyrd/runtime/console/*`. `--out` writes the JSON save after those commands when every command succeeded. An open scene refuses that write.
- `Wyrd.coverage` counts storylet draws, slot-variant entries, and shown line ids. Recording is off until `enabled` is set, including in a release build. Counts stay out of saves. `merge` adds them to `user://wyrd_coverage.json`. `wyrd coverage` lists never-hit ids by file:line. One `coverage` line is logged per hit when tracing is on, and one `coverage_report` line per report.
- `Wyrd.facts.choice_summary` lists stored-fact writes from the provenance map. It filters by scene, choice, key prefix, and an inclusive time range. `wyrd choices` prints that table. A concrete stored fact may say `recap: true`. Deed compaction drops other provenance and keeps those rows. One `choice_summary` line is logged for a read when tracing is on, and one `choice_compact` line when compaction drops rows.
- `Wyrd.debug.snapshot(sections)` reads live facts, role bindings and history, quest stages with waiting reasons, the dirty condition set, deeds with decayed weights, social axes and disposition, belief and group precedence, and fact provenance. The document is built on demand and is not saved. A prefix and a page window filter each section. One `wyrd debug snapshot` line is logged when tracing is on. Load does not log it.
- Gullhaven marks `ferry.toll_coins` with `recap: true`. A headless test kills each Gullhaven role holder with `wyrd console --cmd` and checks the example quest. The ferry lock re-routes through `ferry.locked_gone`.

## 0.4.0-m6 - 2026-10-16

M6 director and reactivity. `VERSION` is `0.4.0-m6`. Corey cuts the tag `v0.4.0-m6`. Save schema is 2.

- Storylet queries, bark clocks, quest regions, sequences, voiced lines, and secrecy tiers.
- `wyrd why-not` takes `--tiers` and `--secrecy-fact`. `wyrd storylets` lists storylets. `wyrd cooldowns` lists clocks.
- `WyrdConfig.trace_director` logs one `director_candidate` line per scope-and-speaker match when tracing is on. Load does not log it.

## 0.3.0-m5 - 2026-10-16

M5 deeds and social. `VERSION` is `0.3.0-m5`. Corey cuts the tag. Save schema is 2.

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

M4 roles and casting. `VERSION` is `0.2.0-m4`. Corey cuts the tag. Save schema stays 1.

- `wyrd roles` prints a sorted table of every role: holder, status, strategy, pending or abolished, and frozen slots. `--prefix` keeps ids that start with that text. `--save` loads a JSON save first. The same table is `WyrdRoles.render_table`.
- Gullhaven adds the harbor guild: a guild-assigned factor, an elected reeve, a barred visitor, an unwilling factor, abolish when the guild has no successor, and a `locked_gone` variant on the ferry lock. The lookout cast slot stays.
- The Gullhaven acceptance matrix kills, replaces, or vacates every role holder at every stage, checks the fallback, and save/loads back to the same state.
- `cast(<condition>)` picks once at quest start from `WyrdWorldAdapter.candidates`, keeps the entities the condition accepts, and freezes a seeded pick. No candidate leaves the slot `empty`. The freeze is saved on the existing roles blob. One filterable `cast` line is logged. A constant cast condition uses the existing always/never slot warning.
- Slot states `unwilling($h)`, `barred`, `locked_gone`, and `contested` resolve live. Precedence is `locked_gone`, `contested`, `empty`, then `barred`, `hostile`, `unwilling`, `successor`, and `default`, and the first covered variant wins. `outcome = route_closed` keeps the quest open and is readable with `outcome(quest, branch)`. Coverage warns for a used slot with no `empty` variant, a `locked_at` slot with no `locked_gone` variant, a constant `unwilling` or `barred` condition, and a branch whose every reachable route closes. A quest resolution logs one filterable `slot_state` line.
- A `role <id>` block compiles `scope`, `eligibility`, `default_holder`, `visibility`, `succession`, and `vacancy`. `roles.define()` stores the same definition. `eligible(role, entity)` tests `candidate`. `relation` succession also requires eligibility. `faction_assigns` picks a living eligible member by `faction_rank` and a seeded tie-break. `host_decides` and `election` stay `contested` until `assign`. `election` emits `election_needed` and calls `WyrdElectionAdapter.start_election`. `vacancy: abolish` runs when a strategy finds nobody.
- Slot state `contested` sits after `locked_gone` and before `empty`. A missing `contested` variant uses the `empty` variant and the state stays `contested`. A `contested` variant does not cover the empty lint.
- `line_ready` carries the speaker entity and the role ids they hold in that scene. A successor records `role_changed` and is never the departed holder. Each succession step logs one filterable `succession` line.

## 0.1.0-s3 - 2026-10-15

WFR13 host world events. A pack declares an `events` block. `Wyrd.events.emit` type-checks the payload, drops `on_event` caches (a pattern key drops every concrete cache), and re-checks dirty conditions before it returns. `begin_batch` / `end_batch` coalesce that re-check. A missing invalidate mode on a resolved fact is `E_RESOLVER_NO_INVALIDATE`. A wait that reads a resolved fact with an empty or `per_query` mode is `E_WAIT_RESOLVER_MODE`. The event log is not part of `save_state`. See `docs/events-draft.md`.

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
