# Spike: compiled condition speed

Status: measured on this Linux VM (4 vCPU, `OS.get_processor_name()` reported `Intel(R) Xeon(R) Processor`), Godot 4.7.2-stable (official). Not a CI gate. Corey asked to record numbers only (2026-10-14).

## Question

Can a GDScript walk of a flat instruction array evaluate conditions fast enough for a large open world: on the order of 10k facts and 5k conditions, re-checked from a dirty set rather than every frame?

## What was timed

`tests/bench/bench.gd` builds a Gullhaven fixture through `WyrdRng` seed `0x57595244`: 10k stored int facts (`gullhaven.fact_00000` and so on) and 5k conditions. Each condition is two to five `and` comparisons. Compile and fixture setup are outside the timer. Each reader then scans all 5k conditions twice. The second scan is the warm run. There is no dirty set in this slice, so warm is another full scan, not a cache hit.

The three readers are the compiled instruction array through `tests/support/wyrd_rpn_eval.gd`, a hand-written GDScript loop of the same comparisons (the ceiling), and Godot `Expression` (a reference only). Content does not use `Expression`. All three agreed on checksum 700.

Setup (schema, values, compile, and `Expression` parse) was about 1.65–1.73 s and is not an evaluation number.

## Results

Microseconds for one 5k batch, three runs of the same binary:

| Run | RPN cold | RPN warm | GDScript warm | Expression warm |
|---|---:|---:|---:|---:|
| 1 | 80750 | 77378 | 658 | 4028 |
| 2 | 78018 | 75228 | 810 | 4457 |
| 3 | 107099 | 87311 | 740 | 5487 |

Per evaluation on run 1: RPN 16.15 µs cold and 15.48 µs warm; GDScript 0.154 µs cold and 0.132 µs warm; `Expression` 1.11 µs cold and 0.81 µs warm. Run 1's full JSON shape is what `tests/bench/bench.gd` writes. Later runs moved by tens of percent, so the headline is the range: a warm RPN batch is about 75–87 ms (about 15–17 µs each).

## Answers

- What counts as passing is still Corey's call. On this machine a warm 5k RPN batch is about 75–87 ms. The same comparisons in straight GDScript finish in under 1 ms. A budget of 2 ms per warm batch would reject this interpreter and still pass the ceiling.
- The gap to the ceiling is about 100×, and the gap to `Expression` is about 15–20×. A tighter opcode set might close some of that. It will not make an interpreter as cheap as the hand-written loop. This spike does not generate GDScript. Compiled content stays plain data that can be saved.
- The bench does not wait for a dirty set. Cold and warm are both full scans, and they landed in the same band. The number above is the cost of walking every condition, not the cost of rechecking a dirty subset. That subset is S2.

## S1b-perf, same machine

The tables above stay the original spike. This section is a later pass on the same Linux VM (`Intel(R) Xeon(R) Processor`, 4 vCPU) and Godot 4.7.2-stable (official). The walker now lives in `addons/wyrd/runtime/conditions/wyrd_rpn_eval.gd`. Each figure is one process. Cold is the first pass. Warm is the second full scan, or the mean of the next 1000 dirty ticks. Checksum 700 held for all three readers, and every dirty run matched a full scan.

### Full scan, before and after

Microseconds for one 5k batch. "Before" is the dictionary walker with `match` dispatch, measured in the same session as the pass. "After" is three confirmation runs of the kept binary.

| | Run | RPN cold | RPN warm | GDScript warm | Expression warm |
|---|---:|---:|---:|---:|---:|
| Before | 1 | 80077 | 77744 | 762 | 4591 |
| Before | 2 | 78318 | 76039 | 695 | 4314 |
| Before | 3 | 77909 | 75750 | 680 | 3888 |
| After | 1 | 16145 | 13583 | 832 | 4611 |
| After | 2 | 17766 | 15124 | 788 | 4957 |
| After | 3 | 17122 | 15764 | 840 | 5321 |

