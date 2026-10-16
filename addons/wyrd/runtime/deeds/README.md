# deeds

`WyrdDeedLog` is an append-only log. `record` assigns a monotonic id and the current game minute, then emits `deed_recorded`.

Rows are parallel packed arrays (`id`, `t`, `verb`, `actor`, `target`, `place`, `magnitude`, `visibility`, `memorable`) plus tag and witness pools. Indexes are by actor, target, and verb. A query scans the shortest of those indexes.

Decay is `magnitude × 0.5^((bucketed_now − t) / half_life)`. `bucketed_now` truncates to `hour_bucket_minutes`. Memorable rows and a half-life of 0 stay at full magnitude. `deed_score` rounds the sum to 6 decimal places.

`compact` merges rows that share verb, actor, target, place, visibility, memorable, minute, tags, and witness modes. Their magnitudes add, and the newest id is kept. Rows with a different minute stay apart, so a `within` window does not grow. A row whose decayed weight has rounded to zero is dropped when the dropped weights still round to zero and the row is not the latest perception of any witness. `deed_score`, axes, disposition, and reputation stay within that rounding. `deed_count` can fall. `perceived` stays on the surviving latest row. Compaction does not emit `deed_recorded` and does not run perception callbacks. `WyrdConfig.compact_after` of 0 does not compact on tick. A positive value compacts when the log is at least that long. The game seed is not an input. One `compact` line is logged per call when tracing is on.

`witnesses: auto` calls `WyrdSpatialAdapter.witnesses_of`. Any other list is stored as given, sorted by id. Each witness stores a mode from `WyrdSpatialAdapter.perceive`: `saw`, `heard`, or `inferred`. The default mode is `saw`. An empty mode drops that witness. A mode outside those three is `saw` and `push_error`. `perceived(agent, verb)` returns the latest mode. The host calls `Wyrd.deeds.record`.
