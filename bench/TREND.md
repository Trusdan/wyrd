# Bench trend

No tag results are committed yet. The tag run writes `bench/results/<tag>.json` and regenerates this file.

Medians. `tick.recheck` is the inner-tick p95, then the median of those samples. Absolute budgets warn until they are confirmed.

| metric | unit |
| --- | --- |
| compile.strict | s |
| tick.recheck | s |
| believes.own | s |
| believes.group | s |
| perceive.credibility | s |
| reputation.cached | s |
| reputation.cold | s |
| save.time | s |
| save.bytes | B |
| load.time | s |
| compact.time | s |
| memory.peak | B |
| memory.steady | B |
