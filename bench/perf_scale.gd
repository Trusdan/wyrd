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
const HASH_FILE := "res://bench/scale_pack.sha256"
const GROUP := "harbor_council"
const DEPTH_GROUPS: PackedStringArray = ["harbor_watch", "ferry_crew", "harbor_council"]
const OWN_AGENT := "dock_hand_000"
const GROUP_AGENT := "dock_hand_001"
const BELIEF_FACT := "harbor.scale_00000"
const VERBS: PackedStringArray = ["paid", "arrived", "whispered"]


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
static func metrics() -> Array:
	return [
		{"budget": 20.0, "name": "compile.strict", "stat": "median", "unit": "s"},
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
		{"budget": 268435456.0, "name": "memory.peak", "stat": "median", "unit": "B"},
		{"budget": 268435456.0, "name": "memory.steady", "stat": "median", "unit": "B"},
		{"budget": 0.02, "name": "director.query", "stat": "median", "unit": "s"},
		{"budget": 0.05, "name": "director.why_not", "stat": "median", "unit": "s"},
		{"budget": 40.0, "name": "compile.tie_lint", "stat": "median", "unit": "s"},
	]
