class_name WyrdPerfScale
extends RefCounted

## Shared knobs for the milestone bench.
##
## @experimental
## The full pack is the design scale. Smoke is exactly one tenth of each count.
## Storylets live in a sibling directory so the quest pack stays what it was.
## Absolute budgets stay warnings until they are confirmed.

const SEED := 0x57595244
const WARMUPS := 2
const FULL_SAMPLES := 7
const SMOKE_SAMPLES := 3
const TICKS_PER_SAMPLE := 8
const TICK_TOUCHES := 16
const BELIEVE_CALLS := 10000
const PERCEIVE_BATCH := 32
const QUERY_BATCH := 32
const WHY_BATCH := 32
const MERGE_BUCKETS := 32
const QUERY_SPEAKER := "dock_hand_000"
const QUERY_TOPIC := "rumor.scale_00"
## Filtered snapshot page. The prefix matches world facts `harbor.scale_00000`
## and the following facts that share that stem. Limit 0 would return the rest.
const SNAPSHOT_PREFIX := "harbor.scale_000"
const SNAPSHOT_OFFSET := 0
const SNAPSHOT_LIMIT := 50
const HASH_FILE := "res://bench/scale_pack.sha256"
const GROUP := "harbor_council"
const DEPTH_GROUPS: PackedStringArray = ["harbor_watch", "ferry_crew", "harbor_council"]
const OWN_AGENT := "dock_hand_000"
const GROUP_AGENT := "dock_hand_001"
const BELIEF_FACT := "harbor.scale_00000"
const VERBS: PackedStringArray = ["paid", "arrived", "whispered"]
## Proposed warning for memory.peak and memory.resident. 384 MiB, sized for an 8 GB laptop.
## The bench still only warns on this budget.
const MEMORY_PEAK_BUDGET := 402653184.0
## Deed [code]within[/code] window for the index-versus-scan pair. The clock sits
## on the newest scale deed so the window is a slice of the log, not the whole log.
const DEED_WITHIN := 180
## Ticks spent draining the rumor pack when counting believers. The timed rumor
## samples do not drain the queue.
const RUMOR_DRAIN_TICKS := 64
const COARSE_STRIDE := 5
const COARSE_PLACE := "gullhaven"
const PRECISE_PLACE := "dock"
const RUMOR_KIND := "friend"
const PRECISE_POLICY := "harbor_whisper"
const REACH_POLICY := "harbor_reach"
const MUTATION_FIELD := "harbor.toll_fate"
const MUTATION_TO := "waived"
const GAZETTE := "harbor_gazette"
const GAZETTE_FACT := "harbor.gazette"


static func profile(name: String) -> Dictionary:
	if name == "full":
		return {
			"deeds": 50000,
			"facts": 10000,
			"npcs": 500,
			"quests": 700,
			"speakers": 20,
			"storylets": 4000,
			"topics": 80,
		}
	if name == "smoke":
		return {
			"deeds": 5000,
			"facts": 1000,
			"npcs": 50,
			"quests": 70,
			"speakers": 2,
			"storylets": 400,
			"topics": 8,
		}
	return {}


static func samples_for(name: String) -> int:
	if name == "smoke":
		return SMOKE_SAMPLES
	return FULL_SAMPLES


## [code]stat[/code] is the value the budget and the regression ratio use.
## [code]absolute[/code] false means the 20% regression gate is the only judge.
## [code]compile.strict[/code] and [code]compile.tie_lint[/code] are developer-only.
static func metrics() -> Array:
	return [
		{"absolute": false, "budget": 20.0, "name": "compile.strict", "stat": "median", "unit": "s"},
		{"budget": 0.002, "name": "tick.recheck", "stat": "p95", "unit": "s"},
		{"budget": 0.000005, "name": "believes.own", "stat": "median", "unit": "s"},
		{"budget": 0.000005, "name": "believes.group", "stat": "median", "unit": "s"},
		{"budget": 0.00005, "name": "perceive.credibility", "stat": "median", "unit": "s"},
		{"budget": 0.0001, "name": "reputation.cached", "stat": "median", "unit": "s"},
		{"budget": 0.02, "name": "reputation.cold", "stat": "median", "unit": "s"},
		{"budget": 0.5, "name": "save.time", "stat": "median", "unit": "s"},
		{"budget": 10485760.0, "name": "save.bytes", "stat": "median", "unit": "B"},
		{"budget": 1.0, "name": "load.time", "stat": "median", "unit": "s"},
		{"budget": 2.0, "name": "compact.time", "stat": "median", "unit": "s"},
		{"budget": MEMORY_PEAK_BUDGET, "name": "memory.peak", "stat": "median", "unit": "B"},
		{"budget": 268435456.0, "name": "memory.steady", "stat": "median", "unit": "B"},
		{"budget": 0.02, "name": "director.query", "stat": "median", "unit": "s"},
		{"budget": 0.02, "name": "director.query_coverage", "stat": "median", "unit": "s"},
		{"budget": 0.05, "name": "director.why_not", "stat": "median", "unit": "s"},
		{"absolute": false, "budget": 40.0, "name": "compile.tie_lint", "stat": "median", "unit": "s"},
		# Full snapshot 767 ms, including the deferred pair index.
		{"budget": 1.5, "name": "debug.snapshot", "stat": "median", "unit": "s"},
		{"budget": 2.0, "name": "debug.snapshot_page", "stat": "median", "unit": "s"},
		{"budget": 0.1, "name": "debug.snapshot_section", "stat": "median", "unit": "s"},
		# Proposed from the full-profile medians after the M8 perf pass. They warn until Corey confirms them.
		# memory.quests: 164.5 MiB measured, ceiling 192 MiB.
		{"budget": 201326592.0, "name": "memory.quests", "stat": "median", "unit": "B"},
		# rumor.tick 4.21 ms and scheduler.tick 4.44 ms. A 64-hop tick is still over 2 ms.
		# Ceiling stays 12 ms. Not the frame warning.
		{"budget": 0.012, "name": "rumor.tick", "stat": "median", "unit": "s"},
		{"budget": 0.012, "name": "scheduler.tick", "stat": "median", "unit": "s"},
		# publish.issue 170 ms and deeds_known_to 122 ms.
		{"budget": 0.25, "name": "publish.issue", "stat": "median", "unit": "s"},
		{"budget": 0.2, "name": "deeds_known_to", "stat": "median", "unit": "s"},
		# Believer index 564 KiB, 363 B each, 54 KiB of JSON.
		{"budget": 786432.0, "name": "memory.believers", "stat": "median", "unit": "B"},
		{"budget": 512.0, "name": "memory.per_belief", "stat": "median", "unit": "B"},
		{"budget": 65536.0, "name": "save.believers", "stat": "median", "unit": "B"},
		# In-flight save 567 ms and 7.73 MiB, load 961 ms. Pair index is not built during import.
		{"budget": 0.75, "name": "save.flight", "stat": "median", "unit": "s"},
		{"budget": 9437184.0, "name": "save.flight_bytes", "stat": "median", "unit": "B"},
		{"budget": 1.2, "name": "load.flight", "stat": "median", "unit": "s"},
		# Indexed score 0.61 ms, full scan 14.5 ms.
		{"budget": 0.001, "name": "deeds.index", "stat": "median", "unit": "s"},
		{"budget": 0.025, "name": "deeds.scan", "stat": "median", "unit": "s"},
		{"budget": MEMORY_PEAK_BUDGET, "name": "memory.resident", "stat": "median", "unit": "B"},
	]