A warm RPN batch moved from about 76–78 ms to about 14–16 ms (about 2.7–3.2 µs each). The hand-written ceiling stayed under 1 ms. The gap to that ceiling is about 18–22×, down from about 100×.

### Dirty set

The index is built once from the same 5k conditions: about 21–24 ms, 17500 entries, 8239 keys. Changed facts come from `WyrdRng` sub-seed `0x57595245` plus the changed-fact count. Mean affected counts are fixed: 1.771, 17.594, and 172.274. Warm cells are the min–max of three runs, in microseconds. The ceiling re-checks the same conditions.

| Changed facts | Affected mean | RPN index | RPN eval | RPN tick | Ceiling eval | Ceiling tick |
|---|---:|---:|---:|---:|---:|---:|
| 1, before | 1.771 | 1.35–1.43 | 27.9–28.1 | 29.4–29.5 | 0.82–0.87 | 2.21–2.30 |
| 10, before | 17.594 | 9.5–10.0 | 276–279 | 285–289 | 6.1–6.3 | 15.6–16.4 |
| 100, before | 172.274 | 88–92 | 2703–2753 | 2791–2844 | 56–58 | 145–150 |
| 1, after | 1.771 | 1.37–1.42 | 5.49–5.69 | 6.86–7.10 | 0.83–0.87 | 2.20–2.28 |
| 10, after | 17.594 | 8.50–8.68 | 50.9–51.5 | 59.4–60.1 | 5.83–5.89 | 14.4–14.6 |
| 100, after | 172.274 | 76–79 | 495–505 | 574–581 | 54.0–54.9 | 130–134 |

Cold first ticks after the pass, three runs: 1 fact took 27–36 µs (2 conditions), 10 facts took 70–75 µs (16 conditions), and 100 facts took 624–658 µs (180 conditions).

### Kept and dropped

A change stayed only when all three warm full scans beat the previous three, and the dirty-tick medians at 1, 10, and 100 facts did not get worse. Warm RPN batch, then dirty tick at 100 facts, in microseconds.

| Change | Warm RPN, three runs | Dirty tick, 100 facts | Result |
|---|---|---|---|
| Fixed-size stack | 94478, 84572, 85806 | 3214, 3127, 3185 | Dropped. Slower than the 76–78 ms baseline, and the dirty ticks were slower too. |
| Hoist `consts` into a local | 79542, 77347, 91205 | 2932, 3200, 3007 | Dropped. Overlapped the baseline, and one run was worse. |
| Fact slots, then array reads | 72557, 69671, 72749 | 2723, 2792, 2759 | Kept. All three full scans beat the baseline. One 10-fact tick was 311 µs against a baseline band of 285–289 µs; the median was not worse. |
| `if` / `elif` by frequency, on top of slots | 23310, 21841, 22034 | 895, 995, 906 | Kept. About a third of the slot walk, and every dirty tick was faster. |
| Load-time superinstructions, on top of that | 16248, 16636, 14193 | 579, 728, 574 | Kept. Faster full scans, and dirty ticks stayed under the `if` / `elif` band. Saved opcodes did not change. |
| Inline the `JUMP_IF_FALSE` pop, on top of that | 22439, 14814, 14401 | 541, 554, 579 | Dropped. The full scans overlapped, and one run was much slower. |

The confirmation runs in the full-scan table are the stacked result after that last drop.

### Reading the dirty-set cost

No budget is set here. On this machine, after the pass, a tick that changes one fact costs about 7 µs to find and re-check the one or two conditions that read it. Ten facts cost about 60 µs. A hundred facts cost about 0.58 ms, against about 0.13 ms for the hand-written loop over the same conditions, and against about 14–16 ms to scan all 5k. The index lookup is the small part. The walk is still most of the tick. Whether 0.58 ms for a busy tick is acceptable is Corey's call.
