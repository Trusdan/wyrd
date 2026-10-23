# Milestone bench

`tools/perf_bench.sh` times the hot paths on a seeded Gullhaven scale pack. The pack is written to a temp directory and is not committed. `bench/scale_pack.sha256` is the hash of the full quest pack and its storylet sibling. It does not cover `<pack>_rumors/`.

```bash
tools/perf_bench.sh --profile smoke --head . --mode warn --out /tmp/wyrd-perf-smoke.json
tools/perf_bench.sh --profile full --head . --base /path/to/base --mode warn --out /tmp/wyrd-perf-full.json
tools/perf_bench.sh --profile smoke --head . --mode warn --bench-filter tick --out /tmp/wyrd-perf-tick.json
```

`--mode gate` fails a regression over 20% for a local check; hosted runs never use it.

`--bench-filter` keeps metrics whose names start with that prefix. `--samples` overrides the sample count for a local run. CI does not pass it. The runner imports a checkout before the generator when `.godot/global_script_class_cache.cfg` is missing, so `class_name` scripts parse on a fresh tree.

Smoke is one tenth of the full pack: 70 quests, 1,000 facts, 50 NPCs, 5,000 deeds, 400 storylets, 8 topics, 2 speakers. Full is 700 quests, 10,000 facts, 500 NPCs, 50,000 deeds, 4,000 storylets, 80 topics, 20 speakers. Storylets are written to `<pack>_storylets/`, a sibling the quest-pack check does not walk. Each profile discards 2 warm-up runs, then takes 3 smoke samples or 7 full samples. The shell runs the base checkout and the head checkout in one job and alternates samples. A base harness that does not know a metric is recorded as head only. `director.query` is the median seconds for one seeded topic selection, timed over 32 topics, with coverage off. The link-time storylet index does not change those winners, so the recorded checksum stays the v0.5.0-m7 value. Witness and hour-bucket deed indexes do not change snapshot deed, social, or precedence rows, so those checksums stay the same. `director.query_coverage` is that same batch with coverage counting on for the timed queries only, then turned off. `director.why_not` explains the specific winner on `rumor.scale_00` for `dock_hand_000`, 32 times, and reports seconds per call. `compile.tie_lint` is `check --strict` on the storylet sibling, which runs the pairwise tie lint. `debug.snapshot` is one full `Wyrd.debug.snapshot()` call, in seconds, after a new game stores every scale fact and imports the deed log. `debug.snapshot_page` is one call with prefix `harbor.scale_000`, offset 0, and limit 50. The prefix is applied while rows are collected, and sections that were not requested are not built. `debug.snapshot_section` is that same page for the facts section only. Role, quest, and deed keys do not use that prefix, so their pages are empty when they are requested. Their budgets warn like the others.

The rumor sibling is `<pack>_rumors/`. `harbor.wyrd` is the scale gazette: `harbor_gazette` publishes for `harbor_council` once a day after a one-hour delay, and `harbor_toll` sets `harbor.toll_fate`. `graph.txt` is the relationship graph and the rumor policies. Each NPC is `dock_hand_NNN` and is friends with the next two. The first fifth stand in coarse `gullhaven`. The rest stand in precise `dock`. `harbor_reach` matches `arrived` and has no mutation. `harbor_whisper` matches `whispered`, allows two hops, and names a mutation of `harbor.toll_fate` to `waived` with keep chance 0. The worker supplies that callable. The nightly, tag, and manual workflow picks up every name in `WyrdPerfScale.metrics()`. A base harness that does not know one records it as head only.

