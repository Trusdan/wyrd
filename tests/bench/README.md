# Informational benchmark

This folder is the older timing probe. CI runs it and does not fail on the numbers. The milestone suite, with smoke and full profiles, is `bench/README.md`.

# Benchmark harness

`bench.gd` writes JSON for two informational workloads. CI does not fail on the timing.

The placeholder workload hashes a fixed set of Gullhaven ids and mixes in rolls from `WyrdRng` (`elapsed_usec`, iteration count, a checksum, and the Wyrd and Godot versions).

The condition workload is fixed: 10k stored facts and 5k conditions from `WyrdRng` seed `0x57595244`. It times a compiled instruction walk, a hand-written GDScript ceiling, and Godot `Expression` as a reference. Compile time is `setup_usec` and is not part of the batch times. The warm pass is a second full scan.

The RPN reader binds fact keys to slots while the fixture is built, then walks a load-time plan. That plan is not saved, and the compiled opcodes stay as documented. Setup time still includes the bind.

`bench_dirty.gd` then copies that fixture and times a dependency-index tick. For 1, 10, and 100 changed facts it picks slots from `WyrdRng` sub-seed `0x57595245` plus the changed-fact count, calls `WyrdDepIndex.affected`, and re-checks only those conditions. The first tick is `dirty.<n>.cold`. The next 1000 ticks are the warm means: `dirty.<n>.affected_mean`, `dirty.<n>.index_usec`, `dirty.<n>.eval_usec`, and `dirty.<n>.tick_usec` for the RPN walker. `ceiling_eval_usec` and `ceiling_tick_usec` are the hand-written loop over the same subset. `index_build_usec`, `index_entries`, and `index_keys` describe the index. After the timed ticks, a full scan must match the maintained results (`checksum_match`). Numbers and how to read them are in `docs/spikes/s0-condition-speed.md`.

`bench.gd` also runs `wyrd_ai_bench.gd` and writes its four rows under `ai` (`ai.packet`, `ai.validate`, `ai.present_overhead`, and `ai.cache_lookup`). The workload uses `WyrdFakeAIText` and the null provider only. No model is downloaded or run. The timings are recorded and are not checked.
