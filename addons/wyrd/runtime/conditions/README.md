# conditions

Runtime condition index and stack evaluator. The draft language is `docs/conditions-draft.md`.

`WyrdDepIndex` maps exact fact keys and `{id}` patterns to condition indexes. It is built from each condition's `reads` and is never saved. A pattern matches the whole key. A computed segment stays a wildcard.

`WyrdRpnEval` walks a compiled instruction array. A missing fact makes a comparison false. An optional `fact_reader` supplies keys the dictionary does not hold. Load-time plans are rebuilt from the saved program and are not written back. `tests/support/wyrd_rpn_eval.gd` is a thin shim over this class.

`WyrdConditionCtx` wires the slice built-ins to the fact store and the adapters. `holder` uses the role stub. `deed_count` returns 0 until the deed log exists. `chance` uses `WyrdRng.for_decision` on the `chance` stream. `knows` and `known` read a role reveal or `known/<agent>`. `believes` is the truthy belief, `belief` is the value, and `held` reads one group. `conflicted` is true when the agent's groups hold different values for one key. `perceived(agent, verb)` returns the latest `saw`, `heard`, or `inferred` mode. `nearby` counts spatial ids. `has` is a positive inventory `count`. `progress(id)` and `done(id)` read a sequence; an unknown id is an error and yields 0 or false. A missing adapter returns 0 or false. A lookup logs `belief_lookup` when tracing is on. A conflict resolution logs `conflict`. A knowledge change logs `knowledge`. A witness mode logs `perception`.
