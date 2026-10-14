# conditions

Runtime condition index and stack evaluator. The draft language is `docs/conditions-draft.md`.

`WyrdDepIndex` maps exact fact keys and `{id}` patterns to condition indexes. It is built from each condition's `reads` and is never saved. A pattern matches the whole key. A computed segment stays a wildcard.

`WyrdRpnEval` walks a compiled instruction array. A missing fact makes a comparison false. An optional `fact_reader` supplies keys the dictionary does not hold. Load-time plans are rebuilt from the saved program and are not written back. `tests/support/wyrd_rpn_eval.gd` is a thin shim over this class.

`WyrdConditionCtx` wires the slice built-ins to the fact store and the adapters. `holder` uses the role stub. `deed_count` returns 0 until the deed log exists. `chance` uses `WyrdRng.for_decision` on the `chance` stream. `knows`, `believes`, and `held` report M5 and return false.
