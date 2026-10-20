# Bench trend

Medians. `tick.recheck` is the inner-tick p95, then the median of those samples. Absolute budgets warn until they are confirmed.

| metric | unit | v0.4.0-m6 | v0.5.0-m7 | v0.6.2-m8 | v0.6.3-m8 |
| --- | --- | --- | --- | --- | --- |
| compile.strict | s | 119.055s | 78.234s | 141.025s | 117.254s |
| tick.recheck | s | 0.372ms | 0.273ms | 0.543ms | 0.569ms |
| believes.own | s | 1.274us | 0.812us | 1.359us | 1.356us |
| believes.group | s | 1.278us | 0.810us | 1.368us | 1.360us |
| perceive.credibility | s | 0.161ms | 0.115ms | 0.125ms | 0.122ms |
| reputation.cached | s | 45.000us | 33.000us | 9.344us | 9.875us |
| reputation.cold | s | 13.476ms | 11.610ms | 18.432ms | 19.854ms |
| save.time | s | 646.132ms | 496.576ms | 661.374ms | 667.847ms |
| save.bytes | B | 7.419MB | 7.419MB | 8.094MB | 8.094MB |
| load.time | s | 750.134ms | 642.646ms | 891.180ms | 910.354ms |
| compact.time | s | 853.458ms | 672.880ms | 798.892ms | 828.558ms |
| memory.peak | B | 249.978MB | 253.461MB | 272.288MB | 283.200MB |
| memory.steady | B | 221.088MB | 224.571MB | 240.245MB | 251.157MB |
| director.query | s | 4.500ms | 3.421ms | 90.344us | 90.969us |
| director.why_not | s | 13.015ms | 15.971ms | 5.263ms | 5.938ms |
| compile.tie_lint | s | 15.016s | 10.986s | 14.042s | 17.606s |
