# Statement language (draft, not frozen)

Status: draft. This is not part of grammar v1. Sections 1–6 of `docs/grammar-v1.md` stay frozen. Condition semantics stay as in `docs/conditions-draft.md`. Corey approved the open choices below on 2026-10-14.

## Choices

1. A missing `#line:` id is an error now. The hint is `run tag-lines (S1d)`. Example content carries hand-written ids.
2. Choice labels need `#line:` ids. A choice with no label does not.
3. The only quest-level slot-state default is `on_empty:`.
4. A line condition is a `when <cond>:` prefix: `when <cond>: <speaker>: <prose> #line:<id>`.
5. `disabled_when {<cond>} "<reason>"` sits after the choice label. It is parsed only.
6. `record deed` also accepts `visibility:` and `memorable:`.
7. The six slice effects plus `believe`, `unbelieve`, `declare`, `retract`, `learn`, and `forget` are compiled. Any other effect is `E_EFFECT_NOT_IN_SLICE`.
8. Journal text is unquoted prose after a colon: `journal: text #line:<id>`. `{...}` interpolates. A quoted string is not journal text. Quest titles stay quoted and are not interpolated.
9. The separate S1b-perf pass is not part of this draft. It landed as its own change before linking.

## Quest

```wyrd
quest <id> "<Title>"
  slot <name> = <role> mode: live
  slot <name> = <role> mode: locked_at(<stage>)
  slot <name> = <role> mode: cast(<condition>)
  on_empty: wait
  requires: [pack.<id>, ...]
  start when <condition>
  stage <id>
    waits_until <condition>
    journal: <prose> #line:<id>
    scene <scene_id> with <slot>, <slot>
    -> <stage_id>
    -> <stage_id> when <condition>
    ~ <effect>
    outcome <branch> = done
    variant <slot>.<state>:
      redirect beat <beat> to <slot>
```

`cast(<condition>)` picks once at quest start. In that condition `candidate` is the entity being tested. A constant condition warns `W_SLOT_COND_ALWAYS` or `W_SLOT_COND_NEVER`. `requires` and `redirect beat` are parsed only.

A role id is a symbol (`ferry_master`). A role and a slot have no title or display field. `{holder(slot).name}` is the holder's personal name. A readable job title in example text is ordinary prose.

`start when`, `waits_until`, `cast`, `-> ... when`, and the conditions on `unwilling` and `barred` use `wait_trigger_or_eligibility`. `unwilling(<cond>)` and `barred(<cond>)` use that context because they gate a slot state.

Slot states: `default`, `successor`, `empty`, `contested`, `hostile`, `unwilling(<cond>)`, `barred(<cond>)`, `locked_gone`. Precedence is `locked_gone`, `contested`, `empty`, then `barred`, `hostile`, `unwilling`, `successor`, and `default`. The first state that applies and has a declared variant wins. A higher state with no variant falls through. `contested` is the exception: no `contested` variant uses the `empty` variant, and the state stays `contested`. `unwilling` tests the holder as `$h`. `$` plus a name is one identifier. `$h` outside an `unwilling` condition is an error, and a lone `$` is an unexpected token. `barred` tests the player. Both are live, and a fact invalidation re-checks them on the next tick when no scene or host step is open. A scene ending finishes the current stage body before that re-check. `locked_gone` is a frozen `locked_at` holder who was vacated or is not alive, even when the role has a successor. The slot holder stays that person. A quest resolution logs one `slot_state` line (`quest`, `role`, `slot`, `state`, `reason`). `WyrdTrace.prefix` keeps a line when the quest, role, or slot starts with that text.

## Scene

```wyrd
scene <id>
  on_abort:
    ~ <effect>
  <speaker>: <prose> #line:<id>
  when <cond>: <speaker>: <prose> #line:<id>
  * [<label>] -> <target> #line:<id>
  * {<condition>} [<label>] -> <target> #line:<id>
    ~ <effect>
  - (<label>)
  -> <label>
  -> end
  -> scene <id>
```

