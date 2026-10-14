# conditions

Runtime condition index and stack evaluator. The draft language is `docs/conditions-draft.md`.

`WyrdDepIndex` maps exact fact keys and `{id}` patterns to condition indexes. It is built from each condition's `reads` and is never saved. A pattern matches the whole key. A computed segment stays a wildcard.

`WyrdRpnEval` walks a compiled instruction array. A missing fact makes a comparison false. Load-time caches, when the evaluator builds them, are rebuilt from the saved program and are not written back. The fact store and the dirty set itself are S2. `tests/support/wyrd_rpn_eval.gd` is a thin shim over this class.
