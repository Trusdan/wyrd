# social

`WyrdSocial` stores relationship kinds and axis baselines. An axis is the baseline plus deed contributions.

A deed adds `delta × decayed weight × kind scale` to `axis(observer, subject)` when `subject` is the actor and `observer` is the target or a witness. Deltas come from `WyrdConfig.set_axis_delta`. The kind scale starts at 1. Each kind the observer holds toward the subject multiplies by `WyrdConfig.kind_scale` for that axis. A kind in the other direction does not. The baseline is not scaled. Scales are host config and are not saved.

`reputation(subject, group)` is the mean `disposition(member, subject)` of `WyrdWorldAdapter.members(group)`. The subject is excluded. Duplicate members count once. No members returns 0. The value is rounded like an axis sum. It is not stored; kinds, baselines, and deeds reconstruct it. Emitting `groups_changed`, or calling `invalidate_groups`, wakes a condition that reads it. One `reputation` line is logged per call when tracing is on.

Disposition is `disposition_default + affinity / 2`, clamped to 0..100, unless the host registers a formula. The formula is `(a, b, axes) -> int` and is not saved.
