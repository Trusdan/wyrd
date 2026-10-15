# Condition language (draft, not frozen)

Status: draft. This is not part of grammar v1. Sections 1–6 of `docs/grammar-v1.md` stay frozen. Corey approved the open choices below on 2026-10-14, each as option (a).

## Choices

1. `m` is minutes or metres from the parameter that expects a duration or a distance. If neither is expected, the compiler reports `E_EXPR_UNIT`. `h` and `d` are always durations.
2. A day is 1440 minutes until a calendar resource exists. Callers can pass a different `minutes_per_day`.
3. The 10k-fact / 5k-condition benchmark records numbers only. It is not a CI gate.
4. Conditions have no string literals. Text comparisons use symbols.
5. `knows`, `believes`, and `held` are registered signatures marked `M5`.
6. A set literal is `[a, b]`.
7. A computed key segment (`npc.{holder(ferry)}.alive`) is allowed outside prose. Inside a prose span, grammar v1 closes `{...}` at the first `}`, so the same read is `fact(npc, holder(ferry), alive)`.

## Precedence

Loosest first: `?:`, `or`, `and`, `not`, comparisons and `in`, `+` `-`, `*` `/`, unary `-`. Comparisons do not chain. `not a == b` is `not (a == b)`.

## Names, facts, and calls

A bare or dotted name is a symbol or entity id when the parameter expects one (`has(player, harbor_pass)`, `against: faction.harbor`). In value position it is a fact read (`player.coins`, `season == spring`). A one-segment name that is not a fact becomes a symbol. Two or more segments that miss in value position are `E_UNKNOWN_FACT`.

`fact(npc, holder(ferry), alive)` is a fact read, not a registry function. Each argument is one key segment. A call, or any other non-name, becomes the pattern segment `{id}`. A dotted path used as one argument is not split into segments.

Calls take positional arguments, then named arguments. A positional argument after a named one is `E_EXPR_ARG_ORDER`. Omitted optional parameters are compiled as nil.

`holder(ferry).name` reads the symbol `display_name(id)`. Any other field is `attr(id, key)`.

## Units, sets, and ranges

Durations compile to minutes and distances to metres. `30m` is 30 minutes when a duration is expected and 30.0 metres when a distance is expected. `6h` is 360 minutes. `14d` is `14 * minutes_per_day` (20160 by default). Whole minute counts are ints. A distance is a float.

`in` on a range is inclusive (`hour in 6..18`). `in` on a set tests membership (`season in [spring, summer]`). Integer `/` truncates toward zero. `5.0 / 2` is float division.

## Types

`bool`, `int`, `float`, `symbol`, `entity`, `duration`, `distance`, `set` (a set of symbols), and `fact_key`. `int` widens to `float`. Nothing else converts implicitly. A condition used as a bool must already be `bool` (`E_NOT_BOOL`).

`chance(p)` is allowed in `storylet_or_choice`. In `wait_trigger_or_eligibility` it is `E_CHANCE_CONTEXT`. The condition still records `uses_chance`.

In `wait_trigger_or_eligibility`, a resolved fact whose invalidation is empty or `per_query` is `E_RESOLVER_INVALIDATION`. `on_event` and `poll` are allowed. Stored facts are allowed.

## Interpolation

Spoken lines keep the raw spans from the block lexer.

- `{expr}` inserts a value.
- A missing value is `{?<expr>}`, for example `{?ferry.toll_coins}`. It is not an empty string. `0` still renders as `0`. `{holder(slot).name}` is the host display name of the entity in that slot, not the role id. A role has no title field. Prose that also names the job, such as "the ferry master", writes that phrase itself.
- `{if cond}...{else}...{end}` is a conditional fragment and may nest. `{else}` is optional.
- `{holder(ferry)|variants}` is parsed and not resolved.
- `else` and `end` are reserved only as a whole span.
- An unbalanced `{if}`, or a stray `{else}` or `{end}`, is `E_INTERP_UNBALANCED`.

## Specificity and dependencies

Specificity is the number of top-level `and` clauses. An `or` group or a `not` group counts as one. A parse error at the root counts as zero. `priority:` is not part of this draft.

`reads` lists every fact key the condition may read, including keys on a short-circuit arm that one evaluation skips. `and`, `or`, and `?:` compile to jumps.

## Instructions

`WyrdCompiledCondition` holds `code` (`PackedInt32Array`), `consts` (ints, floats, bools, StringNames), `reads`, `specificity`, `uses_chance`, and `source_span`. There are no lambdas and no callables. The stack walker is `addons/wyrd/runtime/conditions/wyrd_rpn_eval.gd`. `tests/support/wyrd_rpn_eval.gd` is a thin shim over that class. A missing fact makes a comparison false.

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

## Diagnostics

Codes use the existing `path:line:col: error[CODE]: message` format.

| Code | When |
|---|---|
| `E_EXPR_SYNTAX` | The expression is incomplete, or it contains a string literal |
| `E_EXPR_UNEXPECTED` | A token is left over or not allowed here |
| `E_EXPR_UNIT` | `m` is not in a duration or distance parameter |
| `E_EXPR_ARG_ORDER` | A positional argument follows a named argument |
| `E_INTERP_UNBALANCED` | `{if}` / `{else}` / `{end}` do not match |
| `E_UNKNOWN_FACT` | Lookup found no concrete key and no `{id}` pattern |
| `E_UNKNOWN_FUNCTION` | The name is not a registered signature |
| `E_ARG_TYPE` | An argument is missing, extra, or the wrong type |
| `E_ARG_NAME` | A named argument is unknown or duplicated |
| `E_OP_TYPE` | An operator does not accept the operand types |
| `E_NOT_BOOL` | A condition's type is not `bool` |
| `E_CHANCE_CONTEXT` | `chance` appears in a wait, trigger, or eligibility condition |
| `E_RESOLVER_INVALIDATION` | A wait condition reads a resolved fact with empty or `per_query` invalidation |

## Not in this draft

Effects, and wiring conditions into `start when`, `waits_until`, choices, and `when`, are later. So are variant resolution, the linker, the calendar resource, and the runtime evaluator.
