# deeds

`WyrdDeedLog` is an append-only log. `record` assigns a monotonic id and the current game minute, then emits `deed_recorded`.

Rows are parallel packed arrays (`id`, `t`, `verb`, `actor`, `target`, `place`, `magnitude`, `visibility`, `memorable`) plus tag and witness pools. Indexes are by actor, target, and verb. A query scans the shortest of those indexes.

Decay is `magnitude × 0.5^((bucketed_now − t) / half_life)`. `bucketed_now` truncates to `hour_bucket_minutes`. Memorable rows and a half-life of 0 stay at full magnitude. `deed_score` rounds the sum to 6 decimal places. There is no compaction.

`witnesses: auto` calls `WyrdSpatialAdapter.witnesses_of`. Any other list is stored as given, sorted by id. Each witness stores a mode from `WyrdSpatialAdapter.perceive`: `saw`, `heard`, or `inferred`. The default mode is `saw`. An empty mode drops that witness. A mode outside those three is `saw` and `push_error`. `perceived(agent, verb)` returns the latest mode. The host calls `Wyrd.deeds.record`.
