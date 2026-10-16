# Bench trend

Medians. `tick.recheck` is the inner-tick p95, then the median of those samples. Absolute budgets warn until they are confirmed.

| metric | unit | v0.4.0-m6 |
| --- | --- | --- |
| compile.strict | s | 119.055s |
| tick.recheck | s | 0.372ms |
| believes.own | s | 1.274us |
| believes.group | s | 1.278us |
| perceive.credibility | s | 0.161ms |
| reputation.cached | s | 45.000us |
| reputation.cold | s | 13.476ms |
| save.time | s | 646.132ms |
| save.bytes | B | 7.419MB |
| load.time | s | 750.134ms |
| compact.time | s | 853.458ms |
| memory.peak | B | 249.978MB |
| memory.steady | B | 221.088MB |
| director.query | s | 4.500ms |
| director.why_not | s | 13.015ms |
| compile.tie_lint | s | 15.016s |
