# Milestone bench

`tools/perf_bench.sh` times the hot paths on a seeded Gullhaven scale pack. The pack is written to a temp directory and is not committed. `bench/scale_pack.sha256` is the full pack's hash.

```bash
tools/perf_bench.sh --profile smoke --head . --mode warn --out /tmp/wyrd-perf-smoke.json
tools/perf_bench.sh --profile full --head . --base /path/to/base --mode gate --out /tmp/wyrd-perf-full.json
tools/perf_bench.sh --profile smoke --head . --mode warn --bench-filter tick --out /tmp/wyrd-perf-tick.json
```

`--bench-filter` keeps metrics whose names start with that prefix. `--samples` overrides the sample count for a local run. CI does not pass it. The runner imports a checkout before the generator when `.godot/global_script_class_cache.cfg` is missing, so `class_name` scripts parse on a fresh tree.

Smoke is one tenth of the full pack: 70 quests, 1,000 facts, 50 NPCs, 5,000 deeds. Full is 700 quests, 10,000 facts, 500 NPCs, 50,000 deeds. There are no storylets. Each profile discards 2 warm-up runs, then takes 3 smoke samples or 7 full samples. The shell runs the base checkout and the head checkout in one job and alternates samples.

Pull requests do not run this suite. A metric more than 20% slower or larger than the base build fails a tag run and a manual dispatch. The same gate applies to the nightly run. A 10–20% gap warns. Absolute budgets warn until they are confirmed. A checksum that changes between samples fails the script.

The nightly schedule is 07:00 UTC. That run skips when `github.sha` on the default branch equals the `headSha` of the last successful scheduled run of `.github/workflows/perf.yml`. A lookup failure still runs the bench. Tag and manual runs do not use that skip. The tag run writes `bench/results/<tag>.json` and regenerates `bench/TREND.md` after a clean gate. Nightly and manual runs upload an artifact and do not commit.

Each log line is `perf <name> median=… p95=… delta=… verdict=…`. `delta` compares the judged statistic with the base build in this job: the median, or the p95 for `tick.recheck`. `n/a` means the base checkout has no `bench/perf_worker.gd`.
