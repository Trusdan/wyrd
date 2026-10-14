# Benchmark harness

`bench.gd` times N iterations of a placeholder workload: hash a fixed set of Gullhaven ids and mix in rolls from `WyrdRng`. It writes JSON (`elapsed_usec`, iteration count, a checksum, and the Wyrd and Godot versions).

The run is informational. CI does not fail on the timing.

The design's baseline (10k facts, 5k conditions) is deferred. Those systems are not in S0, and the spikes in `docs/spikes/` describe how that measurement will be taken.
