# Bench trend

Medians. `tick.recheck` is the inner-tick p95, then the median of those samples. Absolute budgets warn until they are confirmed.

| metric | unit | v0.4.0-m6 | v0.5.0-m7 |
| --- | --- | --- | --- |
| compile.strict | s | 119.055s | 78.234s |
| tick.recheck | s | 0.372ms | 0.273ms |
| believes.own | s | 1.274us | 0.812us |
| believes.group | s | 1.278us | 0.810us |
| perceive.credibility | s | 0.161ms | 0.115ms |
| reputation.cached | s | 45.000us | 33.000us |
| reputation.cold | s | 13.476ms | 11.610ms |
| save.time | s | 646.132ms | 496.576ms |
| save.bytes | B | 7.419MB | 7.419MB |
| load.time | s | 750.134ms | 642.646ms |
| compact.time | s | 853.458ms | 672.880ms |
| memory.peak | B | 249.978MB | 253.461MB |
| memory.steady | B | 221.088MB | 224.571MB |
| director.query | s | 4.500ms | 3.421ms |
| director.why_not | s | 13.015ms | 15.971ms |
| compile.tie_lint | s | 15.016s | 10.986s |