A speaker is a slot name, an entity id (`name` or `name.name`), or `narrator`. The linker checks slot speakers against every quest stage that runs the scene. A slot speaker that stage does not pass is `E_SPEAKER_UNBOUND`. A scene no quest runs is `W_SCENE_UNUSED`, and its speakers are not checked.

Line conditions and choice conditions use `storylet_or_choice`. The first depth-zero `: <speaker> :` ends a line condition, so a ternary colon inside that condition needs parentheses: `when (a ? b : c): ferry: ...`.

`disabled_when` stores the condition text and the quoted reason. The reason is not interpolated. `on_fail -> <target>` may sit on a `do` effect or on the following line. Inside a scene, that target is a label or `end`. A stage-level `on_fail` target must name a stage of that quest, or the linker reports `E_STAGE_UNKNOWN`.

`-> end` leaves the scene. `-> scene <id>` calls a sub-scene. The target must be a scene in the pack, or the linker reports `E_SCENE_UNKNOWN`.

## Storylet

```wyrd
storylet <id>
  scope: topic <id>
  scope: bark
  scope: event <name>
  scope: beat <quest>.<stage>
  speaker: <slot, entity, or any>
  when: <condition>
  priority: <int>
  weight: <int>
  cooldown: <duration>
  - <prose> #line:<id>
  lines:
    - <prose> #line:<id>
  -> scene <id>
```

A storylet has one body: one prose line, a `lines:` set, or `-> scene <id>`. Field order is free. `when` uses `storylet_or_choice`, so `chance` is allowed. An omitted `when` scores 0 and is generic. `when: true` scores 1 and is not generic. `wyrd check` prints `info[I_STORYLET_SCORE]` with the specificity, the priority, and `generic=true` or `generic=false`.

`priority` defaults to 0 and may be negative. `weight` defaults to 1. `0` is allowed. A negative weight is `E_STORYLET_SYNTAX`. `cooldown` defaults to 0 minutes. It is a duration (`m`, `h`, or `d`, with a day of 1440 minutes) and is stored, not enforced. A duplicate id is `E_STORYLET_DUPLICATE`. A `-> scene` target the pack does not declare is `E_SCENE_UNKNOWN`. An `event` scope the pack does not declare is `E_EVENT_UNKNOWN`. A `topic` scope and a `beat` scope are stored and not checked against topics or quests.

`speaker: any` stores the speaker id `any`. This slice does not treat it as a wildcard, and it does not rank storylets. A line set is drawn by `WyrdStoryletDeck` on the runtime: one seeded shuffle per cycle, no repeat until the set is exhausted, then a new cycle. That order, cursor, and cycle are saved under `storylets` on schema 2 and omitted when no set has been drawn. A single line and a scene body write no row. The storylet `when` is not added to the tick queue.

## Effects

| Form | Notes |
|---|---|
| `~ set <fact> = <expr>` | The fact must be stored. `{id}` patterns use `WyrdFactSchema.lookup`. |
| `~ inc <fact> by <expr>` | The fact and the value are `int` or `float`. `int` widens to `float`. |
| `~ record deed <verb>(...)` | Named arguments. `actor` is required. Optional: `target`, `place`, `tags`, `magnitude`, `witnesses`, `visibility`, `memorable`, `reveals`, `claim`, `statement`. |
| `~ unlock topic <id>` | Parsed and stored. |
| `~ do <command>(...)` | Arguments are type-checked. The linker checks the name against `wyrd_commands.json` beside the manifest. A missing file skips that check with `I_COMMANDS_SKIPPED` when a `do` exists. |
| `~ outcome <branch> = route_closed \| done \| failed` | Also accepted without the `~` inside a stage. |
| `~ believe <agent> <fact> = <expr>` | Stored schema fact only. `<agent>` is a dotted id. |
| `~ unbelieve <agent> <fact>` | Removes that agent's belief. A missing belief is a no-op. |
| `~ learn <agent> <fact> = <expr>` | Writes `known/<agent>`. Does not change `world`, `believed`, or `held`. |
| `~ forget <agent> <fact>` | Removes that agent's knowledge. A missing key is a no-op. |
| `~ declare <group> <fact> = <expr>` | Stored schema fact only. `<group>` is a dotted id. |
| `~ retract <group> <fact>` | Removes that group's held fact. A missing fact is a no-op. |