`rumor.tick` is the median seconds of one `tick(0)` while that queue still has work. Reach tokens are queued ahead of the precise hops, and the rumor share is the whole 64-unit budget. `scheduler.tick` is the same median with the default shares 40, 12, 8, and 4, while rumor hops, one gazette issue, and cache refresh are all queued. `publish.issue` is one `harbor_gazette` issue over the scale deed log. The clock is the sum of the slices that finish that issue. One scheduler unit reads at most `publish_slice_rows` candidate rows (default 128). `deeds_known_to` is one `deeds_known_to(harbor_council, 0, whispered)` on that log. `memory.quests` is the `Performance.MEMORY_STATIC` growth from loading the quest pack and starting the game, before the deed import. `memory.believers` is the growth from replaying the drained pack's adoption pairs onto a fresh scale log. `memory.per_belief` is that growth divided by the pair count. `save.believers` is the UTF-8 byte difference of the deed export with the `believers` field and with it removed. `save.flight`, `save.flight_bytes`, and `load.flight` are a schema 4 save and load of the quest pack plus the scale deed log, with rumor jobs, reach rows, and one gazette token still queued. `reputation.cached` primes `reputation(player, harbor_council)` once, untimed, then averages 32 hits. `reputation.cold` times that call with the cache empty. `deeds.index` and `deeds.scan` are one `score_matching` call, averaged over 32 calls, inside a 180-minute window ending at the newest deed. The indexed score and the scanned score are the same value. `generator.propose` is one `propose` call, averaged over 4 passes of 32 offers, after one untimed proposal has built the cast index. `generator.cast_object` and `generator.cast_person` are one indexed `cast_pool` plus `pick_id`, averaged over 512 rounds, after one untimed cast. `generator.validate` is one private `_validate` of a proposal, averaged over 256 rounds. `generator.tick` is the median of eight `tick(0)` calls that each drain 32 offers into instances. `memory.generated` is the `Performance.MEMORY_STATIC` growth from creating the profile's generated instances. `save.generated_bytes` and `load.generated` are a schema 4 save and load of that world with the deed log and those instances. The bench world reports changes, so these casts use the cast-candidate index. The cold first proposal, cast, or tick after each boot is reported beside the warm median and is not the metric value. Those eight metrics use one warmup and five samples at full, and smoke uses the smaller of that count and the smoke count. `memory.resident` is the process high-water after every other sample. `memory.peak` stays the high-water through the `memory.peak` sample, which is still before the rumor samples, so its series stays comparable. `compile.strict` and `compile.tie_lint` are developer-only: the 20% regression gate judges them, and their absolute ceilings do not.

Each `ai.*` row boots its own small inline pack with a fake host and tracing off. The pack is the same in smoke and full, and it sits outside the scale pack, so `bench/scale_pack.sha256` does not change. `ai.packet` times `packet_for_line` for an opted-in bark (256 calls) and records the gossip packet beside it, which lists 5 deeds the player knows. `ai.validate` times `validate` on one passing line (256 calls) after a classifier that returns true. `ai.present_overhead` is the null-provider path: seconds per line for resetting a line view and calling `present` (1024 lines). Its extras show the authored loop (the same reset without calling `Wyrd.ai`), the fake-provider cache hit, and `null_delta` (null minus authored). `ai.cache_lookup` times a hit per lookup across 256 imported entries and 4 passes, and its extras show a miss loop over 256 packets that were not inserted.

Proposed ceilings, from the full-profile medians on the milestone run. Each one warns until Corey confirms it. A confirmed ceiling is an exit gate and still does not fail the run.

| metric | proposed ceiling | measured median | why |
| --- | --- | --- | --- |
| `memory.quests` | 192 MiB | 164.5 MiB | The compiled 700-quest pack. About 17% over the median. |
| `rumor.tick` | 8 ms | 4.21 ms | About 64 hops at 66 µs, about 2× the median. Warn-only until Corey confirms it. Not the 2 ms frame warning. |
| `scheduler.tick` | 8 ms | 4.44 ms | Same busy tick, with the default shares and a gazette issue. About 2× the median. Warn-only until Corey confirms it. |
| `publish.issue` | 0.25 s | 170 ms | About 1.5× the sum of the slices for one issue. |
| `deeds_known_to` | 0.20 s | 122 ms | About 1.6× the indexed walk. |
| `memory.believers` | 768 KiB | 564 KiB | Index growth for 1,590 adoption pairs. |
| `memory.per_belief` | 512 B | 363 B | That growth divided by the pair count. |
| `save.believers` | 64 KiB | 54 KiB | UTF-8 bytes added by the `believers` field. |
| `save.flight` | 0.75 s | 467 ms | About 1.6× a schema 3 save with jobs, reach rows, and one gazette token queued. |
| `save.flight_bytes` | 9 MiB | 7.73 MiB | About 16% over that save. |
| `load.flight` | 1.2 s | 961 ms | Above the measured max of 970 ms. Pair indexing is deferred; the witness, hour, and believer indexes still build during import. |
| `deeds.index` | 1 ms | 0.61 ms | One indexed `score_matching` inside a 180-minute window. |
| `deeds.scan` | 25 ms | 14.5 ms | The same call with lookup off. |
| `debug.snapshot` | 1.5 s | 767 ms | About 2× a full snapshot. The deferred pair index is included. |
| `generator.propose` | 2 ms | 0.692 ms | The 2 ms frame warn for one proposal. Warn-only until it is confirmed. |
| `generator.cast_object` | 0.1 ms | 19.96 µs | About 2× the median is under 0.1 ms, so the floor is the ceiling. Warn-only until it is confirmed. |
| `generator.cast_person` | 0.1 ms | 19.95 µs | Same 0.1 ms floor. Warn-only until it is confirmed. |
| `generator.validate` | 0.11 ms | 54.11 µs | About 2× the median, rounded up. Warn-only until it is confirmed. |
| `generator.tick` | 100 ms | 45.30 ms | About 2× the median, rounded up. Warn-only until it is confirmed. Not the 2 ms frame warning. |
| `memory.generated` | 6 MiB | 3.667 MiB | About 1.5× the median, rounded up to a whole MiB. Warn-only until it is confirmed. |
| `save.generated_bytes` | 9 MiB | 7.512 MiB | The same envelope as `save.flight_bytes`. Warn-only until it is confirmed. |
| `load.generated` | 1.2 s | 1.003 s | The same envelope as `load.flight`. Warn-only until it is confirmed. |
| `memory.resident` | 384 MiB | 325 MiB | Same laptop warning as `memory.peak`. The full-run high water stayed under it. |
| `memory.peak` | 384 MiB | 272 MiB | Unchanged. This sample is still taken before the rumor metrics. |

