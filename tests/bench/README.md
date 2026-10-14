# Benchmark harness

`bench.gd` writes JSON for two informational workloads. CI does not fail on the timing.

The placeholder workload hashes a fixed set of Gullhaven ids and mixes in rolls from `WyrdRng` (`elapsed_usec`, iteration count, a checksum, and the Wyrd and Godot versions).

The condition workload is fixed: 10k stored facts and 5k conditions from `WyrdRng` seed `0x57595244`. It times a compiled instruction walk, a hand-written GDScript ceiling, and Godot `Expression` as a reference. Compile time is `setup_usec` and is not part of the batch times. The warm pass is a second full scan. Numbers and how to read them are in `docs/spikes/s0-condition-speed.md`.