`witnesses` is `auto` or a set. A `do` argument that is only a name path is an entity id when lookup misses, and a fact read when lookup hits. Any other argument is an expression.

`believe`, `declare`, `retract`, `learn`, and `forget` are reserved words. They are legal only as the effect verb immediately after `~`. As an identifier they stay `E_RESERVED_WORD`. `unbelieve` is not reserved.

`reveals` names a stored fact and `claim` is the value. A witness in mode `saw` learns it (`known/`). `heard` and `inferred` believe it (`believed/`). Nobody else receives it. There is no rumour spread. A missing witness list writes nothing. `perceived(agent, verb)` reads the latest mode.

`statement: true` is a statement deed (WFR4). Perception modes are still stored, but the mode does not write the fact. Each witness is a listener. The speaker is not added. The listener accepts when `credibility_score(listener, speaker) >= credibility_threshold`. The default score is `disposition(listener, speaker) / 100`. `WyrdConfig.credibility_threshold` defaults to `0.5` and the comparison is inclusive. `register_credibility` replaces that score and is not saved. The game seed is not an input. Acceptance writes `believed/<listener>` only. Rejection writes nothing. `known/`, `world`, and `held/` stay unchanged. One `credibility` line is logged per listener, including a rejection, even when the belief value does not change. `statement: false`, or a deed with no `statement` argument, keeps the perception write above. A statement with no `reveals` records the deed and makes no credibility decision. `deeds.record` does not run this gate.

`lock topic`, `start quest`, `advance`, `assign role`, `vacate role`, `adjust baseline`, and `create document` are `E_EFFECT_NOT_IN_SLICE`. `set_disposition` is `E_NO_SET_DISPOSITION` with the message `record deeds or use adjust baseline (§2.5)`.

## `#line:`

Every spoken line, journal entry, and choice label needs a `#line:` id. A missing id is `E_LINE_ID_MISSING`. A duplicate id in one file is `E_LINE_ID_DUPLICATE`. The same id in two files of one pack is also `E_LINE_ID_DUPLICATE`, and the message names both files. `tag-lines` writes a missing id and never changes one that is already there.

Each line record keeps its id, speaker, tags, and scene. This slice has no tag syntax, so `tags` is empty. Journal entries leave `scene_id` empty.

## Reads

Every record keeps the union of fact keys read by its conditions, effect expressions, and prose, including keys on nested records. `and` / `or` short-circuit arms are included, as in the condition draft.

## Diagnostics

| Code | When |
|---|---|
| `E_SLOT_DUPLICATE` | A slot name is repeated in one quest |
| `E_STAGE_DUPLICATE` | A stage id is repeated in one quest |
| `E_SLOT_UNKNOWN` | `variant` or `with` names a slot this quest does not declare |
| `E_SLOT_STATE` | The variant state is not one of the eight names, or its condition shape is wrong |
| `E_LOCKED_AT_STAGE` | `locked_at` names a stage this quest does not declare |
| `E_STAGE_UNKNOWN` | `->` names a stage this quest does not declare |
| `E_STMT_UNKNOWN` | The statement is not part of this draft, or its shape is wrong |
| `E_LABEL_UNKNOWN` | A divert, choice, or scene `on_fail` names a label that is not in the scene |
| `E_LABEL_DUPLICATE` | A label is repeated in one scene |
| `E_CHOICE_SYNTAX` | A choice line is not one of the forms above |
| `E_SPEAKER_SHAPE` | A speaker is not a dotted identifier |
| `E_WRITE_RESOLVED` | `set`, `inc`, or a belief effect targets a resolved fact |
| `E_WRITE_TYPE` | A write value does not match the stored fact, or `inc` is not numeric |
| `E_EFFECT_NOT_IN_SLICE` | The effect is outside the slice and belief forms, or the outcome value is not one of the three |
| `E_NO_SET_DISPOSITION` | The effect is `set_disposition` |
| `E_LINE_ID_MISSING` | A spoken line, journal entry, or choice label has no `#line:` |
| `E_LINE_ID_DUPLICATE` | The same `#line:` id appears twice in one file |
| `E_ARG_NAME` | A deed argument is unknown, positional, or duplicated, or a command argument name is duplicated |
| `E_ARG_TYPE` | A deed argument is missing or has the wrong type |