These `ai.*` rows have no ceiling to confirm and are never an exit gate.

### Trend rows

| metric | what it times | judged by |
| --- | --- | --- |
| `ai.packet` | `packet_for_line` on one opted-in bark, with the gossip packet beside it | report-only ratio vs the base build; no absolute ceiling |
| `ai.validate` | `validate` on one passing line | report-only ratio vs the base build; no absolute ceiling |
| `ai.present_overhead` | the null-provider `present` path per line; extras show the authored loop, the fake-provider hit, and the difference | report-only ratio vs the base build; no absolute ceiling |
| `ai.cache_lookup` | a cache hit per lookup across 256 imported entries | report-only ratio vs the base build; no absolute ceiling |

Medians in the table come from the run named in the PR that set the ceiling; hosted tag results are in `bench/results/`.

Pull requests do not run this suite. The hosted workflow runs `--mode warn`. A metric more than 20% slower or larger than the base build, a 10–20% gap, and an absolute budget overage are reported in the log, the job summary, and the artifact, and they do not fail the job. Absolute budgets warn until they are confirmed. `memory.peak` and `memory.resident` warn at 384 MiB (402653184 bytes), sized for an 8 GB laptop. That budget is still proposed. `memory.peak` is the high-water mark of `Performance.MEMORY_STATIC` sampled before and after each metric through the `memory.peak` sample, plus once when the worker finishes preparing. That counter is Godot's static allocator for the whole process. A checksum that changes between samples fails the script.

The nightly schedule is 07:00 UTC. That run skips when `github.sha` on the default branch equals the `headSha` of the last successful scheduled run of `.github/workflows/perf.yml`. A lookup failure still runs the bench. Tag and manual runs do not use that skip. The tag run writes `bench/results/<tag>.json` and regenerates `bench/TREND.md` when the bench script exits 0, including when it reported warnings. A checksum that changes between samples still fails the job, and that run does not commit. Nightly and manual runs upload an artifact and do not commit. Hosted jobs stay on `ubuntu-24.04` until `ubuntu-26.04` is deliberately validated, because benchmark baselines are recorded per image. The v0.6.2-m8 baseline was recorded on ubuntu-24.04.

Each log line is `perf <name> median=… p95=… delta=… verdict=…`. `delta` compares the judged statistic with the base build in this job: the median, or the p95 for `tick.recheck`. `n/a` means the base checkout has no `bench/perf_worker.gd`.

## M11 performance pass

Full profile, 7 samples, `--mode warn`, one machine (Intel Xeon, 4 cores, Linux 6.12.94+, Godot 4.7.2). The base is `7725177`. Checksums matched the base on every metric below.

- Load: `load.time` median 2.395 s → 1.459 s, `load.flight` 2.492 s → 1.531 s, `load.generated` 2.583 s → 1.654 s. A save is deep-copied only when an alias or a missing stage rewrites a row. Deed rows that already match the shape skip the per-field sort; a mismatch still uses that walk, so the first message is the same.
- Tick: `tick.recheck` median 1.026 ms → 0.592 ms (p95 1.168 ms → 0.676 ms). Expiry walks only instances whose template can expire, in sorted id order. Host-call tracing allocates no depth object and builds no argument list while tracing is off. The depth counter is unchanged while tracing is on.

Found, not fixed. On a 50,000-deed save, `check_shape` is still about 242 ms after the deed path (about 914 ms before), and `check` still deep-copies the save once (about 184 ms). That is the gap that remains against the `v0.8.0-m10` `load.time` median of 0.950 s from the reference job. With AI and the generator idle, `ai.tick_prefetch` is about 3 µs and `_apply_generations` about 1 µs. `reputation.cold` and `director.why_not` did not reproduce the hosted trend: cold was −3.6% against `v0.6.4-m3` and +1.6% against `v0.8.0-m10`; why-not was +3.3% and +5.1%.

One smoke run of every metric, 3 samples, same base: `load.time` −46%, `tick.recheck` p95 −27%. Other medians stayed within about 12%. `deeds_known_to` median +12% with a faster p95, checksum unchanged. `perceive.credibility` warns on its budget and was slightly faster.
