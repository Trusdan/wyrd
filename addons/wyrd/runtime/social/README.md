# social

`WyrdSocial` stores relationship kinds and axis baselines. An axis is the baseline plus deed contributions.

A deed adds `delta × decayed weight` to `axis(observer, subject)` when `subject` is the actor and `observer` is the target or a witness. Deltas come from `WyrdConfig.set_axis_delta`. Kind-scaled deltas and reputation are M5.

Disposition is `disposition_default + affinity / 2`, clamped to 0..100, unless the host registers a formula. The formula is `(a, b, axes) -> int` and is not saved.