Existing condition codes (`E_CHANCE_CONTEXT`, `E_RESOLVER_INVALIDATION`, `E_UNKNOWN_FACT`, and the rest) still apply when an expression is compiled.

## Linking

Still draft. `check` links a pack after statements. A directory with no manifest is one pack named after the folder. `--manifest` loads a `WyrdContentManifest` (`pack_id`, `files`, `language_version`). Files are linked in sorted path order. Diagnostics are sorted by file, line, column, then code. `check` exits 1 on an error. Warnings still exit 0 unless `--strict`. Info does not fail `--strict`.

`requires: [pack.<id>]` warns with `W_PACK_UNKNOWN` when the id is not this pack. Topics from `unlock topic` are collected and are not errors. `on_event(...)` names are recorded as plain symbols. There is no event schema here.

`export-json` writes a debug document (`wyrd_export` 1) with a per-file content hash. It is not the runtime load format. `facts` prints the cross-reference. `tag-lines` is the only command that edits source.

| Code | When |
|---|---|
| `E_FACT_REDECLARED` | The same key or an overlapping pattern is declared in another file |
| `E_QUEST_DUPLICATE` | The same quest id is declared in another file |
| `E_SCENE_DUPLICATE` | The same scene id is declared in another file |
| `E_SCENE_UNKNOWN` | `scene <id>` or `-> scene <id>` names a scene that is not in the pack |
| `E_SPEAKER_UNBOUND` | A slot speaker is not passed by a stage that runs the scene |
| `E_COMMAND_UNKNOWN` | `do` names a command missing from `wyrd_commands.json` |
| `E_COMMANDS_FILE` | `wyrd_commands.json` is present and is not a command list |
| `E_LINE_ID_DUPLICATE` | The same `#line:` id appears twice in the pack |
| `E_STAGE_UNKNOWN` | A stage `on_fail` names a stage this quest does not declare |
| `W_SCENE_UNUSED` | No quest stage runs the scene |
| `W_SLOT_UNUSED` | A passed slot is not a speaker in the scene |
| `W_EMPTY_UNCOVERED` | A slot used by a reachable stage has neither `variant <slot>.empty` nor quest `on_empty`. A `contested` variant does not cover it |
| `W_LOCKED_GONE_UNCOVERED` | A `locked_at` slot has no `locked_gone` variant on a reachable stage |
| `W_SLOT_COND_ALWAYS` | An `unwilling` or `barred` condition is always true |
| `W_SLOT_COND_NEVER` | An `unwilling` or `barred` condition is never true |
| `W_ROUTE_CLOSED` | Every reachable assignment of a branch is `route_closed` |
| `W_PACK_UNKNOWN` | `requires` names a pack that is not loaded |
| `W_FACT_NEVER_READ` | A stored fact is written and never read |
| `W_FACT_NEVER_SET` | A stored fact is read and never written |
| `W_FACT_UNUSED` | A fact is never read or written |
| `W_INTERP_UNSET` | Prose interpolates a stored fact's world value that no earlier write sets. A `belief`, `believes`, `held`, `knows`, or `known` key is not that world value |
| `W_HOLDER_UNGUARDED` | Prose interpolates `holder(slot)` where that slot can be empty. A guard is a `when` that requires `filled(slot)`, or an `empty` variant that replaces the branch |
| `W_STALE_BELIEF` | A scene `learn` writes `known/<agent>` while a contradicting `believe` of that agent and key remains and no `unbelieve` clears it |
| `W_CLAIM` | Prose interpolates `belief`, `believes`, or `held`. The value is a claim |
| `E_FACT_LEAK` | Prose interpolates a stored fact's world value, and a `when` or `{if}` reads that fact from the world without `knows` or `known` |
| `I_COMMANDS_SKIPPED` | A `do` exists and no command file was loaded |

