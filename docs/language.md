# Wyrd language 1

`language 1` is the language as of 1.0 and is on the stable surface. Changes follow `docs/stability.md`. A deprecated keyword keeps working and warns. Removal is only in 2.0. As shipped, the runtime warns once per id and `check` reports the diagnostic at each use. Examples use only the invented village Gullhaven.

## Lexical rules

Source is UTF-8. The first non-blank, non-comment line is the header `language 1`. Golden cases for these lexical rules are in `tests/golden/cases/`.

### Files and blocks

Blocks are indentation-only. There is no `end` keyword that closes a block. A block ends when the next line's indent decreases. `end` is also the closer of an `{if}` fragment, and a scene divert target. Those two uses are under [Interpolation](#interpolation) and [Scene](#scene).

Indentation is two spaces per level. A tab is an error. A nested line is indented exactly one level (two spaces) deeper than the line that opened its block. Blank lines are ignored. A blank line does not close a block.

### Comments

`//` starts a comment that runs to the end of the line. There is no block comment. `//` is not recognized inside a quoted string. `#` is never a comment. A leading `#` is how line tags are spelled.

### Line tags

A line tag has the form `#line:<id>`. `<id>` is a stable identifier. Editing the words of the line does not change the id. An id matches `[A-Za-z0-9_]+`. The tag is the last token on the line, except that a `//` comment may follow it.

```wyrd
tavern: The stew is free tonight. #line:a91f // spoken by whoever holds the tavern slot
```

