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

`cast(<condition>)` is type-checked only. Casting arrives in M4. `requires` and `redirect beat` are parsed only.

A role id is a symbol (`ferry_master`). A role and a slot have no title or display field. `{holder(slot).name}` is the holder's personal name. A readable job title in example text is ordinary prose.

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

A speaker is a slot name, an entity id (`name` or `name.name`), or `narrator`. The linker checks slot speakers against every quest stage that runs the scene. A slot speaker that stage does not pass is `E_SPEAKER_UNBOUND`. A scene no quest runs is `W_SCENE_UNUSED`, and its speakers are not checked.

Line conditions and choice conditions use `storylet_or_choice`. The first depth-zero `: <speaker> :` ends a line condition, so a ternary colon inside that condition needs parentheses: `when (a ? b : c): ferry: ...`.

`disabled_when` stores the condition text and the quoted reason. The reason is not interpolated. `on_fail -> <target>` may sit on a `do` effect or on the following line. Inside a scene, that target is a label or `end`. A stage-level `on_fail` target must name a stage of that quest, or the linker reports `E_STAGE_UNKNOWN`.

`-> end` leaves the scene. `-> scene <id>` calls a sub-scene. The target must be a scene in the pack, or the linker reports `E_SCENE_UNKNOWN`.

## Effects

| Form | Notes |
|---|---|
| `~ set <fact> = <expr>` | The fact must be stored. `{id}` patterns use `WyrdFactSchema.lookup`. |
| `~ inc <fact> by <expr>` | The fact and the value are `int` or `float`. `int` widens to `float`. |
| `~ record deed <verb>(...)` | Named arguments. `actor` is required. Optional: `target`, `place`, `tags`, `magnitude`, `witnesses`, `visibility`, `memorable`. |
| `~ unlock topic <id>` | Parsed and stored. |
| `~ do <command>(...)` | Arguments are type-checked. The linker checks the name against `wyrd_commands.json` beside the manifest. A missing file skips that check with `I_COMMANDS_SKIPPED` when a `do` exists. |
| `~ outcome <branch> = route_closed \| done \| failed` | Also accepted without the `~` inside a stage. |

`witnesses` is `auto` or a set. A `do` argument that is only a name path is an entity id when lookup misses, and a fact read when lookup hits. Any other argument is an expression.

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
| `W_EMPTY_UNCOVERED` | A slot has neither `variant <slot>.empty` nor quest `on_empty` |
| `W_PACK_UNKNOWN` | `requires` names a pack that is not loaded |
| `W_FACT_NEVER_READ` | A stored fact is written and never read |
| `W_FACT_NEVER_SET` | A stored fact is read and never written |
| `W_FACT_UNUSED` | A fact is never read or written |
| `W_INTERP_UNSET` | Prose interpolates a stored fact that no earlier `set` or `inc` writes |
| `W_HOLDER_UNGUARDED` | Prose interpolates `holder(slot)` where that slot can be empty. A guard is a `when` that requires `filled(slot)`, or an `empty` variant that replaces the branch |
| `I_COMMANDS_SKIPPED` | A `do` exists and no command file was loaded |

Resolved facts are never "never set". `record deed` is not a fact write. A passed slot the scene does not speak is `W_SLOT_UNUSED`.

## Host-modal step

`await_host` is approved (Corey, 2026-10-14). See `docs/grammar-v1.md` section 9. It is a stage statement: `await_host <screen_id> returns { <field>, ... }`. The word is still not a legal identifier. The runtime pauses the remaining entry steps, calls `request_host_step`, emits `host_step_requested`, and resumes on `complete_host_step`.

## Not in this draft

Casting proper, `locked_gone`, and resolving `redirect beat` are M4. Until then a `cast` slot binds once to the role's current holder when the quest starts. The linker warns `W_EMPTY_UNCOVERED` when a slot can become empty and the quest does not cover it. Storylets, topics as entities, barks, and `priority:` are M6. Host world-event schemas are later host-adapter work. `test` stays unimplemented.
