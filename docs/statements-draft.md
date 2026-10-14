# Statement language (draft, not frozen)

Status: draft. This is not part of grammar v1. Sections 1–6 of `docs/grammar-v1.md` stay frozen. Condition semantics stay as in `docs/conditions-draft.md`. Corey approved the open choices below on 2026-10-14.

## Choices

1. A missing `#line:` id is an error now. The hint is `run tag-lines (S1d)`. Example content carries hand-written ids.
2. Choice labels need `#line:` ids. A choice with no label does not.
3. The only quest-level slot-state default is `on_empty:`.
4. A line condition is a `when <cond>:` prefix: `when <cond>: <speaker>: <prose> #line:<id>`.
5. `disabled_when {<cond>} "<reason>"` sits after the choice label. It is parsed only.
6. `record deed` also accepts `visibility:` and `memorable:`.
7. Only the six slice effects are compiled. Any other effect is `E_EFFECT_NOT_IN_SLICE`.
8. Journal text is unquoted prose after a colon: `journal: text #line:<id>`. `{...}` interpolates. A quoted string is not journal text. Quest titles stay quoted and are not interpolated.
9. The separate S1b-perf pass is not part of this draft. It lands after this work and before PR 5.

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

`cast(<condition>)` is type-checked only. Casting arrives in M4. `requires` and `redirect beat` are parsed only.

`start when`, `waits_until`, `cast`, `-> ... when`, and the conditions on `unwilling` and `barred` use `wait_trigger_or_eligibility`. `unwilling(<cond>)` and `barred(<cond>)` use that context because they gate a slot state.

Slot states: `default`, `successor`, `empty`, `hostile`, `unwilling(<cond>)`, `barred(<cond>)`, `locked_gone`. The slice runtime handles the first four.

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

A speaker is a slot name, an entity id (`name` or `name.name`), or `narrator`. Whether a slot speaker is bound by the quests that run the scene is a PR 5 link check.

Line conditions and choice conditions use `storylet_or_choice`. The first depth-zero `: <speaker> :` ends a line condition, so a ternary colon inside that condition needs parentheses: `when (a ? b : c): ferry: ...`.

`disabled_when` stores the condition text and the quoted reason. The reason is not interpolated. `on_fail -> <target>` may sit on a `do` effect or on the following line. Inside a scene, that target is a label or `end`. A stage-level `on_fail` target is stored and not resolved.

`-> end` leaves the scene. `-> scene <id>` calls a sub-scene. The target scene is not required to exist in this file.

## Effects

| Form | Notes |
|---|---|
| `~ set <fact> = <expr>` | The fact must be stored. `{id}` patterns use `WyrdFactSchema.lookup`. |
| `~ inc <fact> by <expr>` | The fact and the value are `int` or `float`. `int` widens to `float`. |
| `~ record deed <verb>(...)` | Named arguments. `actor` is required. Optional: `target`, `place`, `tags`, `magnitude`, `witnesses`, `visibility`, `memorable`. |
| `~ unlock topic <id>` | Parsed and stored. |
| `~ do <command>(...)` | Arguments are type-checked. The host command schema is a PR 5 link check. |
| `~ outcome <branch> = route_closed \| done \| failed` | Also accepted without the `~` inside a stage. |

`witnesses` is `auto` or a set. A `do` argument that is only a name path is an entity id when lookup misses, and a fact read when lookup hits. Any other argument is an expression.

`lock topic`, `start quest`, `advance`, `assign role`, `vacate role`, `adjust baseline`, and `create document` are `E_EFFECT_NOT_IN_SLICE`. `set_disposition` is `E_NO_SET_DISPOSITION` with the message `record deeds or use adjust baseline (§2.5)`.

## `#line:`

Every spoken line, journal entry, and choice label needs a `#line:` id. A missing id is `E_LINE_ID_MISSING`. A duplicate id in one file is `E_LINE_ID_DUPLICATE`. Cross-file duplicates are a PR 5 check.

Each line record keeps its id, speaker, tags, and scene. This slice has no tag syntax, so `tags` is empty. Journal entries leave `scene_id` empty.

## Reads

Every record keeps the union of fact keys read by its conditions, effect expressions, and prose, including keys on nested records. `and` / `or` short-circuit arms are included, as in the condition draft.

## Diagnostics

| Code | When |
|---|---|
| `E_SLOT_DUPLICATE` | A slot name is repeated in one quest |
| `E_STAGE_DUPLICATE` | A stage id is repeated in one quest |
| `E_SLOT_UNKNOWN` | `variant` or `with` names a slot this quest does not declare |
| `E_SLOT_STATE` | The variant state is not one of the seven names, or its condition shape is wrong |
| `E_LOCKED_AT_STAGE` | `locked_at` names a stage this quest does not declare |
| `E_STAGE_UNKNOWN` | `->` names a stage this quest does not declare |
| `E_STMT_UNKNOWN` | The statement is not part of this draft, or its shape is wrong |
| `E_LABEL_UNKNOWN` | A divert, choice, or scene `on_fail` names a label that is not in the scene |
| `E_LABEL_DUPLICATE` | A label is repeated in one scene |
| `E_CHOICE_SYNTAX` | A choice line is not one of the forms above |
| `E_SPEAKER_SHAPE` | A speaker is not a dotted identifier |
| `E_WRITE_RESOLVED` | `set` or `inc` targets a resolved fact |
| `E_WRITE_TYPE` | A write value does not match the stored fact, or `inc` is not numeric |
| `E_EFFECT_NOT_IN_SLICE` | The effect is outside the six forms, or the outcome value is not one of the three |
| `E_NO_SET_DISPOSITION` | The effect is `set_disposition` |
| `E_LINE_ID_MISSING` | A spoken line, journal entry, or choice label has no `#line:` |
| `E_LINE_ID_DUPLICATE` | The same `#line:` id appears twice in one file |
| `E_ARG_NAME` | A deed argument is unknown, positional, or duplicated, or a command argument name is duplicated |
| `E_ARG_TYPE` | A deed argument is missing or has the wrong type |

Existing condition codes (`E_CHANCE_CONTEXT`, `E_RESOLVER_INVALIDATION`, `E_UNKNOWN_FACT`, and the rest) still apply when an expression is compiled.

## Not in this draft

Cross-file linking, binding scene speakers to quest slots, command-schema checks, cross-file duplicate ids, the manifest, the WFR1 index, `tag-lines`, `export-json`, and the `facts` command are PR 5. Casting, succession, and resolving `redirect beat` are M4. Storylets, topics as entities, barks, and `priority:` are M6. The S1b-perf dirty-set benchmark and RPN speed pass are a separate change after this one and before PR 5. Nothing here runs at runtime.
