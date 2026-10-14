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