Resolved facts are never "never set". A `record deed` without `reveals` is not a fact write. A passed slot the scene does not speak is `W_SLOT_UNUSED`.

## Stage `on`

A stage may handle a declared world event. The form is `on <event> where <condition>:` followed by nested `~` effects and `->` transitions. `event.<field>` is a readonly binding in that condition and in those nested expressions. It is not a stored fact. Storylet `on`, and `on` outside a stage, are `E_STMT_UNKNOWN`. The event schema, payload check, and runtime are in `docs/events-draft.md`.

## Host-modal step

`await_host` is approved (Corey, 2026-10-14). See `docs/grammar-v1.md` section 9. It is a stage statement: `await_host <screen_id> returns { <field>, ... }`. The word is still not a legal identifier. The runtime pauses the remaining entry steps, calls `request_host_step`, emits `host_step_requested`, and resumes on `complete_host_step`.

## Role

A top-level `role <id>` block is content. It sits beside `facts`, `events`, `quest`, and `scene`. The id is a dotted identifier. A role has no title. Fields are optional. A missing field uses the default below. The same fields can be passed to `WyrdRoles.define`.

```wyrd
role ferry_master
  scope: place(gullhaven)
  eligibility: alive(candidate) and has_tag(candidate, local)
  default_holder: ada
  visibility: public
  succession: relation(apprentice|kin)
  vacancy: hold
```

| Field | Values | Default |
|---|---|---|
| `scope` | `world`, `place(<id>)`, `faction(<id>)` | `world` |
| `eligibility` | A condition. `candidate` is the entity under test | Every entity passes |
| `default_holder` | An entity id | None |
| `visibility` | `public`, `secret` | `public` |
| `succession` | `none`, `relation(<kind>\|<kind>)`, `faction_assigns(<id>)`, `election`, `host_decides` | `none` |
| `vacancy` | `hold`, `abolish` | `hold` |

`eligibility` uses `wait_trigger_or_eligibility`, so `chance` is `E_CHANCE_CONTEXT` and a `per_query` resolved fact is `E_WAIT_RESOLVER_MODE`. In that condition the bare name `candidate` is the entity being tested, not a fact. `WyrdRoles.eligible(role, entity)` evaluates it. One trace line is recorded when a condition is present: `eligible` with `role`, `entity`, and `ok`. The line does not list the facts the condition read.

`relation`, `faction_assigns`, `host_decides`, and `election` run on `vacate`. `relation` requires the candidate to be alive, eligible, and a different entity. `faction_assigns` picks from `WyrdWorldAdapter.members`, ordered by a registered `faction_rank` (higher wins) and a seeded tie-break. `host_decides` and `election` leave the role `contested` until `assign`. `election` emits `election_needed` and calls `WyrdElectionAdapter.start_election`. `vacancy: abolish` runs when the strategy finds nobody. A `default_holder` is assigned when that role's binding is empty, including after `start_new_game`.

| Code | When |
|---|---|
| `E_ROLE_SYNTAX` | The role header or a field value is the wrong shape |
| `E_ROLE_DUPLICATE` | The same role id is declared twice |

## Not in this draft

Role definitions are compiled from a `role` block. `unwilling`, `barred`, `locked_gone`, and `contested` resolve at play time. `outcome <branch> = route_closed` keeps the quest open, and `outcome(quest, branch)` reads it. `faction_assigns`, `host_decides`, `election`, and `vacancy: abolish` run. `cast(<condition>)` asks `WyrdWorldAdapter.candidates` once when the quest starts, keeps the ids the condition accepts, and freezes a seeded pick. No survivor leaves the slot `empty`. The freeze is saved with the other slot locks. One `cast` line is logged. `wyrd roles` prints a sorted table of every role (holder, status, strategy, pending or abolished, frozen slots). `--prefix` keeps ids that start with that text. Resolving `redirect beat` stays later. Storylets, topics as entities, barks, and `priority:` are M6. Storylet `on` waits for that work. `test` stays unimplemented.
