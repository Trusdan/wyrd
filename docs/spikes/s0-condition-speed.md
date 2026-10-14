# Spike: compiled condition speed

Status: plan only. S0 does not measure this. The compiler and the fact store are out of scope, so there is nothing honest to time yet.

## Question

Can a GDScript walk of a flat instruction array evaluate conditions fast enough for a large open world: on the order of 10k facts and 5k conditions, re-checked from a dirty set rather than every frame?

## Plan

1. After the slice compiler emits a flat instruction array (no lambdas, no `Callable`s), add a case beside `tests/bench/bench.gd`.
2. Build a Gullhaven-only fixture: 10k stored facts and 5k conditions that each read a few of them. Ids look like `player.coins` and `gullhaven.dock`.
3. Time N evaluations with `Time.get_ticks_usec()` and write JSON through the existing runner. Do not gate CI on the number until a budget is chosen.
4. Compare three readers of that same fixture:
   - the compiled instruction array
   - a hand-written GDScript function that does the same comparisons, as a ceiling
   - Godot `Expression`, as a reference point only. Content will not use `Expression`.
5. Report microseconds per evaluation and for a 5k batch, split into a cold run and a run where nothing is dirty.

## Open questions

- What number counts as passing: one evaluation, one game tick, or a 5k batch?
- If interpretation is too slow, is a tighter integer opcode set enough, or does import have to generate GDScript?
- Generated GDScript would fight the rule that compiled content is plain data that can be saved. Is that trade acceptable anywhere?
- Should the bench refuse to run until the dirty-set cache exists, so a cold scan is not mistaken for the runtime cost?