`#tag:<name>` is an ordinary line tag and may sit before `#line:`. The names are stored on the line. `voiced` is the recording tag. `#tag:ai` marks a line that AI may reword. It is allowed on a spoken line and on a storylet line (a single `-` body or one entry of a `lines:` set). A choice label, a journal entry, a variant line, a document paragraph, or any other tagged node is `E_AI_LINE` ("only spoken and storylet lines can opt in to AI"). On an allowed line, the same code rejects a `voiced` tag ("a voiced line cannot opt in to AI"), a line in a secrecy tier ("a line in a secrecy tier cannot opt in to AI"; a storylet line also inherits the storylet's `secrecy:`), and any interpolation span ("an interpolating line cannot opt in to AI"). A `{{` escape is plain text. A storylet or a scene may add `ai_context: [<fact keys>]` to name concrete fact keys for that packet. An unknown key is `E_AI_CONTEXT_UNKNOWN`. A key whose fact is resolved per query warns `W_AI_CONTEXT_RESOLVED_PER_QUERY`.

```wyrd
narrator: The gate is shut tonight. #tag:ai #line:gate
ai_context: [player.coins, world.season]
```

`#secrecy:<name>` is a secrecy name, not a `#tag:` name. See [Storylet](#storylet).

### Escapes and titles

In prose (spoken lines and other unquoted text):

- `{{` is the only escape, and it is a literal `{`.
- A single `{` starts an interpolation. The expression language is under [Conditions](#conditions).
- `}` closes an interpolation. A `}` that does not close one is literal text.
- `}}` is not an escape.
- There are no backslash escapes in prose.

`The board lists the price as {{two coins}.` displays as `The board lists the price as {two coins}.`

Inside a double-quoted title:

- Titles use double quotes. There are no single-quoted strings.
- `\"` is a literal quote.
- `\\` is a literal backslash.
- No other backslash escape is defined.

`"The \"dawn\" crossing"` is the title `The "dawn" crossing`.

Quoted titles are never interpolated. Only unquoted prose is.

### Header: `language`

```wyrd
language 1
```

`1` is that integer token. The header is required. A missing header, a quoted form, another number, or any other spelling is an error. There is no default. A trailing `//` comment is allowed after `language 1`.

### Identifiers

A line id matches `[A-Za-z0-9_]+`. Quest ids, fact keys, speakers, and role names are identifiers as each form describes them. A reserved word is not a legal identifier.

### Reserved words: `document`, `publishes_by`, `tier`, `await_host`, `believe`, `declare`, `forget`, `learn`, `retract`

These nine words are reserved. They are not legal identifiers:

- `document`
- `publishes_by`
- `tier`
- `await_host`
- `believe`
- `declare`
- `forget`
- `learn`
- `retract`

`document` is a block, and it is also accepted immediately after `~ create`. `publishes_by` starts a periodic document header. `tier` is a field word inside a `template` block only. `await_host` is a stage statement. `believe`, `declare`, `forget`, `learn`, and `retract` are effect verbs immediately after `~`. As an identifier they stay `E_RESERVED_WORD`. `unbelieve` is an effect verb and is not reserved. Writers should not use any reserved word as a quest id, a fact key, or a role name.

### Lexical decisions

1. **Indentation.** Blocks are indentation-only. A block ends when the indent decreases. There is no `end` keyword for blocks.
2. **Indent width.** Two spaces per level. A tab is an error.
3. **Comments.** `//` line comments only. `#` is never a comment.
4. **Comment after a tag.** A `//` comment may follow a `#line:` tag.
5. **Spoken lines.** One source line per spoken line. A multi-line or wrap syntax is not part of language 1.
6. **Prose escapes.** `{{` is the only escape for `{`. A stray `}` is literal. There is no `}}` escape and no backslash escape in prose.
7. **Titles.** Inside double-quoted titles, `\"` escapes a quote and `\\` escapes a backslash.
8. **Header.** `language 1` is required. Anything else is an error.
9. **Reserved words.** The nine words listed above. `await_host` stays reserved and is not a legal identifier. Its statement form is under [Host-modal step](#host-modal-step). `document` and `publishes_by` stay reserved as identifiers. Their block form is under [Document](#document). `tier` stays reserved as an identifier. Its field form inside a template is under [Template](#template). `believe`, `declare`, `forget`, `learn`, and `retract` are the effect verbs under [Effects](#effects).
10. **Examples.** The quest, scene, and facts examples illustrate those blocks.

### Illustrated blocks

These examples show a `facts` block, a `quest`, and a `scene` with choices. One spoken line is one source line.

#### Facts

```wyrd
// content/gullhaven/ferry_toll.wyrd
language 1

facts
  player.coins      : int     stored
  ferry.toll_coins  : int     stored
  npc.{id}.alive    : bool    source: world.is_alive
  world.season      : symbol  source: time.season  invalidate: on_event(season_changed)
```

#### Quest

```wyrd
quest ferry_toll "The Ferry Toll"
  slot tavern = tavern_owner mode: live
  slot ferry  = ferry_master mode: live

  start when deed_count(player, verb: arrived, place: gullhaven) > 0

  stage gossip
    scene toll.offer_room with tavern
    -> pay_toll

  stage pay_toll
    journal "{holder(ferry).name} at the dock wants a toll before the crossing." #line:j_ft_01
```

#### Scene with choices

```wyrd
scene toll.offer_room
  tavern: A room's two coins a night, and the stew is free. #line:a91f // room offer
  * [Take the room] -> took
    ~ do assign_lodging(player, place: gullhaven.tavern) on_fail -> no_room
  * {has_tag(player, local)} [I have a place in town] -> declined
  tavern: The ferry's charging double since the storm, mind. #line:a920
  tavern: The board lists the price as {{two coins}}. #line:a921
```

## Facts

A top-level `facts` block declares keys. A declaration is `<key> : <type>` then `stored` or `source: <name>`, and an optional `invalidate:` mode. A pattern key uses `{id}` for one segment (`npc.{id}.alive`).

Condition types are `bool`, `int`, `float`, `symbol`, `entity`, `duration`, `distance`, `set` (a set of symbols), and `fact_key`. Event field types are `bool`, `int`, `float`, and `symbol`. `int` widens to `float`. Nothing else converts implicitly.

Perspectives:

- `world` is the stored world value. A bare fact read such as `player.coins` reads it.
- `known/<agent>` is what that agent knows. `knows(agent, key)` reads a role reveal or that perspective. `~ learn` writes it. `~ forget` removes it.
- `believed:` is the agent's own belief bag. `believes(agent, key)` and `belief(agent, key)` read the resolved belief, which walks this bag first.
- `held:` is one group's bag. `held(group, key)` reads that group only. `~ declare` writes it. `~ retract` removes it.

`known(agent, key)` was removed in 1.0. Compiling it reports `E_KNOWN_REMOVED` (`known was removed in 1.0; use knows(agent, key)`). Use `knows(agent, key)`. The `known/<agent>` perspective stays.

Lookup of a belief is the agent's `believed:` value, then `held:` of `groups_of(agent)` in precedence order, then null. A present value, including explicit false, stops the walk. Null is no opinion and is not equal to false. There is no fallback to `known:` or `world:`. A belief write marks the fact's dependents the same way a fact write does. Group membership is a synthetic read `group.membership`, dropped by `invalidate_groups` or by emitting `groups_changed`.

A concrete stored fact may carry `recap: true` or `recap: false`. See [Effects](#effects).

`invalidate: on_event(name)` must name an event declared in the pack. `per_query` never caches. `poll(minutes)` is a minute interval. A resolved fact with no invalidate mode is `E_RESOLVER_NO_INVALIDATE`.

## Conditions

`m` is minutes or metres from the parameter that expects a duration or a distance. If neither is expected, the compiler reports `E_EXPR_UNIT`. `h` and `d` are always durations. A day is 1440 minutes until a calendar resource exists. Callers can pass a different `minutes_per_day`. The 10k-fact / 5k-condition benchmark records numbers only. It is not a CI gate. Conditions have no string literals. Text comparisons use symbols.

`knows(agent, key)` reads a role reveal or `known/<agent>`. `believes(agent, key)` is true when the resolved belief is truthy. `belief(agent, key)` and a comparison `believes(agent, key) == v` read the value. `held(group, key)` reads that group's bag only.

A set literal is `[a, b]`. A computed key segment (`npc.{holder(ferry)}.alive`) is allowed outside prose. Inside a prose span, `{...}` closes at the first `}`, so the same read is `fact(npc, holder(ferry), alive)`.

The group-position condition is `conflicted(agent, key)`, not a call named `contested`. `contested` remains the slot state. `conflicted` is true when two of the agent's groups hold different present values for the key. Absence is not a position. Explicit false is. The agent's own belief, `known:`, and `world:` are not positions. `believes` still returns the first present group value in precedence order.

`perceived(agent, verb)` returns the latest witness mode `saw`, `heard`, or `inferred`, or null. `saw` writes `known/<agent>`. `heard` and `inferred` write `believed/<agent>`. Knowledge does not clear a belief. Beliefs are not copied to anyone who did not witness the deed.

A statement deed (`statement: true` on `record deed`) gates the revealed claim on speaker credibility. The default score is the listener's disposition toward the speaker divided by 100. The listener accepts when that score is at least `WyrdConfig.credibility_threshold` (default 0.5, inclusive). `register_credibility(listener, speaker)` replaces the score, is not saved, and does not read the game seed. Acceptance writes `believed/<listener>` only. Rejection writes nothing. `known/`, `world`, and `held/` are unchanged. The speaker is not added as a listener.

`reputation(subject, group)` is the mean disposition of the group's members toward the subject. The subject is excluded. Duplicate members count once. No members returns 0. A kind the observer holds toward the subject multiplies that axis's deed delta. The baseline is not scaled. Kinds in the other direction do not scale. The factors live on `WyrdConfig` and are not saved. Reputation is derived from members, kinds, baselines, and deeds.

`compact` folds interchangeable deed rows. Rows merge only when the minute matches, so `within` does not grow. Magnitudes add. A decayed weight that has rounded to zero can be dropped when that does not move `perceived`. `deed_score`, axes, disposition, and reputation stay within the 6-decimal rounding. `deed_count` may fall. `compact_after` of 0 does not run this on tick.

Learning the truth does not clear a belief. `W_STALE_BELIEF` warns when a scene `learn` writes `known/<agent>` for a key whose `believe` value text differs, and no `unbelieve` of that agent and key appears in the pack. A quest-stage `learn` is not this warning. A `record deed` is not this warning, because the witness mode is chosen at play time.

Player-visible text may interpolate `belief`, `believes`, and `held`. Each of those keys warns `W_CLAIM`. Interpolating the stored fact's world value is `E_FACT_LEAK` when a `when` or an `{if}` reads that fact from the world and does not also `knows` it. A line that does not interpolate the world value is unchanged.

### Precedence

Loosest first: `?:`, `or`, `and`, `not`, comparisons and `in`, `+` `-`, `*` `/`, unary `-`. Comparisons do not chain. `not a == b` is `not (a == b)`.

### Names, facts, and calls

A bare or dotted name is a symbol or entity id when the parameter expects one (`has(player, harbor_pass)`, `against: faction.harbor`). In value position it is a fact read (`player.coins`, `season == spring`). A one-segment name that is not a fact becomes a symbol. Two or more segments that miss in value position are `E_UNKNOWN_FACT`.

`fact(npc, holder(ferry), alive)` is a fact read, not a registry function. Each argument is one key segment. A call, or any other non-name, becomes the pattern segment `{id}`. A dotted path used as one argument is not split into segments.

Calls take positional arguments, then named arguments. A positional argument after a named one is `E_EXPR_ARG_ORDER`. Omitted optional parameters are compiled as nil.

`holder(ferry).name` reads the symbol `display_name(id)`. Any other field compiles as `attr(id, key)`.

### Units, sets, and ranges

Durations compile to minutes and distances to metres. `30m` is 30 minutes when a duration is expected and 30.0 metres when a distance is expected. `6h` is 360 minutes. `14d` is `14 * minutes_per_day` (20160 by default). Whole minute counts are ints. A distance is a float.

`in` on a range is inclusive (`hour in 6..18`). `in` on a set tests membership (`season in [spring, summer]`). Integer `/` truncates toward zero. `5.0 / 2` is float division.

### Types

`bool`, `int`, `float`, `symbol`, `entity`, `duration`, `distance`, `set` (a set of symbols), and `fact_key`. `int` widens to `float`. Nothing else converts implicitly. A condition used as a bool must already be `bool` (`E_NOT_BOOL`).

`chance(p)` is allowed in `storylet_or_choice`. In `wait_trigger_or_eligibility` it is `E_CHANCE_CONTEXT`. The condition still records `uses_chance`.

`nearby(center, radius, tag)` returns an int count. `can_perceive(a, b)` and `can_reach(a, place)` return bool. `has(holder, item_or_tag)` is true when `count` is greater than 0. These calls are allowed in `storylet_or_choice`. In `wait_trigger_or_eligibility` the three spatial calls are `E_SPATIAL_CONTEXT` unless the caller is an `on` condition, a transition nested in that `on`, or `waits_until`. A `waits_until` that uses one and whose stage has no `on` handler is also `E_SPATIAL_CONTEXT`. The condition records `uses_spatial`. That flag is not written into the condition's saved data. A missing adapter returns 0 or false and does not call the unimplemented base.

In `wait_trigger_or_eligibility`, a resolved fact whose invalidation is empty or `per_query` is `E_WAIT_RESOLVER_MODE`. `on_event` and `poll` are allowed. Stored facts are allowed. `E_RESOLVER_INVALIDATION` remains defined and is not emitted. Pack linking also requires every resolved fact to name `on_event`, `poll`, or `per_query` (`E_RESOLVER_NO_INVALIDATE`).

### Interpolation

Spoken lines keep the raw spans from the block lexer.

- `{expr}` inserts a value.
- A missing value is `{?<expr>}`, for example `{?ferry.toll_coins}`. It is not an empty string. `0` still renders as `0`. `{holder(slot).name}` is the host display name of the entity in that slot, not the role id. A role has no title field. Prose that also names the job, such as "the ferry master", writes that phrase itself.
- The linker warns `W_HOLDER_UNGUARDED` when prose interpolates `holder(slot)` and that slot can be empty there. `when filled(slot)` (including as an `and` conjunct, or on both sides of `or`) is a guard. So is a branch that a `variant <slot>.empty` replaces. `when npc.<entity>.alive` is not a guard: that resolved fact is cached until something invalidates it, so it can stay true after the slot is vacated.
- `{if cond}...{else}...{end}` is a conditional fragment and may nest. `{else}` is optional. Here `end` closes the fragment. It does not close a block.
- `{holder(name)|variants}` marks one holder switch. At display time the runtime picks the variant line for the current holder, or the name-free line with that span removed. The pick is not saved. With tracing on it logs `wyrd voice line=%s holder=%s chosen=%s`.
- `else` and `end` are reserved only as a whole span.
- An unbalanced `{if}`, or a stray `{else}` or `{end}`, is `E_INTERP_UNBALANCED`.

### Specificity and dependencies

Specificity is the number of top-level `and` clauses. An `or` group or a `not` group counts as one. A named-argument call counts as one clause, and so does a comparison that contains one. A parse error at the root counts as zero. A storylet with no `when` scores 0 and is generic. `priority` is stored on the storylet and does not change the score. `wyrd check` prints each storylet's score as `info[I_STORYLET_SCORE]`.

`reads` lists every fact key the condition may read, including keys on a short-circuit arm that one evaluation skips. `and`, `or`, and `?:` compile to jumps.

### Instructions

`WyrdCompiledCondition` holds `code` (`PackedInt32Array`), `consts` (ints, floats, bools, StringNames), `reads`, `specificity`, `uses_chance`, and `source_span`. There are no lambdas and no callables. The stack walker is `addons/wyrd/runtime/conditions/wyrd_rpn_eval.gd`. `tests/support/wyrd_rpn_eval.gd` is a thin shim over that class. A missing fact makes a comparison false. A call the evaluator does not find returns false, except `chance` when its argument is at least 1.

| Opcode | Operand | Effect |
|---|---|---|
| `PUSH_CONST` | const index | Push one constant |
| `PUSH_TRUE` | | Push `true` |
| `PUSH_FALSE` | | Push `false` |
| `PUSH_NIL` | | Push nil (omitted optional argument) |
| `LOAD_FACT` | const index | Load one stored key |
| `LOAD_KEY` | segment count | Join segment values and load that key |
| `NEG` | | Unary minus |
| `ADD` `SUB` `MUL` `DIV` | | Arithmetic. Integer `DIV` truncates toward zero |
| `EQ` `NE` `LT` `LE` `GT` `GE` | | Comparisons |
| `NOT` | | Boolean not |
| `IN_SET` | element count | Membership |
| `IN_RANGE` | | Inclusive range |
| `CALL` | name const, argc | Call a registered function. `argc` is the full slot count |
| `JUMP` | absolute ip | Jump |
| `JUMP_IF_FALSE` | absolute ip | Pop; jump when the value is not `true` |
| `JUMP_IF_TRUE` | absolute ip | Pop; jump when the value is `true` |

### Built-ins

One row per compiler signature. The condition context registers a reader for every name except `exists`, `attr`, `role`, `quest`, `stage`, and `seen`. Those six compile. The evaluator returns false for them until a host registers the name. `attr(` is also what a field other than `name` compiles to.

| Name | Signature | What it reads |
|---|---|---|
| `has(` | `has(holder:entity, item_or_tag:symbol)->bool` | Inventory count of that holder and item or tag. True when `count(` is greater than 0. A missing adapter is false. |
| `count(` | `count(holder:entity, item_or_tag:symbol)->int` | Inventory adapter count. A missing adapter is 0. |
| `owner_of(` | `owner_of(item:entity)->entity` | Inventory adapter owner. Empty when none is registered. |
| `nearby(` | `nearby(center:entity, radius:distance, tag:symbol)->int` | Spatial adapter count of ids within the radius with that tag. A missing adapter is 0. |
| `can_perceive(` | `can_perceive(a:entity, b:entity)->bool` | Spatial adapter. A missing adapter is false. |
| `can_reach(` | `can_reach(a:entity, place:entity)->bool` | Spatial adapter. A missing adapter is false. |
| `alive(` | `alive(id:entity)->bool` | World adapter `is_alive`. A missing adapter is false. |
| `active_count(` | `active_count(template:symbol)->int` | Active generated instances of that template. An unknown id is 0. A quest id is allowed. An id that names neither a template nor a quest is `E_TEMPLATE_UNKNOWN`. |
| `exists(` | `exists(id:entity)->bool` | No reader is registered. The evaluator returns false. |
| `kind(` | `kind(id:entity)->symbol` | World adapter kind. A missing adapter is empty. |
| `has_tag(` | `has_tag(id:entity, tag:symbol)->bool` | World adapter tags. A missing adapter is false. |
| `attr(` | `attr(id:entity, key:symbol)->symbol` | No reader is registered. The evaluator returns false. A field other than `name` compiles to this call. |
| `display_name(` | `display_name(id:entity)->symbol` | World adapter display name. Empty becomes null. `holder(slot).name` compiles to this call. |
| `rel(` | `rel(a:entity, b:entity, kind:symbol)->bool` | Whether the social graph has that relationship kind. |
| `path_exists(` | `path_exists(a:entity, b:entity, kinds:set, max_hops:int)->bool` | Whether a path of those relationship kinds exists within the hop limit. |
| `affinity(` | `affinity(a:entity, b:entity)->float` | Social affinity of the pair. |
| `axis(` | `axis(a:entity, b:entity, name:symbol)->float` | Social axis of the pair. |
| `disposition(` | `disposition(a:entity, b:entity)->int` | Social disposition of the pair. |
| `reputation(` | `reputation(subject:entity, group:entity)->float` | Mean disposition of the group's members toward the subject. The subject is excluded. No members is 0. |
| `deed_score(` | `deed_score(actor:entity, verb:symbol?, against:entity?, place:entity?, within:duration?, tags:set?)->float` | Deed-log score for the actor and the optional filters. |
| `deed_count(` | `deed_count(actor:entity, verb:symbol?, against:entity?, place:entity?, within:duration?, tags:set?)->int` | Deed-log count for the actor and the optional filters. |
| `perceived(` | `perceived(agent:entity, verb:symbol)->symbol` | Latest witness mode `saw`, `heard`, or `inferred` for that agent and verb, or null. |
| `role(` | `role(id:entity)->symbol` | No reader is registered. The evaluator returns false. |
| `holder(` | `holder(slot_or_role:symbol)->entity` | The role holder, or the instance cast when a generated scope is open. Empty is null. |
| `has_read(` | `has_read(reader:entity, doc:symbol)->bool` | The document read flag for that reader and document. Not a stored fact. |
| `filled(` | `filled(slot_or_role:symbol)->bool` | True when `holder(` is present. |
| `slot_state(` | `slot_state(slot:symbol)->symbol` | The slot state, or the instance state when a generated scope is open. |
| `outcome(` | `outcome(quest:symbol, branch:symbol)->symbol` | The quest's outcome for that branch, or null when unset. Content cannot name a template here. |
| `progress(` | `progress(id:symbol)->int` | Sequence progress. An unknown id is an error and yields 0. |
| `done(` | `done(id:symbol)->bool` | Whether the sequence is finished. An unknown id is an error and yields false. |
| `knows(` | `knows(agent:entity, key:fact_key)->bool` | A role reveal or `known/<agent>`. |
| `believes(` | `believes(agent:entity, key:fact_key)->bool` | Whether the resolved belief is truthy. |
| `belief(` | `belief(agent:entity, key:fact_key)->symbol` | The resolved belief value. The declared return is the fallback for a dynamic key. The checker uses the fact's type. |
| `conflicted(` | `conflicted(agent:entity, key:fact_key)->bool` | True when two of the agent's groups hold different present values for the key. |
| `held(` | `held(group:entity, key:fact_key)->bool` | Whether that group's `held:` bag has a truthy value for the key. |
| `quest(` | `quest(id:symbol)->symbol` | No reader is registered. The evaluator returns false. Content cannot name a template here. |
| `stage(` | `stage(id:symbol)->symbol` | No reader is registered. The evaluator returns false. Content cannot name a template here. |
| `seen(` | `seen(storylet:symbol)->bool` | No reader is registered. The evaluator returns false. A storylet's selection count is stored on the storylet row and is not this call. |
| `chance(` | `chance(p:float)->bool` | A roll on the `chance` stream. It does not read a fact. The condition records `uses_chance`. |

## Statements

A missing `#line:` id is an error. The hint is `run tag-lines`. Example content carries hand-written ids. Choice labels need `#line:` ids. A choice with no label does not. The only quest-level slot-state default is `on_empty:`. A line condition is a `when <cond>:` prefix: `when <cond>: <speaker>: <prose> #line:<id>`. Journal text is unquoted prose after a colon: `journal: text #line:<id>`. `{...}` interpolates. A quoted string is not journal text. Quest titles stay quoted and are not interpolated. A separate performance pass landed as its own change before linking.

### Quest

```wyrd
quest <id> "<Title>"
  slot <name> = <role> mode: live
  slot <name> = <role> mode: locked_at(<stage>)
  slot <name> = <role> mode: cast(<condition>)
  slot <name> kind: object mode: cast(<condition>)
  slot <name> kind: item mode: cast(<condition>)
  on_empty: wait
  on_missing_stage: depart
  requires: [pack.<id>, ...]
  start when <condition>
  stage <id>
  stage <id> was: <old>[, <old>…]
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

`cast(<condition>)` picks once at quest start. In that condition `candidate` is the entity being tested. A constant condition warns `W_SLOT_COND_ALWAYS` or `W_SLOT_COND_NEVER`. `cast(<condition>)` asks `WyrdWorldAdapter.candidates` once when the quest starts, keeps the ids the condition accepts, and freezes a seeded pick. No survivor leaves the slot `empty`. The freeze is saved with the other slot locks. One `cast` line is logged.

`requires: [pack.<id>, ...]` stores the pack ids. The linker warns `W_PACK_UNKNOWN` when an id is not this pack. At load, a quest whose required pack is not the loaded pack becomes `unavailable` and emits `content_unavailable`. A bad shape is `E_STMT_UNKNOWN` with `requires needs [pack.<id>, ...]`.

`redirect beat <beat> to <slot>` inside a `variant` is parsed and stored. Nothing resolves it. `redirect` outside a variant is `E_STMT_UNKNOWN` with `redirect beat is only valid in a variant`. A bad shape is `redirect needs beat <beat> to <slot>`.

A top-level stage may add `was: <old>[, <old>…]` after its id. Old ids are plain identifiers, the same rule as the stage id. `was:` on a region stage is `E_STMT_UNKNOWN` with `was: is only allowed on a top-level stage`. A malformed list is `E_STMT_UNKNOWN` with `was: needs an old id`. `was` is not reserved and stays a legal identifier everywhere else.

`on_missing_stage: <stage id>` is one plain identifier, the same shape as `on_empty:`, and may appear once. A second one is `duplicate statement "on_missing_stage"`. The stage must be a top-level stage of that quest. A region stage, a `was:` old id, and an unknown id are `E_MISSING_STAGE_TARGET` (`on_missing_stage stage "<id>" is unknown`). Load uses it when a save names a stage this quest no longer has.

A role id is a symbol (`ferry_master`). A role and a slot have no title or display field. `{holder(slot).name}` is the holder's personal name. A readable job title in example text is ordinary prose.

`start when`, `waits_until`, `cast`, `-> ... when`, and the conditions on `unwilling` and `barred` use `wait_trigger_or_eligibility`. `unwilling(<cond>)` and `barred(<cond>)` use that context because they gate a slot state.

`kind: object` or `kind: item` casts from world entities of that kind. The condition's top-level `and` conjunct `has_tag(candidate, <symbol>)` becomes the filter tag; any other shape leaves the tag empty and the condition is still checked on each answer. The world adapter's `candidates` receives that kind and tag. The pick is frozen at quest start. An item pick also stores `owner` from `owner_of` when an inventory adapter is registered, and that string is saved and loaded with the frozen entry. Object and role entries stay `{holder, status}`. Such a slot resolves only `locked_gone`, `empty`, and `default`. It is `empty` when nothing matches. It is `locked_gone` with reason `gone` when the frozen entity no longer exists, and reason `moved` when an item's owner differs from the recorded owner. `E_OBJECT_SUCCESSION` rejects a role on the same slot and a `successor` or `contested` variant. `hostile`, `unwilling`, and `barred` are `E_SLOT_STATE`. Save schema stays 3.

Slot states: `default`, `successor`, `empty`, `contested`, `hostile`, `unwilling(<cond>)`, `barred(<cond>)`, `locked_gone`. Precedence is `locked_gone`, `contested`, `empty`, then `barred`, `hostile`, `unwilling`, `successor`, and `default`. The first state that applies and has a declared variant wins. A higher state with no variant falls through. `contested` is the exception: no `contested` variant uses the `empty` variant, and the state stays `contested`. `unwilling` tests the holder as `$h`. `$` plus a name is one identifier. `$h` outside an `unwilling` condition is an error, and a lone `$` is an unexpected token. `barred` tests the player. Both are live, and a fact invalidation re-checks them on the next tick when no scene or host step is open. A scene ending finishes the current stage body before that re-check. `locked_gone` is a frozen `locked_at` holder who was vacated or is not alive, even when the role has a successor. A departure whose history reason is `assign` is not a vacate, for a host `assign` or a content `assign role`, so the frozen person stays bound and the slot stays usable. The slot holder stays that person. A quest resolution logs one `slot_state` line (`quest`, `role`, `slot`, `state`, `reason`). `WyrdTrace.prefix` keeps a line when the quest, role, or slot starts with that text.

`unwilling`, `barred`, `locked_gone`, and `contested` resolve at play time. `outcome <branch> = route_closed` keeps the quest open, and `outcome(quest, branch)` reads it.

### Sub-states

A stage may contain `region <id>` blocks. Each region holds its own `stage` list. Regions of one parent run together. One region still runs one stage at a time. A `->` inside a region names a sibling stage in that region. The parent `->` still names a stage of the quest. The parent leaves when its own `waits_until` or `-> when` says so. Regions do not join automatically.

The quest stage is depth 1. A stage inside its region is depth 2. A stage nested further warns `W_SUBSTATE_DEPTH` and still runs. Active leaves are saved on the quest row under `regions` (`stage`, `entered`, `step_at`, and nested `regions`). The key is omitted when the stage has no regions. Entry effects do not run again when `entered` is true and `step_at` is past them. A region `scene` or `await_host` uses the quest's one open scene or host slot. If that slot is busy, the region step stays put. With tracing on, each leaf change logs `wyrd region quest=%s path=%s from=%s to=%s`. `path` is the region id, or parent ids joined by `/`. On load, a saved leaf that is no longer one of that region's stages restarts at `stages[0]`, entered, with its entry steps counted, and nested regions reset the same way. The move is a `missing_stage` row.

```wyrd
stage repair
  region rope
    stage frayed
      waits_until harbor.rope_spliced
      -> spliced
    stage spliced
      ~ set harbor.rope_done = true
  -> done when harbor.rope_done
```

### Sequence

A top-level `sequence` counts events inside a game-minute window. It is not a quest stage. The id is a dotted name, the same shape as a quest id. `within` is required. `reset on` is optional. A bare event name resets on that event. Anything else is a condition. A bare name that is not a declared event is `E_EVENT_UNKNOWN`. `nearby`, `can_perceive`, and `can_reach` in a sequence are `E_SPATIAL_CONTEXT`.

```wyrd
sequence bell_signal any(3 of 3) within 60m reset on season_changed
  on mechanism_state where event.object == harbor_bell and event.state == rung
```

`ordered` matches steps in source order and does not skip. `any(<n> of <m>)` with one step counts that step up to `m` and finishes at `n`. `any(<n> of <m>)` with several steps needs `m` steps and counts each step once. The window includes its last minute. The next minute clears partial progress and leaves a finished sequence until reset. A reset event is handled before a step on that emit, so it does not also count. A reset condition is checked on each tick. `progress(id)` and `done(id)` read the sequence. With tracing on, a step, finish, reset, or expiry logs `wyrd sequence id=%s count=%s done=%s reason=%s`. An unknown id is an error and yields 0 or false. Partial progress is saved under `sequences` on schema 2 and omitted when nothing has started. Gullhaven's bell repair uses two regions, and `bell_signal` is three rings of `harbor_bell` within an hour.

### Scene

```wyrd
scene <id>
  on_abort:
    ~ <effect>
  <speaker>: <prose> #line:<id>
  when <cond>: <speaker>: <prose> #line:<id>
  * [<label>] -> <target> #line:<id>
  * [<label>] show_disabled_when {<cond>} "<reason>" -> <target> #line:<id>
  * {<condition>} [<label>] -> <target> #line:<id>
    check <skill>(<name>: <value>) on_fail -> <label>
    ~ <effect>
  - (<label>)
  -> <label>
  -> end
  -> scene <id>
  ai_context: [<fact key>, <fact key>]
```

A speaker is a slot name, an entity id (`name` or `name.name`), or `narrator`. The linker checks slot speakers against every quest stage that runs the scene. A slot speaker that stage does not pass is `E_SPEAKER_UNBOUND`. A scene no quest runs is `W_SCENE_UNUSED`, and its speakers are not checked.

`ai_context: [<fact key>, …]` may appear once among the scene's top-level statements. The keys are concrete dotted fact keys, stored in source order. They are not condition reads. A missing list, an empty list, a repeated key, a pattern key, a second `ai_context`, a line tag, or a block is `E_STMT_UNKNOWN`. An unknown key is `E_AI_CONTEXT_UNKNOWN`. A key resolved `per_query` warns `W_AI_CONTEXT_RESOLVED_PER_QUERY`. An opted-in line's packet reads those keys for facts the player knows. A fact the player has not learned is left out, including every resolved fact.

`#tag:<name>` may sit before `#line:`. `voiced` is the recording tag. `ai` opts a spoken line into AI rewording (`E_AI_LINE` rejects a voiced line, a secrecy tier, or an interpolation; `{holder|variants}` counts). A voiced line may not interpolate a value or a conditional fragment (`E_VOICED_VARIABLE`). `{holder(name)|variants}` is allowed. Untagged lines may still interpolate. `voice-check` reports that rule for every line, per speaker, and exits 1 when any line would fail it.

A holder switch is one span on the line. Nested lines name the holder and supply the pre-written text:

```wyrd
narrator: The crossing stays open. {holder(ferry_master)|variants} #tag:voiced #line:dock_voice
  variant ferry_master: The ferry master keeps the crossing open. #tag:voiced #line:dock_voice_master
  variant net_mender: The net mender keeps the crossing open. #tag:voiced #line:dock_voice_mender
```

Each variant has its own line id. The parent line is the name-free fallback. An empty slot, or a holder with no variant, shows that line with the span removed. The same form works on a journal line and on a storylet line. A storylet line uses the storylet speaker. `{holder|variants}` does not warn `W_HOLDER_UNGUARDED`, because the name-free line is the fallback.

Line conditions and choice conditions use `storylet_or_choice`. The first depth-zero `: <speaker> :` ends a line condition, so a ternary colon inside that condition needs parentheses: `when (a ? b : c): ferry: ...`.

`show_disabled_when {<cond>} "<reason>"` sits after the choice label. The condition is compiled in storylet context (`chance` allowed, bool required). It stores the condition text, the compiled condition, and the quoted reason. The reason is not interpolated and has no line id. `disabled_when` is a deprecated alias of the same form and warns `W_DISABLED_WHEN_DEPRECATED`. It keeps working. Both spellings on one choice are `E_CHOICE_SYNTAX`. A false `{condition}` hides the choice. Otherwise a true disabled condition shows it greyed out with the reason. `on_fail -> <target>` may sit on a `do` effect or on the following line. Inside a scene, that target is a label or `end`. A stage-level `on_fail` target must name a stage of that quest, or the linker reports `E_STAGE_UNKNOWN`.

A choice may start with one `check <skill>(...) on_fail -> <label>` line. `on_fail` may sit on that line or on the next indented line. `check` is not a reserved word. A check anywhere else is `E_STMT_UNKNOWN`. A bad check, a check that is not the first child, a second check, or a missing `on_fail` is `E_CHECK_SYNTAX`. When `wyrd_commands.json` has a `skills` list, an unknown skill is `E_SKILL_UNKNOWN`. Without that key, skills are not checked. The host answers the check through `WyrdSkillAdapter` before the choice effects run. A failure runs no choice effects and diverts to `on_fail`. The effect context is restored after the choice effects, so a later host role change for a bound slot aborts that scene `holder_left`.

`-> end` leaves the scene. That `end` is a divert target, not a block closer. `-> scene <id>` calls a sub-scene. The target must be a scene in the pack, or the linker reports `E_SCENE_UNKNOWN`.

A scene-level `~` line is a step. The runner runs it when it is reached and does not wait for input. Inline `on_fail -> <label>` diverts like a choice. A sibling `on_fail` line is `E_STMT_UNKNOWN` with `on_fail belongs on the do line`. A `when <cond>:` prefix on an effect is `E_STMT_UNKNOWN` with `when is not valid on an effect`. Provenance uses the scene id and an empty choice. If the effect closes the scene, the runner stops. An `assign role` from that step does not abort the scene for its own holder change. Every other open scene still aborts. An `advance` of the scene's own quest still refuses `scene_open`.

### Storylet

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
  speaker_cooldown: <duration>
  secrecy: <name>
  ai_context: [<fact key>, <fact key>]
  - <prose> #line:<id>
  lines:
    - <prose> #line:<id>
  -> scene <id>
```

A storylet has one body: one prose line, a `lines:` set, or `-> scene <id>`. `~` effects may sit among the fields, in any position, and are not a body. Inline or sibling `on_fail` is `E_STORYLET_SYNTAX` with `on_fail is not valid in a storylet`, and that effect is not stored. Effects do not change specificity, priority, the score line, or the tie lint. Field order is free. `when` uses `storylet_or_choice`, so `chance` is allowed. An omitted `when` scores 0 and is generic. `when: true` scores 1 and is not generic. `wyrd check` prints `info[I_STORYLET_SCORE]` with the specificity, the priority, and `generic=true` or `generic=false`.

`ai_context: [<fact key>, …]` stores concrete dotted fact keys in source order. The keys are not condition reads. A bad list is `E_STORYLET_SYNTAX` (the same messages as a scene `ai_context`, plus the usual duplicate-field and line-tag errors). An unknown key is `E_AI_CONTEXT_UNKNOWN`. A key resolved `per_query` warns `W_AI_CONTEXT_RESOLVED_PER_QUERY`. A storylet line tagged `#tag:ai` is an opt-in; a line in the storylet's `secrecy:` tier cannot opt in. An opted-in line's packet reads those keys for facts the player knows.

`priority` defaults to 0 and may be negative. `weight` defaults to 1. `0` is allowed. A negative weight is `E_STORYLET_SYNTAX`. `cooldown` defaults to 0 minutes. It is a duration (`m`, `h`, or `d`, with a day of 1440 minutes). The director treats a positive cooldown as a filter. `speaker_cooldown` uses the same duration and defaults to 0. The director consults it only for `scope: bark`. A duplicate id is `E_STORYLET_DUPLICATE`. A `-> scene` target the pack does not declare is `E_SCENE_UNKNOWN`. An `event` scope the pack does not declare is `E_EVENT_UNKNOWN`. A `topic` scope and a `beat` scope are stored and not checked against topics or quests.

`speaker: any` is a wildcard. A query for a specific speaker matches that speaker and `any`. A query whose speaker is empty or `any` matches every storylet in the scope. `Any` is not the wildcard. Exact speaker is not a rank key.

`WyrdDirector.query(scope_kind, scope_id, speaker)` filters by scope, speaker, secrecy, `when`, and cooldown, then ranks. Highest first: priority, specificity, weight, fewer times seen, then the older selection. A storylet that has never been selected is older than one that has. Generics stay in that pool at specificity 0. A higher priority beats a more specific storylet. Remaining ties are sorted by id and broken with `WyrdRng.for_decision` on stream `storylet_director`. The decision key is the scope text and the query speaker. The time bucket is the current game minute. A bark query ignores `scope_id`. A unique winner does not roll.

A storylet is on cooldown when it has been selected, its cooldown is greater than 0, and `now - last_minute` is still below that cooldown. Equality makes it eligible again. Cooldown 0 never excludes. If every match is on cooldown, the query has no winner.

A bark speaker clock is separate. The key is the query speaker when that name is non-empty and not `any`, otherwise the storylet speaker when that name is concrete, otherwise none. `any` and an empty name do not start a clock. A bark win with `speaker_cooldown` greater than 0 stores that duration and the current minute for the key. A bark candidate is cooling while `now - last` is still below the stored duration. A later win replaces that stored duration. Topic, event, and beat queries ignore the clock.

A win records `seen` and `last_minute`, then draws the body, then runs the storylet effects. Provenance uses scene `storylet:<id>` and an empty choice, then the previous scene and choice are restored. `why_not`, `candidate_rows`, and `Wyrd.dialogue.open` do not run them. A bark win still emits `bark_ready` after the effects. A bark win also emits `bark_ready` with one `WyrdLineView`. The speaker token is passed through `roles.holder`; a resolved holder becomes the view's entity, and a vacant token stays the entity id. `display_name` comes from the world adapter, or the entity id when that name is empty. `roles` lists world role bindings held by that entity, sorted. A scene body emits an empty line id and empty text. Audio uses the scene runner's `line_audio` callback. `draw` alone does not record a selection and does not emit `bark_ready`. `seen` and `last_minute` share the schema 2 `storylets` bag with the line-set `cursor`, `cycle`, and `order`, and they are omitted when nothing has been selected. Speaker clocks share schema 2 as `bark_speakers` and are omitted when none are stored. A storylet id the pack no longer has is kept in the storylet bag and ignored, so it returns if the content comes back. An unknown speaker id is kept in `bark_speakers`. A save entry that is not an object is dropped. A missing `bark_speakers` key clears the clocks and leaves the storylet rows. The storylet `when` is not added to the tick queue. `chance` in that `when` is keyed by the storylet id and the site `when`.

One `director` line is logged per query when tracing is on: scope, speaker, candidate count, winner, and score `priority/specificity/weight/seen`. Candidates are the rows that passed the filters. The score uses `seen` from before this selection. When `WyrdConfig.trace_director` is true and tracing is on, each scope-and-speaker match also logs `wyrd director_candidate scope=%s speaker=%s storylet=%s score=%s eligible=%s clause="%s"`. `eligible` is true when that match passed secrecy, `when`, and cooldown. `clause` is the first failing text, or `-`. A quote in that text is stored as itself and printed as `'`. `path` is the storylet id. `key` is the scope id, empty for a bark. The prefix matches either, and it also matches `scope` and `speaker`. The lines are not saved. Load does not log them. A line set is still drawn by `WyrdStoryletDeck`: one seeded shuffle per cycle, no repeat until the set is exhausted, then a new cycle.

`secrecy: <name>` on a storylet, and `#secrecy:<name>` on a line, name a host tier. The ordered names live on `WyrdConfig.secrecy_tiers`, lowest first, and are not saved. The unlocked name is the world fact `WyrdConfig.secrecy_fact` (default `player.clearance`). A missing fact, or a fact value that is not in the list, unlocks nothing named. An empty secrecy name stays visible. A name at the unlocked index is visible. A higher name is dropped before `when` and cooldown. A name that is not in the host list is dropped, and the runtime reports it once per new game. A line with no `#secrecy` uses the storylet name. A scene line, a journal line, and a choice use only their own `#secrecy`. A locked line in a set is skipped and the cursor moves past it. A storylet whose own name is open, but whose every line is locked, is dropped with the other candidates. One `wyrd secrecy storylet=%s line=%s tier=%s unlocked=%s` line is logged for each drop when tracing is on. The prefix matches the storylet id (`key`) and the line id (`path`). Load does not log one. The unlocked fact is an ordinary world fact, so schema stays 2 and the save has no secrecy key. A holder line with its own `#secrecy` that sits above the unlock shows the name-free line instead. The reserved word `tier` is not the field name. Facts do not carry a secrecy name. A document carries `#secrecy` on its header, and a paragraph may carry `#secrecy`. `check --tiers a,b,c` (lowest first) warns `W_SECRECY_LEAK` when visible text at a lower tier shows a stored fact that only higher-tier content sets.

The linker warns `W_STORYLET_TIE` once per pair, on the later storylet, when two storylets share a scope, their speakers can meet in one query, priority and specificity are equal, and the conditions can both be true. A topic, event, or beat scope matches the same kind and the same id. Every bark shares one scope. `speaker: any` overlaps every speaker. Two other speakers do not. The same storylet id is a duplicate, not a tie. Weight is printed in id order and does not suppress the warning. Exclusion is static. The same subject required to equal two values, a required equality that is also forbidden, or a required call or comparison that is also forbidden, do not warn. `or`, and `not` of `and` or `or`, do not prove exclusion. A `when` that fails to parse may still overlap. `chance` does not exclude another `chance`.

`WyrdDirector.why_not(storylet_id, scope_kind, scope_id, speaker)` explains one storylet. It does not record a selection, draw a line, or advance a random stream. Reasons, in order, are `missing`, `scope`, `speaker`, `secrecy`, `when`, `cooldown`, `ok`, and `outranked`. `eligible` is true only for `ok`. The `when` reason names the first failing top-level `and` clause. Secrecy is checked before `when`. The storylet clock is checked before the bark speaker clock. `cooldown` is the authored storylet minutes, or the stored speaker-clock minutes when that clock is the blocker. `remaining` is the minutes left, or 0 when the storylet was never selected, the cooldown is 0, or the cooldown has elapsed. When the storylet would win the seeded rank, the reason is `ok` and `winner` is that id. When another storylet would win, the reason is `outranked` and `winner` is that id. `tier` is the storylet secrecy name, or the line name when every line is locked and the storylet field is empty, or `-`. `unlocked` is the world fact named by `WyrdConfig.secrecy_fact`, or `-` when that fact is unset. One `why_not` line is logged when tracing is on. `wyrd why-not --manifest <path> [--scope kind] [--scope-id id] [--speaker id] [--save path] <storylet-id>` prints the same line. Omitted flags use the storylet's own scope, scope id, and speaker. An explicit `--speaker` replaces that default, and an empty speaker matches every storylet in the scope. The command exits 0 when it can explain the storylet, including an ineligible one, and exits 1 when the id is unknown or the pack does not load. `--tiers a,b,c` sets `WyrdConfig.secrecy_tiers` for that run, lowest first. Spaces around commas are ignored. An empty name is an error and the command exits 1. A repeated name stays in the list and the first copy is the one the unlock uses. Omitted `--tiers` leaves the list empty, which locks every named tier. `--secrecy-fact <key>` replaces `WyrdConfig.secrecy_fact` for that run. The default key is `player.clearance`. Neither flag is saved. `--trace-director` prints one candidate line per scope-and-speaker match, then the why-not line. `wyrd storylets --manifest <path> [--scope kind] [--scope-id id] [--speaker id] [--filter text] [--prefix text] [--tiers list] [--secrecy-fact key] [--save path] [--trace-director]` lists storylets in id order. `--filter` is a case-sensitive substring of the id. `--prefix` keeps ids that start with that text. `--speaker` uses the same wildcard as a query, and rows that do not match are omitted. A bark ignores `--scope-id`. Each row is `wyrd storylet id=%s scope=%s speaker=%s priority=%s specificity=%s weight=%s cooldown=%s secrecy=%s seen=%s block=%s clause="%s"`. `block` is `-` when the row passes secrecy, `when`, and cooldown, otherwise `secrecy`, `when`, or `cooldown`. The dump does not record a selection and does not roll. `--trace-director` on `storylets` needs `--scope` and appends candidate lines for that query. An omitted `--scope-id` matches only an empty scope id. `wyrd cooldowns --manifest <path> [--save path] [--prefix text]` lists exported storylet rows and speaker clocks: `wyrd cooldown storylet=%s seen=%s last=%s cooldown=%s remaining=%s` and `wyrd cooldown speaker=%s last=%s cooldown=%s remaining=%s`. `--prefix` keeps a storylet id or a speaker key that starts with that text. A storylet that has never been selected is omitted. Schema stays 2.

### Topics

There is no topic declaration. An id is whatever `unlock topic`, `lock topic`, or `scope: topic` uses. `Wyrd.topics` holds the unlocked ids. `is_unlocked(id)` and `unlocked()` (sorted) are the host reads. There is no host write. No condition built-in reads the set. The facade relays `topic_unlocked` and `topic_locked`. `runtime.effects.topic_unlocked` still fires once, on a new unlock.

`Wyrd.dialogue.open(npc)` returns the sorted unlocked topics that have at least one eligible storylet for that npc now. Eligibility is scope, speaker (the entity, a role that entity holds, or `any`, in one pool), secrecy, `when`, and cooldown. It records nothing, runs no effects, and does not open a scene. `can_save` stays as it was. An unknown npc, including a missing world adapter or an empty id, is `push_error` and an empty list, with no trace. With tracing on, the line is `wyrd topic_open npc=%s topics=%d`.

`Wyrd.dialogue.ask_topic(npc, topic)` refuses, in order: unknown npc (`push_error`, no trace), an open scene (`scene_open`), a locked topic (`locked`), then no winner (`no_storylet`, trace only). A win records the selection, draws the body, runs the storylet effects, then presents. A line or set emits `topic_answered(npc, topic, line)` on the scene runner. The line uses that npc as the speaker. A `-> scene` body calls `dialogue.open_scene`. The reason on a win is `answered`, including a scene body. With tracing on, the line is `wyrd topic_ask npc=%s topic=%s storylet=%s ok=%s reason=%s`.

`WyrdDirector.query` is unchanged and does not require the topic to be unlocked. `query_for_entity(scope_kind, scope_id, entity)` is the entity pool above. Its decision key is the scope text and the entity. It does not log `director_candidate` lines.

With tracing on, unlock logs `wyrd topic_unlock topic=%s ok=%s reason=%s` (`unlocked`, `already`) and lock logs `wyrd topic_lock topic=%s ok=%s reason=%s` (`locked`, `not_unlocked`). Each storylet or scene-line effect logs `wyrd effect_run source=%s id=%s kind=%s`. Load does not log these lines. The unlocked ids ride in the save bag `topics` when any exist. A missing key clears the set. Unknown ids are kept. Save schema stays 3.

### Line ids: `#line:`

Every spoken line, journal entry, and choice label needs a `#line:` id. A missing id is `E_LINE_ID_MISSING`. A duplicate id in one file is `E_LINE_ID_DUPLICATE`. The same id in two files of one pack is also `E_LINE_ID_DUPLICATE`, and the message names both files. `tag-lines` writes a missing id and never changes one that is already there.

Each line record keeps its id, speaker, tags, and scene. `tags` holds the `#tag:` names on that line, including `voiced` and `ai`. Journal entries leave `scene_id` empty.

### Reads

Every record keeps the union of fact keys read by its conditions, effect expressions, and prose, including keys on nested records. `and` / `or` short-circuit arms are included.

### Stage `on`

A stage may handle a declared world event. The form is `on <event> where <condition>:` followed by nested `~` effects and `->` transitions. `event.<field>` is a readonly binding in that condition and in those nested expressions. It is not a stored fact. Storylet `on`, and `on` outside a stage, are `E_STMT_UNKNOWN`. The event schema, payload check, and runtime are under [Events](#events).

`waits_until` may call `nearby`, `can_perceive`, or `can_reach` when the stage has an `on` handler. The same calls are allowed in that handler's `where` and in a transition nested there. `start when`, `cast`, a variant condition, and an ordinary stage transition reject them with `E_SPATIAL_CONTEXT`. A `waits_until` that uses one of them and has no `on` handler is the same error. The runtime rechecks that wait when one of the stage's `on` events is emitted. Later ticks read the cached result and do not poll the adapter. The first tick can still evaluate it, because every condition starts dirty.

### Host-modal step

`await_host` remains a reserved word and is not a legal identifier. Fact keys, quest ids, speakers, and role names still cannot use it.

A host-modal step is one statement inside a stage:

```wyrd
await_host <screen_id> returns { <field>, <field> }
```

`<screen_id>` is an identifier. `<field>` names are identifiers. The braces are the returns list, not prose interpolation. There is no condition, no block, and no nested effects. An empty `{}` is allowed. A field name may appear only once.

The compiler stores the step on the stage. At stage entry the runtime pauses remaining entry steps, calls `request_host_step`, and emits `host_step_requested`. `complete_host_step` stores the returned fields and resumes the steps that follow. A save is refused while a scene is open; a waiting host step is stored and resumed after load.

### Role

A top-level `role <id>` block is content. It sits beside `facts`, `events`, `quest`, and `scene`. The id is a dotted identifier. A role has no title. The header may add `was: <old>[, <old>…]` after the id; old ids are dotted the same way. A malformed list is `E_ROLE_SYNTAX` with `was: needs an old id`. Fields are optional. A missing field uses the default below. The same fields can be passed to `WyrdRoles.define`.

```wyrd
role ferry_master was: boatman
  scope: place(gullhaven)
  eligibility: alive(candidate) and has_tag(candidate, local)
  default_holder: ada
  visibility: public
  succession: relation(apprentice|kin)
  vacancy: hold
```

Role fields: `scope`, `eligibility`, `default_holder`, `visibility`, `succession`, `vacancy`.

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

`wyrd roles` prints a sorted table of every role (holder, status, strategy, pending or abolished, frozen slots). `--prefix` keeps ids that start with that text.

### Document

A top-level `document` block is either a periodic issue or a readable document. A header that contains `publishes_by`, `every`, or `delay` is the periodic issue below. A header without those words is readable: it needs a title, `text: live` or `text: frozen`, and at least one `page`. `document` and `publishes_by` stay reserved as identifiers. `create document <doc_id> copy <copy_id>` is an effect. `wyrd pot` extracts player text. That effect calls `create_copy` with an empty params dictionary.

```wyrd
document harbor_gazette "Harbor Gazette" publishes_by harbor_guild every 1 day delay 1 hour
  claim harbor.toll_fate
  fact harbor.gazette
  verb whispered
  fragment when held(harbor_guild, harbor.toll_fate)
    slant lost_at_sea
```

The header is `document <id> ["<title>"] publishes_by <group> every <number> <unit> delay <number> <unit>`. Either header may add `was: <old>[, <old>…]` directly after the id, before `publishes_by` on a periodic issue. Old ids are dotted, the same rule as the document id. The list stops at the first token that is not a comma continuation, so `publishes_by` still starts the periodic header. A malformed list is `E_DOCUMENT_SYNTAX` with `was: needs an old id`. The title is optional. Units are `minute` or `minutes`, `hour` or `hours`, and `day` or `days`. A minute is one game minute, an hour is 60, and a day is 1440. The period must be greater than zero. The delay may be zero. `claim` is the fact whose believed, known, or world value the issue copies. `fact` is a stored symbol that receives one line per issue. `verb` is the `deeds_known_to` filter. Each is optional and may appear once. A `fragment` is `when <condition>` and one `slant <symbol>` child. The first true fragment wins.

A readable document does not publish. `period_minutes` stays 0. `text:` is required once. `meta` values are bool, int, float, symbol, or string literals. Wyrd stores `meta` and does not interpret it. Each `page` needs a paragraph. Page lines are prose. `when <cond>:` on a paragraph stays code up to the colon. `{…|variants}` and `#tag:voiced` are `E_DOCUMENT_SYNTAX`. `#line:` is allowed on the readable header and on paragraphs. `tag-lines` tags those and does not tag a periodic document. `on_first_read:` and `on_read:` take `~` effects. `on_fail` is `E_DOCUMENT_SYNTAX` with `on_fail is not valid in a document`. Page, paragraph, and `{if}` conditions use the story context. `has_read(reader, doc)` reads a read flag. Read flags are not stored facts.

The runtime rules for witnesses, rumor believers, the claim pick, the catch-up cap, and the schema 3 counter are in `addons/wyrd/runtime/publish/README.md`. A skipped issue number is stored in that fact. The counter rides in `flight`.

### Template

A template is a quest body the generator can start. The header is `template <id> "<title>"`. Children reuse `slot`, `on_empty`, `on_missing_stage`, `requires`, and `stage`. A template has no `start`. `on_deed <verb>` or `on_deed <verb> where <condition>` queues pressure when that deed is recorded. A verb may appear once. The condition is a wait and may read `deed.actor`, `deed.target`, `deed.place`, and `deed.magnitude`. It cannot read a slot or param of this template.

```wyrd
template ferry.errand "The Errand"
  slot giver = dock_keeper mode: live
  param toll: item cast(has_tag(candidate, toll))
  when: player.coins > 0
  priority: 1
  weight: 2
  max_active: 1
  tier: low..high
  assumes: alive(giver)
  allow_protected: false
  on_deed theft where not deed.target == player
  stage ask
    journal: Ask the giver. #line:ask1
```

`param <name>: item|place|object cast(<condition>)` compiles the cast the way a kind slot does, with `candidate` bound. A param name that matches a slot or another param is `E_SLOT_DUPLICATE` with `duplicate slot "<name>"`. A template stage takes the same top-level `was:` list as a quest stage. Stage aliases are scoped to that template id. `slot`, `on_empty`, `on_missing_stage`, `requires`, and `stage` compile on the quest paths.

Each of `when:`, `priority:`, `weight:`, `max_active:`, `tier:`, `assumes:`, and `allow_protected:` may appear once. `when:` is a storylet condition and sets specificity from the compiled condition. `priority:` is a signed integer, default 0. `weight:` is an integer of at least 0, default 1. A negative weight is rejected. `max_active:` is an integer of at least 1, default 1. `tier:` is one name, or `<low>..<high>`. `tier` stays reserved as an identifier and is accepted as this field word only. Names are not checked against pressure tiers here. `assumes:` is a wait condition, so `chance` is rejected. Each top-level `and` part is one assumption and keeps its source text. In an entity argument inside `assumes:` only, an identifier that names one of this template's slots or params compiles as `holder(<name>)`. The same text anywhere else stays an entity literal. `allow_protected:` is `true` or `false`, default false.

`start` is `E_TEMPLATE_SYNTAX` with `a template has no start; the generator starts its instances`. `on_deed <verb>` or `on_deed <verb> where <condition>` may appear any number of times. The same verb twice is `E_TEMPLATE_SYNTAX` with `duplicate deed hook "<verb>"`. The condition is a wait. It may read `deed.actor`, `deed.target`, and `deed.place` as entities and `deed.magnitude` as a float. A bare name compared with one of those entities is an entity. A statement line has no `!=`, so write `not deed.target == player`. An unknown `deed.` field is `E_EVENT_ARG` with `unknown deed field "<name>"`. A bare name, `holder(<name>)`, or `slot_state(<name>)` that names a slot or param of this template is `E_TEMPLATE_SYNTAX` with `a deed hook runs before anything is cast`. A compiled template prints `info[I_TEMPLATE_SCORE]` as `template "<id>" specificity <n> priority <n>`.

`check --pressure-tiers a,b,c` warns `W_TEMPLATE_TIER_UNKNOWN` when a template tier name is not in that list, and `W_TEMPLATE_TIER_ORDER` when `low..high` names a low tier above the high tier. Without the list, neither warning is emitted.

A template shares the quest id namespace. The later declaration of a shared id is `E_QUEST_DUPLICATE`, and the message names `template` when the template is the later one. Quest lints walk template bodies: empty coverage, unreachable stages, unused slots, fact xref, secrecy, line ids, and holder and role checks. An unused name passed with `with` is `W_SLOT_UNUSED`; a param uses the noun `param`. `start quest`, `advance`, `quest(...)`, `stage(...)`, `outcome(...)`, and a storylet `scope: beat <template>.<stage>` cannot name a template (`E_TEMPLATE_REF`, `"<id>" is a template; content cannot name its instances`). `active_count(<id>)` of an id that names no template and no quest is `E_TEMPLATE_UNKNOWN` with `unknown template "<id>"`. A quest id is allowed. Two templates that share priority and specificity, have overlapping tiers, and whose `when` conditions can both be true are a tie (`W_TEMPLATE_TIE`): `template "<id>" ties "<id>": priority <n> specificity <n> weights <n> and <n>`. A missing tier overlaps every tier. A range overlaps every tier. Two single names overlap only when they are equal. Weight does not break the tie. `content.templates` is filled from the pack. The runner does not keep a row for the template id. The generator picks, casts, and binds instances from that table.

### Aliases

`was:` renames an id that older content still uses. `was` is not a reserved word. It stays a legal identifier in facts, ids, and prose. The compiler resolves chains and stores the tables on the linked pack. Load rewrites saved quest stages and their `trail` entries, role ids, deed verbs, document ids, periodic publish state, and the verbs of in-flight rumors through those tables.

```wyrd
stage offer was: offer_old
role ferry_master was: boatman
document harbor_gazette "Harbor Gazette" was: gazette
document tide_notice "Tide Notice" was: notice publishes_by harbor_guild every 1 day delay 1 hour
verb pay was: paid, tendered
```

A `stage`, `role`, or `document` header may add `was: <old>[, <old>…]` directly after its id. Old ids use that kind's id rule: a plain identifier for a stage, a dotted identifier for a role or a document. The list ends at the first token that is not a comma continuation. A quoted title still sits where it does today. `was:` on a region stage is not allowed.

`verb <new> was: <old>[, <old>…]` is a top-level, one-line statement. It has no title, no children, and no line tag. It only declares aliases. Verbs stay undeclared. A top-level `verb` without `was:` is `E_STMT_UNKNOWN` with `verb needs <new> was: <old>`. Two `verb` statements with the same new id merge their lists. The periodic document field `verb` is unchanged.

Stage aliases are scoped to the top-level stages of one quest or template. Quests and templates share one id namespace, and each keeps its own stage table. Role, document, and verb aliases are pack-wide.

A chain resolves to the final id. `verb settle was: pay` and `verb pay was: paid` store `paid → settle` and `pay → settle`. An old id that is still live in that scope is `E_ALIAS_CONFLICT`. One old id claimed twice is `E_ALIAS_DUPLICATE`. A cycle is `E_ALIAS_CYCLE`. Those entries are left out of the tables. A header id is always live, so a stage, role, or document chain is a conflict. Verb chains are the ones that resolve.

A verb is live when the pack names it: `record deed <verb>`, a template `on_deed <verb>`, or a periodic document's `verb` field.

The tables are `aliases.stage[<quest or template id>][<old>] = <new>`, and `aliases.role`, `aliases.document`, and `aliases.verb` as `<old> → <new>`. A kind key is omitted when that kind has no entries. `export-json` writes the same dictionary only when it is not empty. The manifest hash folds a canonical line `kind<TAB>scope<TAB>old<TAB>new` per entry, sorted, only when the tables are not empty. `scope` is empty except for a stage.

### Linking

`check` links a pack after statements. A directory with no manifest is one pack named after the folder. `--manifest` loads a `WyrdContentManifest` (`pack_id`, `files`, `language_version`). Files are linked in sorted path order. Diagnostics are sorted by file, line, column, then code. `check` exits 1 on an error. Warnings still exit 0 unless `--strict`. Info does not fail `--strict`. `check --watch` re-checks the pack whenever a listed file changes, and wraps each run in `wyrd: check started` and `wyrd: check finished errors=<n> warnings=<n>`. `check --tiers a,b,c`, lowest first, runs `W_SECRECY_LEAK` with the same list rules as `why-not`. Without `--tiers`, that warning is absent and `check` output is otherwise unchanged. A quest stage that no `->`, `do … on_fail`, `advance`, or region path reaches warns `W_STAGE_UNREACHABLE`. A `do … on_fail` inside an `on <event>` handler does not count, because handler effects do not divert. A stage reached only by a host GDScript `advance()` call warns, because the compiler cannot see that call.

`requires: [pack.<id>]` warns with `W_PACK_UNKNOWN` when the id is not this pack. `unlock topic` and `lock topic` warn `W_TOPIC_NO_STORYLET` when no storylet uses `scope: topic` for that id. There is no reverse warning. `on_event(...)` names are recorded as plain symbols. The event schema is under [Events](#events).

`export-json` writes a debug document (`wyrd_export` 1) with a per-file content hash. It is not the runtime load format. `facts` prints the cross-reference. `tag-lines` is the only command that edits source.

Resolved facts are never "never set". A `record deed` without `reveals` is not a fact write. A passed slot the scene does not speak is `W_SLOT_UNUSED`. A stage sets an outcome when one of its own effects, or an effect in one of its `on` handlers, is `outcome`. A variant body and a region stage are separate stages. A choice walks that choice's effects.

## Effects

`show_disabled_when` is a choice field, not an effect. The effect forms are the `~` lines below. The six slice effects plus `believe`, `unbelieve`, `declare`, `retract`, `learn`, `forget`, `start quest`, `advance`, `assign role`, `vacate role`, `adjust baseline`, `lock topic`, and `create document` are compiled. A storylet and a scene line may list `~` effects. Any other effect is `E_EFFECT_NOT_IN_SLICE`. `record deed` also accepts `visibility:` and `memorable:`.

| Form | Notes |
|---|---|
| `~ set <fact> = <expr>` | The fact must be stored. `{id}` patterns use `WyrdFactSchema.lookup`. |
| `~ inc <fact> by <expr>` | The fact and the value are `int` or `float`. `int` widens to `float`. |
| `~ record deed <verb>(...)` | Named arguments. `actor` is required. Optional: `target`, `place`, `tags`, `magnitude`, `witnesses`, `visibility`, `memorable`, `reveals`, `claim`, `statement`. |
| `~ unlock topic <id>` | Stores the id. A repeat unlock does not signal again. |
| `~ lock topic <id>` | Removes a stored id. A topic that is not unlocked is a no-op. |
| `~ do <command>(...)` | Arguments are type-checked. The linker checks the name against `wyrd_commands.json` beside the manifest. A missing file skips that check with `I_COMMANDS_SKIPPED` when a `do` exists. |
| `~ outcome <branch> = route_closed \| done \| failed` | Also accepted without the `~` inside a stage. |
| `~ believe <agent> <fact> = <expr>` | Stored schema fact only. `<agent>` is a dotted id. |
| `~ unbelieve <agent> <fact>` | Removes that agent's belief. A missing belief is a no-op. |
| `~ learn <agent> <fact> = <expr>` | Writes `known/<agent>`. Does not change `world`, `believed`, or `held`. |
| `~ forget <agent> <fact>` | Removes that agent's knowledge. A missing key is a no-op. |
| `~ declare <group> <fact> = <expr>` | Stored schema fact only. `<group>` is a dotted id. |
| `~ retract <group> <fact>` | Removes that group's held fact. A missing fact is a no-op. |
| `~ start quest <id>` | Starts that quest even when `start when` is false. `dormant` and `available` become `active` at the first stage. `active`, `completed`, `failed`, and `abandoned` warn and stay. `unavailable` stays `unavailable`. |
| `~ advance <quest> to <stage>` | Moves an `active` quest to a top-level stage, even if `waits_until` is false or a held-empty slot is waiting. The offered scene and the waiting reason are cleared. A pending host step or an open scene for that quest warns and stays. The current stage is a no-op. Any other status warns and stays. |
| `~ assign role <role> to <entity>` | Assigns the role from content. `<entity>` is a name path: an entity id, `player`, a slot of the running quest, or `holder(<role>)`. The status is `default` when the entity is the role's `default_holder`, otherwise `successor`. |
| `~ vacate role <role>` | Vacates the role from content and runs its succession. |
| `~ adjust baseline <axis>(a, b) by <n>` | Adds `<n>` to the stored baseline. `<n>` is an int or float, and may be negative. `<axis>` is any symbol. |
| `~ create document <doc_id> copy <copy_id>` | Copies a frozen readable document. `<copy_id>` is a dotted id or a quoted string. |

`witnesses` is `auto` or a set. A `do` argument that is only a name path is an entity id when lookup misses, and a fact read when lookup hits. Any other argument is an expression.

`believe`, `declare`, `retract`, `learn`, and `forget` are reserved words. They are legal only as the effect verb immediately after `~`. As an identifier they stay `E_RESERVED_WORD`. `unbelieve` is not reserved.

A concrete stored fact may carry `recap: true` or `recap: false`. `recap: true` keeps `set` and `inc` provenance when deeds compact. `recap: false` drops that provenance and records that the author chose it. A missing `recap:` key is unmarked. `set` or `inc` of an unmarked concrete stored fact warns `W_RECAP_UNMARKED` when the write sits in a stage that sets an outcome, or on a choice. The warning is one line per write, at the effect. `wyrd check` prints it and exits 0. `wyrd check --strict` exits 1. The code filters like the other warning lines.

`reveals` names a stored fact and `claim` is the value. A witness in mode `saw` learns it (`known/`). `heard` and `inferred` believe it (`believed/`). Nobody else receives it. There is no rumour spread. A missing witness list writes nothing. `perceived(agent, verb)` reads the latest mode.

`statement: true` is a statement deed. Perception modes are still stored, but the mode does not write the fact. Each witness is a listener. The speaker is not added. The listener accepts when `credibility_score(listener, speaker) >= credibility_threshold`. The default score is `disposition(listener, speaker) / 100`. `WyrdConfig.credibility_threshold` defaults to `0.5` and the comparison is inclusive. `register_credibility` replaces that score and is not saved. The game seed is not an input. Acceptance writes `believed/<listener>` only. Rejection writes nothing. `known/`, `world`, and `held/` stay unchanged. One `credibility` line is logged per listener, including a rejection, even when the belief value does not change. `statement: false`, or a deed with no `statement` argument, keeps the perception write above. A statement with no `reveals` records the deed and makes no credibility decision. `deeds.record` does not run this gate.

`start quest <id>` and `advance <quest> to <stage>` run in source order and share the 24 stage-hop limit. If the target quest's own step list is running, an `advance` is applied after that list, like a divert. A bad shape is `E_STMT_UNKNOWN`: `start quest needs a quest id`, or `advance needs <quest> to <stage>`. With tracing on, a start logs `wyrd quest_start quest=%s ok=%s reason=%s` (`started`, `active`, `completed`, `failed`, `abandoned`, or `unavailable`). An advance logs `wyrd quest_advance quest=%s from=%s to=%s ok=%s reason=%s` (`moved`, `not_active`, `same_stage`, `host_step`, or `scene_open`). A pending host step is reported ahead of an open scene. The current stage is reported ahead of both. Every status change logs `wyrd quest_status quest=%s from=%s to=%s`. The existing `transition` line stays. Neither effect reads or writes a fact. Save schema stays 3.

`assign role <role> to <entity>` calls `WyrdRoles.assign_from_content`. An unknown role is `push_error` with no trace. An abolished role, a contested role, a missing or dead entity, and a failed eligibility check warn. The same holder traces and does not warn. On success the previous holder is history with reason `assign`, a public `role_changed` deed records old to new when both exist, and `role_holder_changed` fires. The trace is `wyrd role_assign role=%s from=%s to=%s ok=%s reason=%s` (`assigned`, `abolished`, `contested`, `no_entity`, `ineligible`, `same_holder`).

`vacate role <role>` calls `WyrdRoles.vacate(role, content)` after the same unknown, abolished, and contested checks, and after an empty role. Succession then runs in declared order. The trace is `wyrd role_vacate role=%s from=%s to=%s ok=%s reason=%s` (`vacated`, `abolished`, `contested`, `empty`). `to` is the successor, or empty.

`adjust baseline <axis>(a, b) by <n>` calls `WyrdSocial.adjust_baseline`. A missing baseline counts as 0. There is no clamp and no kind scale. `n` of 0 does not touch the cache. An unresolved party, a self edge, and zero warn. The trace is `wyrd baseline_adjust a=%s b=%s axis=%s from=%s to=%s ok=%s reason=%s` (`adjusted`, `zero`, `self_edge`, `no_entity`). The fields carry `who` as `a`. Nothing writes a fact or a deed. Reputation stays derived.

A bad shape is `E_STMT_UNKNOWN`: `assign role needs <role> to <entity>`, `vacate role needs a role id`, or `adjust baseline needs <axis>(a, b) by <n>`. A non-numeric `<n>` is `E_WRITE_TYPE` with `adjust baseline needs an int or float`. A role that no `role` block declares warns `W_ROLE_UNKNOWN`, because a host may `define()` it. Name paths and `<n>` that read a fact are fact reads. Save schema stays 3.

A bad `create document` shape is `E_STMT_UNKNOWN` with `create document needs <doc_id> copy <copy_id>`. An unknown document is `E_DOCUMENT_UNKNOWN`. A live or periodic document is `E_DOCUMENT_NOT_FROZEN`. `lock` without `topic` is `E_EFFECT_NOT_IN_SLICE`, for the word `lock`. `lock topic` without an id is `E_STMT_UNKNOWN` with `lock topic needs a topic id`. `set_disposition` is `E_NO_SET_DISPOSITION` with the message `record deeds or use adjust baseline (§2.5)`.

## Events

A top-level `events` block sits beside `facts`. Grammar sections for files, indentation, comments, line tags, escapes, the header, and reserved words do not change. The stage `on` form is under [Stage `on`](#stage-on).

### Declaration

Names are unique in the pack. An event with no fields is invalidate-only: the payload must be empty. Field types are `bool`, `int`, `float`, and `symbol`. Every declared field is required.

```wyrd
events
  season_changed()
  entity_alive_changed(entity: symbol, alive: bool)
  mechanism_state(object: symbol, state: symbol, actor: symbol)
  item_inserted(item: symbol, receptacle: symbol, actor: symbol)
  liquid_poured(liquid: symbol, amount: int, target: symbol, actor: symbol)
  bucket_poured(actor: symbol, place: symbol) leaves: harbor.deck_wet = true decays 60
```

`leaves: <fact> = <value>` writes that stored fact into `world` when the event is emitted. `decays <minutes>` is a positive count of game minutes. Omit it and the fact stays. The fact must be a concrete stored key. A pattern, a resolved fact, a type mismatch, a field named `witnesses`, or `decays` that is not a positive integer is a diagnostic (`E_EVENT_ARG`, `E_UNKNOWN_FACT`, `E_WRITE_RESOLVED`, or `E_WRITE_TYPE`). There is no separate evidence store.

`emit` may pass `witnesses` beside the declared fields. An array of `{id, mode}` uses the deed modes: `saw` writes `known/<id>`, and `heard` or `inferred` writes `believed/<id>`. An empty mode skips that witness. `witnesses: auto` calls `WyrdSpatialAdapter.witnesses_of`, then `perceive`, with `actor`, then `target` or `object`, then `place` or that same target. A missing `witnesses` key writes no witness layers. A bad witness list is `push_error` and the emit still leaves the world fact.

The deadline is cleared on `tick` once `now_minutes()` reaches it, and only when the world value is still the evidence value. `known` and `believed` stay. Re-emitting replaces the deadline for that fact. `save_state` stores the deadlines in `facts.evidence` when any exist. Schema stays 2. `notice_evidence(observer, place)` runs `perceive` for evidence still at that place and writes the same layers. It does not clear the world fact.

`invalidate: on_event(name)` must name an event declared in the pack. `per_query` never caches. `poll(minutes)` is unchanged. A resolved fact with no invalidate mode is `E_RESOLVER_NO_INVALIDATE`.

### `on` handlers

Only a stage may say `on <event> where <condition>:`. The block is effects and `->` transitions, in source order. `event.<field>` is a readonly binding in that `where` and in those nested expressions. It is not stored unless an effect `set`s a fact. The same stage runs at most one matching handler per emit. A transition does not run the destination stage's handlers for that emit.

An open scene is not aborted when an event arrives. The next line, choice, or wait sees the new values. A holder leaving a passed slot still aborts on the role change. A dead holder aborts on the next `Wyrd.tick`. Authors who need a hard interrupt call `dialogue.abort`.

### Emit

`Wyrd.events.emit(name, payload)` checks the payload against the loaded schema. `witnesses` is not a declared field. A failure is `push_error`, trace kind `emit_rejected`, and no invalidation. Success traces `emit` with the name, payload, game time, invalidated keys, and the condition indexes re-checked, in ascending index order. Only dependents are re-checked. Each witness adds one `event_witness` line: `wyrd event_witness agent=%s mode=%s event=%s key=%s value=%s`. Each evidence write adds one `evidence` line: `wyrd evidence event=%s key=%s value=%s until=%s`. `until` is empty when the fact does not decay. Both lines carry `who` and `key` for the trace prefix. The evidence line's `who` is empty.

`begin_batch` / `end_batch` nest. Each emit still type-checks, drops caches, and runs handlers. One re-check runs when the outermost batch ends (`batch_begin` / `batch_end` in the trace).

### Save and replay

`save_state` does not store the event log. Load restores facts, roles, quests, and RNG. Caches start empty. Replay injects `emit`, `emit_rejected`, `batch_begin`, and `batch_end` in order. A mismatched payload fails the trace diff the same way a host answer does.

`debug_dump` and the playtest events line show the last 32 emits. That ring is not saved.

## Diagnostics

Codes use the `path:line:col: error[CODE]: message` format, and the same shape for `warning` and `info`. Existing condition codes still apply when an expression is compiled.

| Code | When |
|---|---|
| `E_AI_LINE` | `#tag:ai` is on a node that is not a spoken line or a storylet line, or that line is voiced, in a secrecy tier, or interpolating |
| `E_AI_CONTEXT_UNKNOWN` | `ai_context` names a fact key the schema does not have |
| `W_AI_CONTEXT_RESOLVED_PER_QUERY` | An `ai_context` key is resolved per query |
| `E_EXPR_SYNTAX` | The expression is incomplete, or it contains a string literal |
| `E_EXPR_UNEXPECTED` | A token is left over or not allowed here |
| `E_EXPR_UNIT` | `m` is not in a duration or distance parameter |
| `E_EXPR_ARG_ORDER` | A positional argument follows a named argument |
| `E_INTERP_UNBALANCED` | `{if}` / `{else}` / `{end}` do not match |
| `E_UNKNOWN_FACT` | Lookup found no concrete key and no `{id}` pattern, or `claim` or `fact` names a key the schema does not have |
| `E_UNKNOWN_FUNCTION` | The name is not a registered signature |
| `E_ARG_TYPE` | An argument is missing, extra, or the wrong type, or a deed argument is missing or has the wrong type |
| `E_ARG_NAME` | A named argument is unknown or duplicated, a deed argument is unknown, positional, or duplicated, or a command argument name is duplicated |
| `E_OP_TYPE` | An operator does not accept the operand types |
| `E_NOT_BOOL` | A condition's type is not `bool` |
| `E_CHANCE_CONTEXT` | `chance` appears in a wait, trigger, or eligibility condition |
| `E_SPATIAL_CONTEXT` | `nearby`, `can_perceive`, or `can_reach` appears in a wait, trigger, or eligibility condition that is not an `on` handler or a `waits_until` tied to one |
| `E_WAIT_RESOLVER_MODE` | A wait condition reads a resolved fact with empty or `per_query` invalidation |
| `E_RESOLVER_INVALIDATION` | Defined, and not emitted |
| `E_RESOLVER_NO_INVALIDATE` | A resolved fact has no `invalidate` mode |
| `E_KNOWN_REMOVED` | The source calls `known(agent, key)`. Use `knows` |
| `W_STALE_BELIEF` | A scene `learn` writes `known/<agent>` while a contradicting `believe` of that agent and key remains and no `unbelieve` clears it |
| `W_CLAIM` | Prose interpolates `belief`, `believes`, or `held`. The value is a claim |
| `E_FACT_LEAK` | Prose interpolates a stored fact's world value, and a `when` or `{if}` reads that fact from the world without `knows` |
| `W_HOLDER_UNGUARDED` | Prose interpolates `holder(slot)` where that slot can be empty. A guard is a `when` that requires `filled(slot)`, or an `empty` variant that replaces the branch |
| `E_SLOT_DUPLICATE` | A slot name is repeated in one quest, or a template param repeats a slot or param (`duplicate slot "<name>"`) |
| `E_STAGE_DUPLICATE` | A stage id is repeated in one quest |
| `E_SLOT_UNKNOWN` | `variant` or `with` names a slot this quest does not declare |
| `E_SLOT_STATE` | The variant state is not one of the eight names, its condition shape is wrong, or `hostile`, `unwilling`, or `barred` is used on an object or item slot |
| `E_OBJECT_SUCCESSION` | An object or item slot also names a role, or has a `successor` or `contested` variant |
| `E_LOCKED_AT_STAGE` | `locked_at` names a stage this quest does not declare |
| `E_MISSING_STAGE_TARGET` | `on_missing_stage` names a stage that is not a top-level stage of that quest or template |
| `E_STAGE_UNKNOWN` | `->` names a stage this quest does not declare, a stage `on_fail` names a stage this quest does not declare, or `advance` names a stage that is not a top-level stage of that quest. A nested sub-state is the same error |
| `E_STMT_UNKNOWN` | The statement is not a form in this reference, or its shape is wrong. `start quest` without an id says `start quest needs a quest id`. `advance` without `<quest> to <stage>` says `advance needs <quest> to <stage>`. `assign role` without `<role> to <entity>` says `assign role needs <role> to <entity>`. `vacate role` without a role id says `vacate role needs a role id`. `adjust baseline` without `<axis>(a, b) by <n>` says `adjust baseline needs <axis>(a, b) by <n>`. `lock topic` without an id says `lock topic needs a topic id`. A sibling scene `on_fail` says `on_fail belongs on the do line`. A `when` prefix on a scene effect says `when is not valid on an effect`. `was:` on a region stage says `was: is only allowed on a top-level stage`. A malformed stage `was:` says `was: needs an old id`. A scene `ai_context` that is the wrong shape says so. `redirect` outside a variant says `redirect beat is only valid in a variant`. A top-level `verb` without `was:` says `verb needs <new> was: <old>` |
| `E_LABEL_UNKNOWN` | A divert, choice, or scene `on_fail` names a label that is not in the scene |
| `E_LABEL_DUPLICATE` | A label is repeated in one scene |
| `E_CHOICE_SYNTAX` | A choice line is not one of the forms above, including both `show_disabled_when` and `disabled_when` on one choice. Error text names `show_disabled_when` |
| `E_CHECK_SYNTAX` | A choice check is malformed, is not the first child, is repeated, or has no `on_fail` |
| `E_SKILL_UNKNOWN` | `wyrd_commands.json` lists `skills` and the check names one that is not in that list |
| `W_DISABLED_WHEN_DEPRECATED` | A choice uses the `disabled_when` alias. `show_disabled_when` is the spelling |
| `E_SPEAKER_SHAPE` | A speaker is not a dotted identifier |
| `E_WRITE_RESOLVED` | `set`, `inc`, or a belief effect targets a resolved fact |
| `E_WRITE_TYPE` | A write value does not match the stored fact, `inc` is not numeric, or `adjust baseline` `<n>` is not an int or float |
| `E_EFFECT_NOT_IN_SLICE` | The effect is outside the compiled forms, or the outcome value is not one of the three. `lock` without `topic` uses this code |
| `E_NO_SET_DISPOSITION` | The effect is `set_disposition`. The message is `record deeds or use adjust baseline (§2.5)` |
| `E_LINE_ID_MISSING` | A spoken line, journal entry, or choice label has no `#line:` |
| `E_LINE_ID_DUPLICATE` | The same `#line:` id appears twice in one file, or twice in the pack. The pack message names both files |
| `E_VOICED_VARIABLE` | A line tagged `voiced` interpolates variable text |
| `E_VARIANT_SYNTAX` | A variant line, holder span, or duplicate holder is the wrong shape |
| `W_SUBSTATE_DEPTH` | A sub-state is nested past depth 2 |
| `E_SEQUENCE_SYNTAX` | A sequence header, count, window, or step is the wrong shape |
| `E_SEQUENCE_DUPLICATE` | The same sequence id is declared more than once |
| `E_EVENT_DUPLICATE` | The same event name is declared twice |
| `E_EVENT_UNKNOWN` | `on_event` or `on` names an event the pack does not declare, a sequence reset names an unknown event, or a storylet `event` scope is not declared |
| `E_EVENT_ARG` | The declaration shape is wrong, a field name is repeated, `event.<field>` is not on that event, or a deed hook names an unknown `deed.` field |
| `E_EVENT_TYPE` | A field type is not `bool`, `int`, `float`, or `symbol` |
| `E_STORYLET_SYNTAX` | A storylet body, field, weight, `ai_context`, or `on_fail` is the wrong shape |
| `E_STORYLET_DUPLICATE` | The same storylet id is declared twice |
| `E_SPEAKER_UNBOUND` | A slot speaker is not passed by a stage that runs the scene |
| `W_SCENE_UNUSED` | No quest stage runs the scene |
| `E_FACT_REDECLARED` | The same key or an overlapping pattern is declared in another file |
| `E_QUEST_DUPLICATE` | The same quest id is declared in another file. The message names `template` when a template is the later declaration |
| `E_QUEST_UNKNOWN` | `start quest` or `advance` names a quest that is not in the pack |
| `E_SCENE_DUPLICATE` | The same scene id is declared in another file |
| `E_SCENE_UNKNOWN` | `scene <id>` or `-> scene <id>` names a scene that is not in the pack |
| `E_COMMAND_UNKNOWN` | `do` names a command missing from `wyrd_commands.json` |
| `E_COMMANDS_FILE` | `wyrd_commands.json` is present and is not a command list |
| `I_COMMANDS_SKIPPED` | A `do` exists and no command file was loaded |
| `W_SLOT_UNUSED` | A passed slot is not a speaker in the scene. A template param uses the noun `param` |
| `W_EMPTY_UNCOVERED` | A slot used by a reachable stage has neither `variant <slot>.empty` nor quest `on_empty`. A `contested` variant does not cover it |
| `W_LOCKED_GONE_UNCOVERED` | A `locked_at` slot has no `locked_gone` variant on a reachable stage, or an object or item slot has no `locked_gone` variant |
| `W_SLOT_COND_ALWAYS` | An `unwilling` or `barred` condition is always true |
| `W_SLOT_COND_NEVER` | An `unwilling` or `barred` condition is never true |
| `W_ROUTE_CLOSED` | Every reachable assignment of a branch is `route_closed` |
| `W_PACK_UNKNOWN` | `requires` names a pack that is not loaded |
| `W_ROLE_UNKNOWN` | `assign role` or `vacate role` names a role that no `role` block in the pack declares. A host may `define()` it |
| `W_TOPIC_NO_STORYLET` | `unlock topic` or `lock topic` names an id that no storylet uses as `scope: topic`. The message is `topic "<id>" has no storylet` |
| `W_FACT_NEVER_READ` | A stored fact is written and never read |
| `W_FACT_NEVER_SET` | A stored fact is read and never written |
| `W_FACT_UNUSED` | A fact is never read or written |
| `W_RECAP_UNMARKED` | A concrete stored fact is `set` or `inc` in a stage that sets an outcome, or by a choice effect, and the declaration has no `recap:` key. `recap: true` and `recap: false` are silent. A pattern, a resolved fact, `believe`, `learn`, `declare`, `record deed`, an event `leaves` write, and a write on another stage stay silent |
| `W_INTERP_UNSET` | Prose interpolates a stored fact's world value that no earlier write sets. A `belief`, `believes`, `held`, `knows`, or `known` key is not that world value |
| `W_SECRECY_LEAK` | `check --tiers` only. Visible text interpolates a stored fact, and every writer that can run sits at a higher secrecy tier. `{if}` is exempt. Text or a writer whose name is not in the list is skipped |
| `W_STAGE_UNREACHABLE` | A quest stage that no `->`, handler transition, variant body, stage `do … on_fail` (including in a variant body or region stage), `advance`, or region path reaches. The id is `quest.stage`, or `quest.parent.region.child` for a region stage. A stage nested in an unreached stage is not reported again. A stage reached only by a host `advance()` call warns, because the compiler cannot see it. A handler's `on_fail` is not a path |
| `W_STORYLET_TIE` | Two storylets share a scope and a speaker, priority and specificity are equal, and the conditions can both be true |
| `I_STORYLET_SCORE` | `wyrd check` prints a storylet's specificity, priority, and whether it is generic |
| `E_ROLE_SYNTAX` | The role header or a field value is the wrong shape |
| `E_ROLE_DUPLICATE` | The same role id is declared twice |
| `E_DOCUMENT_SYNTAX` | The header, a duration, a field, a fragment, or a readable page is the wrong shape. The message names the field. `{…\|variants}` and `#tag:voiced` on a document page use this code. `on_fail` says `on_fail is not valid in a document` |
| `E_DOCUMENT_DUPLICATE` | The same document id is declared twice |
| `E_DOCUMENT_UNKNOWN` | `create document` or a literal `has_read` doc names no document |
| `E_DOCUMENT_NOT_FROZEN` | `create document` names a live or periodic document |
| `E_RESERVED_WORD` | A reserved word is used as an identifier. `document` and `publishes_by` are the cases named on a document, and `believe`, `declare`, `retract`, `learn`, and `forget` are the same code outside an effect verb |
| `E_TEMPLATE_SYNTAX` | A template field, param, `start`, or `on_deed` is the wrong shape. The message names the field |
| `E_TEMPLATE_REF` | Content names a template where a quest or an instance is meant |
| `E_TEMPLATE_UNKNOWN` | `active_count` names an id that is neither a declared template nor a declared quest |
| `W_TEMPLATE_TIE` | Two templates can tie for a pick |
| `W_TEMPLATE_TIER_UNKNOWN` | A template tier name is not in `--pressure-tiers` |
| `W_TEMPLATE_TIER_ORDER` | `tier: low..high` names a low tier above the high tier |
| `I_TEMPLATE_SCORE` | The template's specificity and priority |
| `E_ALIAS_CONFLICT` | An old id is still a live id in that scope. The message is `alias "<old>" is still a live <kind>`. A header id is live, so a self alias on a stage, role, or document is a conflict. A verb is live when the pack names it |
| `E_ALIAS_DUPLICATE` | One old id is claimed by two new ids in the same scope, or listed twice in one list. The message is `alias "<old>" is claimed by "<a>" and "<b>"`, at the later claim |
| `E_ALIAS_CYCLE` | The alias graph cycles. The message is `alias cycle: <a> -> <b> -> <a>`, once, at the earliest statement in the cycle |

## Not in language 1

One source line is one spoken line. A multi-line or wrap syntax for prose is not part of language 1.

A calendar resource is not part of language 1. A day is 1440 minutes until one exists. Callers can pass a different `minutes_per_day`.

`redirect beat` inside a variant is parsed and stored. Nothing resolves that redirect. `redirect` on a stage, outside a variant, is `E_STMT_UNKNOWN`.

A storylet cannot handle `on`. `on` outside a stage is `E_STMT_UNKNOWN`.

The `wyrd test` command prints `test: not implemented`.

## Keyword index

One row per `WyrdKeywords` group. Each word also appears in backticks on a heading below.

| Group | Words | Section |
|---|---|---|
| `header` | `language` | [Lexical rules](#lexical-rules) |
| `blocks` | `facts`, `events`, `quest`, `scene`, `role`, `storylet`, `sequence`, `document`, `template` | [Statements](#statements) |
| `reserved` | `document`, `publishes_by`, `tier`, `await_host`, `believe`, `declare`, `forget`, `learn`, `retract` | [Reserved words](#reserved-words-document-publishes_by-tier-await_host-believe-declare-forget-learn-retract) |
| `types` | `bool`, `int`, `float`, `symbol` | [Types](#types) |
| `fields` | `default_holder`, `eligibility`, `scope`, `succession`, `vacancy`, `visibility`, `ai_context`, `cooldown`, `priority`, `secrecy`, `speaker`, `speaker_cooldown`, `weight`, `when`, `fragment`, `text`, `meta`, `page`, `on_read`, `on_first_read`, `claim`, `fact`, `verb`, `publishes_by`, `every`, `delay`, `stored`, `source`, `recap`, `invalidate`, `doc`, `slot`, `on_empty`, `on_missing_stage`, `start`, `requires`, `stage`, `waits_until`, `journal`, `variant`, `await_host`, `on`, `region`, `redirect`, `on_abort`, `on_fail`, `check`, `disabled_when`, `show_disabled_when`, `ordered`, `any`, `where`, `leaves`, `decays`, `mode`, `live`, `frozen`, `cast`, `locked_at`, `lines`, `within`, `reset`, `with`, `topic`, `quest`, `role`, `baseline`, `copy`, `deed`, `to`, `by`, `of`, `beat`, `event`, `witnesses`, `actor`, `magnitude`, `memorable`, `place`, `statement`, `tags`, `target`, `auto`, `slant`, `param`, `max_active`, `assumes`, `allow_protected`, `on_deed`, `expires`, `was` | [Statements](#statements) |
| `effects` | `set`, `inc`, `record`, `unlock`, `lock`, `do`, `outcome`, `believe`, `unbelieve`, `declare`, `retract`, `learn`, `forget`, `start`, `advance`, `assign`, `vacate`, `adjust`, `create` | [Effects](#effects) |
| `states` | `default`, `successor`, `empty`, `hostile`, `locked_gone`, `contested`, `unwilling`, `barred` | [Quest](#quest) |
| `outcomes` | `route_closed`, `done`, `failed` | [Effects](#effects) |
| `operators` | `and`, `or`, `not`, `in` | [Precedence](#precedence) |
| `conditional` | `if`, `else`, `end` | [Interpolation](#interpolation) |
| `booleans` | `true`, `false` | [Types](#types) |

### header: `language`

### blocks: `facts`, `events`, `quest`, `scene`, `role`, `storylet`, `sequence`, `document`, `template`

### reserved: `document`, `publishes_by`, `tier`, `await_host`, `believe`, `declare`, `forget`, `learn`, `retract`

### types: `bool`, `int`, `float`, `symbol`

### fields: `default_holder`, `eligibility`, `scope`, `succession`, `vacancy`, `visibility`, `ai_context`, `cooldown`, `priority`, `secrecy`, `speaker`, `speaker_cooldown`, `weight`, `when`, `fragment`, `text`, `meta`, `page`, `on_read`, `on_first_read`, `claim`, `fact`, `verb`, `publishes_by`, `every`, `delay`, `stored`, `source`, `recap`, `invalidate`, `doc`, `slot`, `on_empty`, `on_missing_stage`, `start`, `requires`, `stage`, `waits_until`, `journal`, `variant`, `await_host`, `on`, `region`, `redirect`, `on_abort`, `on_fail`, `check`, `disabled_when`, `show_disabled_when`, `ordered`, `any`, `where`, `leaves`, `decays`, `mode`, `live`, `frozen`, `cast`, `locked_at`, `lines`, `within`, `reset`, `with`, `topic`, `quest`, `role`, `baseline`, `copy`, `deed`, `to`, `by`, `of`, `beat`, `event`, `witnesses`, `actor`, `magnitude`, `memorable`, `place`, `statement`, `tags`, `target`, `auto`, `slant`, `param`, `max_active`, `assumes`, `allow_protected`, `on_deed`, `expires`, `was`

### effects: `set`, `inc`, `record`, `unlock`, `lock`, `do`, `outcome`, `believe`, `unbelieve`, `declare`, `retract`, `learn`, `forget`, `start`, `advance`, `assign`, `vacate`, `adjust`, `create`

### states: `default`, `successor`, `empty`, `hostile`, `locked_gone`, `contested`, `unwilling`, `barred`

### outcomes: `route_closed`, `done`, `failed`

### operators: `and`, `or`, `not`, `in`

### conditional: `if`, `else`, `end`

### booleans: `true`, `false`
