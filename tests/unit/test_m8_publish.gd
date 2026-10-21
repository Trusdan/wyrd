extends GutTest

## Periodic issues. The deed row stays. The frozen line is a fact.


const _QUERY := """
language 1
facts
  harbor.toll_fate : symbol stored
quest harbor_guild "The Harbor Guild"
  stage post
"""

const _HOUR := """
language 1
facts
  harbor.toll_fate : symbol stored
  harbor.gazette : symbol stored
quest harbor_guild "The Harbor Guild"
  stage post
document harbor_gazette "Harbor Gazette" publishes_by harbor_guild every 1 hour delay 1 hour
  claim harbor.toll_fate
  fact harbor.gazette
  verb whispered
  fragment when held(harbor_guild, harbor.toll_fate)
    slant lost_at_sea
"""

const _MINUTE := """
language 1
facts
  harbor.toll_fate : symbol stored
  harbor.gazette : symbol stored
quest harbor_guild "The Harbor Guild"
  stage post
document harbor_gazette "Harbor Gazette" publishes_by harbor_guild every 1 minute delay 1 minute
  claim harbor.toll_fate
  fact harbor.gazette
  verb whispered
"""


func test_deeds_known_to_uses_the_witness_index() -> void:
	var runtime := _boot(_QUERY, 4)
	_guild(runtime, PackedStringArray(["dock_hand", "ferry_master"]))
	_host(runtime).spatial.set_perception(&"dock_hand", &"heard")
	_host(runtime).spatial.set_perception(&"ferry_master", &"saw")
	_host(runtime).spatial.set_perception(&"net_mender", &"saw")
	_witness(runtime, &"whispered", PackedStringArray(["dock_hand"]))
	_witness(runtime, &"whispered", PackedStringArray(["net_mender"]))
	runtime.tick(10)
	_witness(runtime, &"whispered", PackedStringArray(["ferry_master"]))
	_witness(runtime, &"told", PackedStringArray(["dock_hand"]))
	var all := runtime.deeds_known_to(&"harbor_guild", 0, &"")
	assert_eq(_ids(all), [1, 3, 4])
	assert_eq(String(all[0]["mode"]), "believed")
	assert_eq(String(all[0]["verb"]), "whispered")
	assert_eq(all[0]["knowers"], [{"layer": "believed", "who": "dock_hand"}])
	assert_eq(String(all[1]["mode"]), "known")
	var ferry_knowers: Array = all[1]["knowers"]
	assert_eq(String(ferry_knowers[0]["who"]), "ferry_master")
	var later := runtime.deeds_known_to(&"harbor_guild", 10, &"")
	assert_eq(_ids(later), [3, 4])
	var whispered := runtime.deeds_known_to(&"harbor_guild", 0, &"whispered")
	assert_eq(_ids(whispered), [1, 3])
	assert_eq(runtime.deeds_known_to(&"harbor_guild", 0, &"paid").size(), 0)
	assert_eq(runtime.deeds_known_to(&"", 0, &"").size(), 0)


func test_a_mutated_belief_beats_the_world_fact_and_the_deed_stays() -> void:
	var runtime := _arm(_boot(_HOUR, 4))
	runtime.facts.set_in(&"harbor.toll_fate", &"waived", &"believed/dock_hand")
	runtime.facts.set_in(&"harbor.toll_fate", &"paid", &"believed/ferry_master")
	var deed := runtime.deeds.row_at(0)
	runtime.trace.enabled = true
	runtime.tick(60)
	var lines := _lines(runtime)
	assert_eq(lines.size(), 1)
	assert_eq(lines[0], "harbor_gazette#1 due=60 deeds=1 ids=1 claim=waived source=belief")
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	assert_eq(runtime.deeds.row_at(0)["verb"], deed["verb"])
	assert_eq(runtime.deeds.row_at(0)["actor"], deed["actor"])
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	var again := _arm(_boot(_HOUR, 29))
	again.facts.set_in(&"harbor.toll_fate", &"waived", &"believed/dock_hand")
	again.facts.set_in(&"harbor.toll_fate", &"paid", &"believed/ferry_master")
	again.tick(60)
	assert_eq(_lines(again), lines)


func test_a_belief_without_a_witness_does_not_add_a_deed() -> void:
	var runtime := _boot(_HOUR, 4)
	_guild(runtime, PackedStringArray(["ferry_master"]))
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	runtime.facts.set_in(&"harbor.toll_fate", &"paid", &"believed/ferry_master")
	_host(runtime).spatial.set_perception(&"net_mender", &"heard")
	_witness(runtime, &"whispered", PackedStringArray(["net_mender"]))
	runtime.tick(60)
	assert_eq(_lines(runtime), ["harbor_gazette#1 due=60 deeds=0 ids= claim=paid source=belief"])
	assert_eq(runtime.deeds.row_at(0)["verb"], &"whispered")


func test_known_is_used_when_nobody_believes() -> void:
	var runtime := _arm(_boot(_HOUR, 4))
	runtime.facts.set_in(&"harbor.toll_fate", &"stolen", &"known/ferry_master")
	runtime.tick(60)
	assert_eq(_lines(runtime), ["harbor_gazette#1 due=60 deeds=1 ids=1 claim=stolen source=known"])
	var world := _arm(_boot(_HOUR, 4))
	world.tick(60)
	assert_eq(_lines(world), ["harbor_gazette#1 due=60 deeds=1 ids=1 claim=lost_at_sea source=world"])


func test_held_slant_wins_and_the_deed_stays() -> void:
	var runtime := _arm(_boot(_HOUR, 4))
	runtime.facts.set_in(&"harbor.toll_fate", &"waived", &"believed/dock_hand")
	runtime.facts.set_in(&"harbor.toll_fate", &"lost_at_sea", &"held/harbor_guild")
	var deed := runtime.deeds.row_at(0)
	runtime.tick(60)
	assert_eq(_lines(runtime), ["harbor_gazette#1 due=60 deeds=1 ids=1 claim=lost_at_sea source=slant"])
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"waived")
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	assert_eq(runtime.deeds.row_at(0)["id"], deed["id"])
	assert_eq(runtime.deeds.row_at(0)["verb"], deed["verb"])


func test_an_issue_window_stops_at_the_due_minute() -> void:
	var runtime := _arm(_boot(_HOUR, 4))
	runtime.tick(60)
	assert_eq(_lines(runtime)[0], "harbor_gazette#1 due=60 deeds=1 ids=1 claim=lost_at_sea source=world")
	_witness(runtime, &"whispered", PackedStringArray(["dock_hand"]))
	runtime.tick(60)
	assert_eq(_lines(runtime)[1], "harbor_gazette#2 due=120 deeds=1 ids=2 claim=lost_at_sea source=world")


func test_nothing_publishes_before_the_delay() -> void:
	var runtime := _boot(_HOUR, 4)
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(runtime.now_minutes(), 0)
	assert_null(runtime.facts.get(&"harbor.gazette"))
	assert_eq(runtime.scheduler().carry("publish"), 0)
	assert_eq(_rows(runtime, "publish").size(), 0)
	assert_eq(runtime.config().publish_catchup_max, 3)


func test_thirty_and_one_forty_four_fps_match() -> void:
	var slow := _drive(30)
	var fast := _drive(144)
	var whole := _drive(0)
	assert_eq(_lines(slow), _lines(fast))
	assert_eq(_lines(slow), _lines(whole))
	assert_eq(_lines(slow), [
		"harbor_gazette#1 due=1 deeds=0 ids= claim=lost_at_sea source=world",
		"harbor_gazette#2 due=2 deeds=0 ids= claim=lost_at_sea source=world",
		"harbor_gazette#3 due=3 deeds=0 ids= claim=lost_at_sea source=world",
	])
	assert_eq(_publish_keys(slow), _publish_keys(fast))
	assert_eq(_publish_keys(slow), _publish_keys(whole))
	var early := _drive(-1)
	assert_null(early.facts.get(&"harbor.gazette"))
	assert_eq(_rows(early, "publish").size(), 0)


func test_a_time_jump_publishes_the_oldest_three() -> void:
	var runtime := _boot(_HOUR, 4)
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	_host(runtime).clock.set_minutes(600)
	runtime.trace.enabled = true
	runtime.tick(0)
	assert_eq(runtime.now_minutes(), 600)
	assert_eq(_lines(runtime), [
		"harbor_gazette#1 due=60 deeds=0 ids= claim=lost_at_sea source=world",
		"harbor_gazette#2 due=120 deeds=0 ids= claim=lost_at_sea source=world",
		"harbor_gazette#3 due=180 deeds=0 ids= claim=lost_at_sea source=world",
	])
	assert_eq(_skips(runtime), _skip_span(4, 240, 7))
	assert_eq(_rows(runtime, "publish").size(), 3)
	assert_eq(String(_rows(runtime, "publish")[0]["issue"]), "harbor_gazette#1")
	assert_eq(int(_rows(runtime, "publish")[2]["deeds"]), 0)
	runtime.tick(0)
	assert_eq(_lines(runtime).size(), 3)
	assert_eq(_skips(runtime), _skip_span(4, 240, 7))


func test_catchup_zero_publishes_nothing() -> void:
	var runtime := _boot(_HOUR, 4)
	runtime.config().publish_catchup_max = 0
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	_host(runtime).clock.set_minutes(600)
	runtime.tick(0)
	assert_eq(_lines(runtime), [])
	assert_eq(_skips(runtime), _skip_span(1, 60, 10))
	assert_eq(runtime.scheduler().carry("publish"), 0)
	runtime.tick(0)
	assert_eq(_lines(runtime), [])
	assert_eq(_skips(runtime).size(), 10)
	runtime.config().publish_catchup_max = -2
	runtime.tick(0)
	assert_eq(_lines(runtime), [])
	assert_eq(_skips(runtime).size(), 10)


func test_carry_publishes_one_issue_per_unit() -> void:
	var runtime := _boot(_HOUR, 4)
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	runtime.config().scheduler_work_per_tick = 1
	runtime.config().scheduler_share_waits = 0
	runtime.config().scheduler_share_rumor = 0
	runtime.config().scheduler_share_publish = 1
	runtime.config().scheduler_share_cache = 0
	_host(runtime).clock.set_minutes(600)
	runtime.tick(0)
	assert_eq(_lines(runtime), ["harbor_gazette#1 due=60 deeds=0 ids= claim=lost_at_sea source=world"])
	assert_eq(_skips(runtime), _skip_span(4, 240, 7))
	assert_eq(runtime.scheduler().carry("publish"), 2)
	runtime.tick(0)
	runtime.tick(0)
	assert_eq(_lines(runtime).size(), 3)
	assert_eq(_lines(runtime)[2], "harbor_gazette#3 due=180 deeds=0 ids= claim=lost_at_sea source=world")
	assert_eq(runtime.scheduler().carry("publish"), 0)
	runtime.tick(0)
	assert_eq(_lines(runtime).size(), 3)


func test_publish_trace_is_filterable() -> void:
	var quiet := _boot(_HOUR, 4)
	quiet.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	quiet.trace.enabled = false
	quiet.tick(60)
	assert_eq(_rows(quiet, "publish").size(), 0)
	var runtime := _boot(_HOUR, 4)
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	runtime.trace.enabled = true
	runtime.trace.prefix = "harbor_gazette"
	runtime.tick(60)
	var lines := _rows(runtime, "publish")
	assert_eq(lines.size(), 1)
	assert_eq(String(lines[0]["document"]), "harbor_gazette")
	assert_eq(String(lines[0]["issue"]), "harbor_gazette#1")
	assert_eq(String(lines[0]["path"]), "harbor_gazette")
	assert_eq(String(lines[0]["key"]), "harbor_gazette#1")
	assert_eq(String(lines[0]["who"]), "harbor_guild")
	assert_eq(int(lines[0]["deeds"]), 0)
	assert_eq(String(lines[0]["kind"]), "publish")
	var group := _boot(_HOUR, 4)
	group.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	group.trace.enabled = true
	group.trace.prefix = "harbor_guild"
	group.tick(60)
	assert_eq(_rows(group, "publish").size(), 1)
	var missed := _boot(_HOUR, 4)
	missed.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	missed.trace.enabled = true
	missed.trace.prefix = "no_such"
	missed.tick(60)
	assert_eq(_rows(missed, "publish").size(), 0)
	assert_eq(missed.facts.get(&"harbor.gazette"), runtime.facts.get(&"harbor.gazette"))


func test_replay_skips_publish() -> void:
	var runtime := _boot(_HOUR, 4)
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	runtime.trace.enabled = true
	runtime.tick(60)
	var recorded: Array = []
	for row in runtime.trace.snapshot():
		if String(row["kind"]) == "publish":
			recorded.append(row)
	assert_eq(recorded.size(), 1)
	var fresh := _boot(_HOUR, 4)
	fresh.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	fresh.trace.enabled = true
	WyrdTrace.replay(fresh, recorded)
	assert_null(fresh.facts.get(&"harbor.gazette"))
	assert_eq(_rows(fresh, "publish").size(), 0)
	WyrdTrace.replay(runtime, recorded)
	assert_eq(_lines(runtime).size(), 1)


func test_save_keeps_the_frozen_fact_and_drops_the_queue() -> void:
	var runtime := _boot(_HOUR, 4)
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	runtime.trace.enabled = true
	runtime.tick(60)
	var frozen := String(runtime.facts.get(&"harbor.gazette"))
	var data := runtime.save_state()
	assert_eq(int(data["schema_version"]), 4)
	assert_false(data.has("publish"))
	assert_false(data.has("issues"))
	var raw := JSON.stringify(data)
	assert_false(raw.contains("issue\t"))
	assert_true(raw.contains("harbor_gazette#1"))
	var loaded := _boot(_HOUR, 1)
	loaded.trace.enabled = true
	loaded.trace.clear()
	var report := loaded.load_state(data)
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_rows(loaded, "publish").size(), 0)
	assert_eq(String(loaded.facts.get(&"harbor.gazette")), frozen)
	assert_eq(loaded.scheduler().carry("publish"), 0)
	loaded.tick(0)
	assert_eq(String(loaded.facts.get(&"harbor.gazette")), frozen)
	assert_eq(_rows(loaded, "publish").size(), 0)

	var queued := _boot(_HOUR, 4)
	queued.config().scheduler_work_per_tick = 0
	queued.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	_host(queued).clock.set_minutes(60)
	queued.tick(0)
	assert_null(queued.facts.get(&"harbor.gazette"))
	assert_gt(queued.scheduler().carry("publish"), 0)
	var pending := queued.save_state()
	assert_true(_publish_tokens(pending).has("issue\tharbor_gazette\t1\t60"))
	var resumed := _boot(_HOUR, 1)
	assert_true(resumed.load_state(JSON.parse_string(JSON.stringify(pending))).ok)
	assert_gt(resumed.scheduler().carry("publish"), 0)
	assert_null(resumed.facts.get(&"harbor.gazette"))
	resumed.config().scheduler_work_per_tick = 64
	_host(resumed).clock.set_minutes(60)
	resumed.tick(0)
	assert_eq(_lines(resumed), ["harbor_gazette#1 due=60 deeds=0 ids= claim=lost_at_sea source=world"])


func test_a_rumor_listener_adds_the_deed_at_the_adoption_minute() -> void:
	var runtime := _boot(_HOUR, 4)
	_policy(runtime, 1, 1.0)
	_link(runtime, "line_fisher", "dock_hand")
	_guild(runtime, PackedStringArray(["dock_hand"]))
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	runtime.perception_claim("harbor.toll_fate", &"stolen")
	runtime.deeds.record(&"whispered", &"line_fisher", &"", &"gullhaven")
	runtime.clear_perception_claim()
	assert_eq(runtime.deeds.witnesses_at(0).size(), 0)
	_host(runtime).clock.set_minutes(30)
	runtime.tick(0)
	assert_eq(runtime.now_minutes(), 30)
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_eq(int(runtime.deeds.row_at(0)["t"]), 0)
	var adopted := runtime.deeds_known_to(&"harbor_guild", 30, &"whispered")
	assert_eq(_ids(adopted), [1])
	assert_eq(int(adopted[0]["t"]), 30)
	assert_eq(String(adopted[0]["mode"]), "believed")
	assert_eq(adopted[0]["knowers"], [{"layer": "believed", "who": "dock_hand"}])
	assert_eq(_ids(runtime.deeds_known_to(&"harbor_guild", 0, &"whispered")), [1])
	assert_eq(runtime.deeds_known_to(&"harbor_guild", 31, &"whispered").size(), 0)
	runtime.rumors.clear_flight()
	assert_eq(_ids(runtime.deeds_known_to(&"harbor_guild", 30, &"whispered")), [1])
	var kept := runtime.save_state()
	var loaded := _boot(_HOUR, 1)
	assert_true(loaded.load_state(kept).ok)
	_guild(loaded, PackedStringArray(["dock_hand"]))
	var restored := loaded.deeds_known_to(&"harbor_guild", 30, &"whispered")
	assert_eq(_ids(restored), [1])
	assert_eq(int(restored[0]["t"]), 30)
	assert_eq(loaded.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	var bare: Dictionary = runtime.save_state()
	for row in bare["deeds"]["rows"]:
		row.erase("believers")
	var forgotten := _boot(_HOUR, 1)
	assert_true(forgotten.load_state(bare).ok)
	_guild(forgotten, PackedStringArray(["dock_hand"]))
	assert_eq(forgotten.deeds_known_to(&"harbor_guild", 0, &"whispered").size(), 0)
	assert_eq(forgotten.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	_host(runtime).clock.set_minutes(60)
	runtime.tick(0)
	assert_eq(_lines(runtime), ["harbor_gazette#1 due=60 deeds=1 ids=1 claim=stolen source=belief"])


func test_a_materialized_coarse_believer_adds_the_deed() -> void:
	var runtime := _boot(_HOUR, 4)
	_policy(runtime, 1, 1.0)
	_guild(runtime, PackedStringArray(["dock_hand"]))
	var host := _host(runtime)
	host.spatial.set_precision(&"gullhaven", &"coarse")
	host.spatial.set_place(&"dock_hand", &"gullhaven")
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	runtime.perception_claim("harbor.toll_fate", &"stolen")
	runtime.deeds.record(&"whispered", &"line_fisher", &"", &"gullhaven")
	runtime.clear_perception_claim()
	assert_eq(runtime.deeds.witnesses_at(0).size(), 0)
	runtime.tick(240)
	assert_eq(runtime.now_minutes(), 240)
	assert_eq(runtime.rumors.reach_level("1", &"gullhaven"), 4)
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"))
	assert_eq(runtime.deeds_known_to(&"harbor_guild", 0, &"whispered").size(), 0)
	assert_true(runtime.eval_bool(_compile(runtime, "believes(dock_hand, harbor.toll_fate)")))
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"stolen")
	assert_eq(int(runtime.deeds.row_at(0)["t"]), 0)
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	var known := runtime.deeds_known_to(&"harbor_guild", 240, &"whispered")
	assert_eq(_ids(known), [1])
	assert_eq(int(known[0]["t"]), 240)
	assert_eq(known[0]["knowers"], [{"layer": "believed", "who": "dock_hand"}])
	assert_eq(_ids(runtime.deeds_known_to(&"harbor_guild", 1, &"whispered")), [1])
	assert_eq(runtime.deeds_known_to(&"harbor_guild", 241, &"whispered").size(), 0)
	var kept := runtime.save_state()
	assert_false(kept.has("believers"))
	var loaded := _boot(_HOUR, 1)
	var report := loaded.load_state(kept)
	assert_push_error("harbor_toll")
	assert_true(report.ok, report.diagnostics.format())
	assert_true(report.diagnostics.format().contains("deed 1"), report.diagnostics.format())
	_guild(loaded, PackedStringArray(["dock_hand"]))
	var restored := loaded.deeds_known_to(&"harbor_guild", 240, &"whispered")
	assert_eq(_ids(restored), [1])
	assert_eq(int(restored[0]["t"]), 240)
	assert_eq(loaded.rumors.reach_level("1", &"gullhaven"), -1)


func test_a_mutated_rumor_belief_is_the_claim() -> void:
	var runtime := _boot(_HOUR, 4)
	var policy := WyrdRumorPolicy.new()
	policy.id = &"harbor_toll"
	policy.kinds = PackedStringArray(["friend"])
	policy.max_hops = 1
	policy.pass_chance = 1.0
	policy.mutations = [_change("harbor.toll_fate", Callable(self, &"_waive"), Callable(self, &"_keep_none"))]
	runtime.register_rumor_policy(policy)
	_link(runtime, "line_fisher", "dock_hand")
	_guild(runtime, PackedStringArray(["dock_hand", "ferry_master"]))
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	runtime.perception_claim("harbor.toll_fate", &"stolen")
	var deed := runtime.deeds.record(&"whispered", &"line_fisher", &"", &"gullhaven")
	runtime.clear_perception_claim()
	runtime.tick(0)
	assert_eq(deed, 1)
	assert_eq(runtime.facts.get_in(&"harbor.toll_fate", &"believed/dock_hand"), &"waived")
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"believed/ferry_master"))
	assert_null(runtime.facts.get_in(&"harbor.toll_fate", &"known/dock_hand"))
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")
	assert_eq(runtime.deeds.row_at(0)["verb"], &"whispered")
	assert_eq(runtime.deeds.row_at(0)["actor"], &"line_fisher")
	var known := runtime.deeds_known_to(&"harbor_guild", 0, &"whispered")
	assert_eq(_ids(known), [1])
	assert_eq(known[0]["knowers"], [{"layer": "believed", "who": "dock_hand"}])
	runtime.tick(60)
	assert_eq(_lines(runtime), ["harbor_gazette#1 due=60 deeds=1 ids=1 claim=waived source=belief"])
	assert_eq(runtime.deeds.row_at(0)["verb"], &"whispered")
	assert_eq(runtime.facts.get(&"harbor.toll_fate"), &"lost_at_sea")


func test_compaction_moves_believers_onto_the_newest_id() -> void:
	var runtime := _boot(_QUERY, 4)
	_guild(runtime, PackedStringArray(["dock_hand", "ferry_master"]))
	var first := runtime.deeds.record(&"whispered", &"line_fisher", &"", &"gullhaven")
	var second := runtime.deeds.record(&"whispered", &"line_fisher", &"", &"gullhaven")
	assert_eq(first, 1)
	assert_eq(second, 2)
	runtime.deeds.note_believer(first, &"dock_hand", 15)
	runtime.deeds.note_believer(second, &"dock_hand", 40)
	runtime.deeds.note_believer(second, &"ferry_master", 50)
	runtime.deeds.note_believer(first, &"ferry_master", 80)
	assert_eq(runtime.deeds.compact(), 1)
	assert_eq(int(runtime.deeds.row_at(0)["id"]), 2)
	assert_eq(runtime.deeds.index_of(1), -1)
	var early := runtime.deeds_known_to(&"harbor_guild", 15, &"whispered")
	assert_eq(_ids(early), [2])
	assert_eq(int(early[0]["t"]), 15)
	assert_eq(early[0]["knowers"], [
		{"layer": "believed", "who": "dock_hand"},
		{"layer": "believed", "who": "ferry_master"},
	])
	var later := runtime.deeds_known_to(&"harbor_guild", 16, &"whispered")
	assert_eq(int(later[0]["t"]), 50)
	assert_eq(later[0]["knowers"], [{"layer": "believed", "who": "ferry_master"}])
	assert_eq(runtime.deeds_known_to(&"harbor_guild", 51, &"whispered").size(), 0)
	var saved := runtime.save_state()
	var loaded := _boot(_QUERY, 1)
	assert_true(loaded.load_state(saved).ok)
	_guild(loaded, PackedStringArray(["dock_hand", "ferry_master"]))
	var restored := loaded.deeds_known_to(&"harbor_guild", 15, &"whispered")
	assert_eq(_ids(restored), [2])
	assert_eq(int(restored[0]["t"]), 15)
	assert_eq(restored[0]["knowers"], early[0]["knowers"])


func test_a_dropped_deed_loses_its_believer() -> void:
	var runtime := _boot(_QUERY, 4)
	_guild(runtime, PackedStringArray(["dock_hand", "ferry_master"]))
	runtime.config().half_life_verbs = PackedStringArray(["whispered"])
	runtime.config().half_life_minutes = PackedFloat64Array([60.0])
	var gone := runtime.deeds.record(&"whispered", &"line_fisher", &"", &"gullhaven")
	var kept := runtime.deeds.record(
		&"told", &"line_fisher", &"", &"gullhaven",
		PackedStringArray(), 1.0, null, &"public", true
	)
	runtime.deeds.note_believer(gone, &"dock_hand", 5)
	runtime.deeds.note_believer(kept, &"ferry_master", 8)
	runtime.tick(1260)
	assert_eq(runtime.deeds.compact(), 1)
	assert_eq(int(runtime.deeds.row_at(0)["id"]), kept)
	assert_eq(runtime.deeds_known_to(&"harbor_guild", 0, &"whispered").size(), 0)
	var told := runtime.deeds_known_to(&"harbor_guild", 8, &"told")
	assert_eq(_ids(told), [kept])
	assert_eq(int(told[0]["t"]), 8)
	assert_eq(told[0]["knowers"], [{"layer": "believed", "who": "ferry_master"}])
	assert_eq(runtime.deeds_known_to(&"harbor_guild", 9, &"told").size(), 0)


func test_skipped_issues_match_across_save() -> void:
	var live := _jumped(4)
	var paused := _jumped(4)
	var data := paused.save_state()
	assert_eq(int(data["schema_version"]), 4)
	assert_false(data.has("publish"))
	assert_false(data.has("issues"))
	assert_false(data.has("believers"))
	var raw := JSON.stringify(data)
	assert_false(raw.contains("issue\t"))
	assert_true(raw.contains("skip harbor_gazette#4 due=240"))
	assert_true(raw.contains("harbor_gazette#1"))
	var loaded := _boot(_HOUR, 1)
	assert_true(loaded.load_state(data).ok)
	assert_eq(loaded.scheduler().carry("publish"), 0)
	live.trace.enabled = true
	loaded.trace.enabled = true
	live.trace.clear()
	loaded.trace.clear()
	_host(live).clock.set_minutes(720)
	_host(loaded).clock.set_minutes(720)
	live.tick(0)
	loaded.tick(0)
	var expected := [
		"harbor_gazette#1 due=60 deeds=0 ids= claim=lost_at_sea source=world",
		"harbor_gazette#2 due=120 deeds=0 ids= claim=lost_at_sea source=world",
		"harbor_gazette#3 due=180 deeds=0 ids= claim=lost_at_sea source=world",
		"harbor_gazette#11 due=660 deeds=0 ids= claim=lost_at_sea source=world",
		"harbor_gazette#12 due=720 deeds=0 ids= claim=lost_at_sea source=world",
	]
	assert_eq(_lines(live), expected)
	assert_eq(_lines(loaded), expected)
	assert_eq(_skips(live), _skip_span(4, 240, 7))
	assert_eq(_skips(loaded), _skips(live))
	assert_eq(String(loaded.facts.get(&"harbor.gazette")), String(live.facts.get(&"harbor.gazette")))
	assert_eq(_rows(live, "publish").size(), 2)
	assert_eq(_rows(loaded, "publish").size(), 2)
	live.tick(0)
	loaded.tick(0)
	assert_eq(String(loaded.facts.get(&"harbor.gazette")), String(live.facts.get(&"harbor.gazette")))
	assert_eq(_rows(loaded, "publish").size(), 2)


func test_a_document_parses_and_rejects_a_bad_header() -> void:
	var ok := _file(_HOUR)
	assert_eq(ok.codes, [], str(ok.messages))
	var document: WyrdDocumentDef = ok.unit.documents[0]
	assert_eq(document.id, "harbor_gazette")
	assert_eq(document.title, "Harbor Gazette")
	assert_eq(document.group, "harbor_guild")
	assert_eq(document.period_minutes, 60)
	assert_eq(document.delay_minutes, 60)
	assert_eq(document.claim_key, "harbor.toll_fate")
	assert_eq(document.fact_key, "harbor.gazette")
	assert_eq(document.verb_filter, "whispered")
	assert_eq(document.fragments.size(), 1)
	assert_eq(String(document.fragments[0]["slant"]), "lost_at_sea")
	var missing := _file("""
language 1
document harbor_gazette every 1 hour delay 1 hour
""")
	assert_true(missing.codes.has("E_DOCUMENT_SYNTAX"), str(missing.messages))
	assert_true(str(missing.messages).contains("publishes_by"))
	var week := _file("""
language 1
document harbor_gazette publishes_by harbor_guild every 1 week delay 1 hour
""")
	assert_true(week.codes.has("E_DOCUMENT_SYNTAX"), str(week.messages))
	assert_true(str(week.messages).contains("unknown duration unit"))
	var delay := _file("""
language 1
document harbor_gazette publishes_by harbor_guild every 1 hour
""")
	assert_true(delay.codes.has("E_DOCUMENT_SYNTAX"), str(delay.messages))
	assert_true(str(delay.messages).contains("needs delay"))
	var slant := _file("""
language 1
facts
  harbor.toll_fate : symbol stored
document harbor_gazette publishes_by harbor_guild every 1 hour delay 1 hour
  fragment
    slant lost_at_sea
""")
	assert_true(slant.codes.has("E_DOCUMENT_SYNTAX"), str(slant.messages))
	assert_true(str(slant.messages).contains("fragment needs when"))
	var twice := _file("""
language 1
document harbor_gazette publishes_by harbor_guild every 1 hour delay 1 hour
document harbor_gazette publishes_by harbor_guild every 1 day delay 1 hour
""")
	assert_true(twice.codes.has("E_DOCUMENT_DUPLICATE"), str(twice.messages))
	var reserved := _file("""
language 1
quest document "The Harbor Guild"
quest publishes_by "The Harbor Guild"
""")
	assert_eq(reserved.codes.count("E_RESERVED_WORD"), 2, str(reserved.messages))


func test_indexed_known_to_matches_the_scan() -> void:
	var runtime := _boot(_QUERY, 4)
	_guild(runtime, PackedStringArray(["dock_hand", "ferry_master"]))
	_host(runtime).spatial.set_perception(&"dock_hand", &"heard")
	_host(runtime).spatial.set_perception(&"ferry_master", &"saw")
	_witness(runtime, &"whispered", PackedStringArray(["dock_hand"]))
	runtime.tick(10)
	_witness(runtime, &"whispered", PackedStringArray(["ferry_master", "dock_hand"]))
	runtime.tick(20)
	runtime.deeds.note_believer(1, &"ferry_master", 25)
	var indexed := runtime.deeds_known_to(&"harbor_guild", 10, &"whispered")
	runtime.deeds.set_lookup(false)
	var scanned := runtime.deeds_known_to(&"harbor_guild", 10, &"whispered")
	assert_eq(JSON.stringify(indexed), JSON.stringify(scanned))
	runtime.deeds.set_lookup(true)
	var wider := runtime.deeds_known_to(&"harbor_guild", 0, &"")
	runtime.deeds.set_lookup(false)
	assert_eq(JSON.stringify(wider), JSON.stringify(runtime.deeds_known_to(&"harbor_guild", 0, &"")))
	assert_gt(indexed.size(), 0)


func test_sliced_issue_matches_one_shot_and_restarts_on_load() -> void:
	var runtime := _arm(_boot(_HOUR, 4))
	for _index in 6:
		_witness(runtime, &"whispered", PackedStringArray(["dock_hand"]))
	runtime.facts.set_in(&"harbor.toll_fate", &"waived", &"believed/dock_hand")
	runtime.restore_clock(4, 60)
	runtime.config().publish_slice_rows = 1
	runtime.publish.enqueue_due()
	var tokens := runtime.scheduler().carry_tokens("publish")
	assert_eq(tokens.size(), 1)
	var token := String(tokens[0])
	runtime.trace.enabled = true
	assert_false(runtime.publish.issue(token))
	assert_eq(_lines(runtime).size(), 0)
	var steps := 1
	while steps < 30 and not runtime.publish.issue(token):
		steps += 1
	assert_gt(steps, 1)
	var line: String = _lines(runtime)[0]
	var phases: Array = []
	for row in _rows(runtime, "publish_cursor"):
		phases.append(String(row["phase"]))
	assert_eq(String(phases[0]), "start")
	assert_eq(String(phases[phases.size() - 1]), "done")
	var whole := _arm(_boot(_HOUR, 4))
	for _index in 6:
		_witness(whole, &"whispered", PackedStringArray(["dock_hand"]))
	whole.facts.set_in(&"harbor.toll_fate", &"waived", &"believed/dock_hand")
	whole.tick(60)
	assert_eq(_lines(whole), [line])
	var paused := _arm(_boot(_HOUR, 4))
	for _index in 6:
		_witness(paused, &"whispered", PackedStringArray(["dock_hand"]))
	paused.facts.set_in(&"harbor.toll_fate", &"waived", &"believed/dock_hand")
	paused.restore_clock(4, 60)
	paused.config().publish_slice_rows = 1
	paused.publish.enqueue_due()
	var paused_token := String(paused.scheduler().carry_tokens("publish")[0])
	assert_false(paused.publish.issue(paused_token))
	var data := paused.save_state()
	assert_eq(int(data["schema_version"]), 4)
	var flight: Dictionary = data["flight"]
	var publish: Dictionary = flight["publish"]
	assert_eq(String(publish["cursor"]), paused_token)
	assert_true(publish.has("beliefs"))
	assert_true(publish.has("claim"))
	var loaded := _boot(_HOUR, 4)
	assert_true(loaded.load_state(data).ok)
	# Group membership lives on the host, so a load does not bring it back.
	_guild(loaded, PackedStringArray(["dock_hand", "ferry_master"]))
	loaded.config().publish_slice_rows = 1
	loaded.trace.enabled = true
	loaded.trace.clear()
	var resumed := String(loaded.scheduler().carry_tokens("publish")[0])
	var guard := 0
	while guard < 30 and not loaded.publish.issue(resumed):
		guard += 1
	assert_eq(_lines(loaded), [line])
	var restarted: Array = _rows(loaded, "publish_cursor")
	assert_eq(String(restarted[0]["phase"]), "resume")
	assert_eq(loaded.scheduler().carry("publish"), 1)
	assert_false(String(loaded.facts.get(&"harbor.gazette")).contains("skip "))


func test_mid_issue_save_keeps_the_frozen_snapshot() -> void:
	var line := _late_belief_line(false, 1, false)
	for point in [1, 2, 3]:
		assert_eq(_late_belief_line(true, point, false), line, "slice %d" % point)
	assert_ne(_late_belief_line(true, 1, true), line)


func _late_belief_line(do_save: bool, point: int, drop_beliefs: bool) -> String:
	var runtime := _arm(_boot(_HOUR, 4))
	for _index in 6:
		_witness(runtime, &"whispered", PackedStringArray(["dock_hand"]))
	runtime.facts.set_in(&"harbor.toll_fate", &"waived", &"believed/dock_hand")
	runtime.restore_clock(4, 60)
	runtime.config().publish_slice_rows = 1
	runtime.publish.enqueue_due()
	var token := String(runtime.scheduler().carry_tokens("publish")[0])
	var slices := 0
	while slices < 30:
		slices += 1
		var done := runtime.publish.issue(token)
		if slices == point and not done:
			runtime.deeds.note_believer(1, &"ferry_master", 60)
			runtime.facts.set_in(&"harbor.toll_fate", &"stolen", &"believed/dock_hand")
			if do_save:
				return _load_open_issue(runtime, drop_beliefs)
		if done:
			break
	return String(_lines(runtime)[0])


func _load_open_issue(runtime: WyrdRuntime, drop_beliefs: bool) -> String:
	var data := runtime.save_state()
	var publish: Dictionary = data["flight"]["publish"]
	assert_true(publish.has("beliefs"))
	if drop_beliefs:
		publish.erase("beliefs")
		publish.erase("claim")
		data["flight"]["publish"] = publish
	var loaded := _boot(_HOUR, 4)
	assert_true(loaded.load_state(data).ok)
	_guild(loaded, PackedStringArray(["dock_hand", "ferry_master"]))
	loaded.config().publish_slice_rows = 1
	loaded.trace.enabled = true
	loaded.trace.clear()
	var resumed := String(loaded.scheduler().carry_tokens("publish")[0])
	var guard := 0
	while guard < 30 and not loaded.publish.issue(resumed):
		guard += 1
	var phases: Array = _rows(loaded, "publish_cursor")
	assert_eq(String(phases[0]["phase"]), "restart" if drop_beliefs else "resume")
	return String(_lines(loaded)[0])


func _arm(runtime: WyrdRuntime) -> WyrdRuntime:
	_guild(runtime, PackedStringArray(["dock_hand", "ferry_master"]))
	_host(runtime).spatial.set_perception(&"dock_hand", &"heard")
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	_witness(runtime, &"whispered", PackedStringArray(["dock_hand"]))
	return runtime


func _guild(runtime: WyrdRuntime, members: PackedStringArray) -> void:
	for member in members:
		_host(runtime).world.add_member(&"harbor_guild", StringName(member))


func _witness(runtime: WyrdRuntime, verb: StringName, witnesses: PackedStringArray) -> void:
	runtime.deeds.record(verb, &"line_fisher", &"", &"gullhaven", PackedStringArray(), 1.0, witnesses)


func _drive(fps: int) -> WyrdRuntime:
	var runtime := _boot(_MINUTE, 11)
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	runtime.trace.enabled = true
	runtime.trace.clear()
	if fps < 0:
		runtime.tick(0)
	elif fps == 0:
		runtime.tick(3)
	else:
		for _frame in 3 * fps:
			runtime.tick(1.0 / float(fps))
	return runtime


func _boot(body: String, seed_value: int) -> WyrdRuntime:
	var path := "user://wyrd_m8_publish_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.set_meta(&"host", host)
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(seed_value)
	return runtime


func _host(runtime: WyrdRuntime) -> WyrdFakeHost:
	return runtime.get_meta(&"host") as WyrdFakeHost


func _policy(runtime: WyrdRuntime, hops: int, chance: float) -> void:
	var policy := WyrdRumorPolicy.new()
	policy.id = &"harbor_toll"
	policy.kinds = PackedStringArray(["friend"])
	policy.max_hops = hops
	policy.pass_chance = chance
	runtime.register_rumor_policy(policy)


func _link(runtime: WyrdRuntime, source: String, target: String) -> void:
	runtime.social.set_kind(StringName(source), StringName(target), &"friend")


func _jumped(seed_value: int) -> WyrdRuntime:
	var runtime := _boot(_HOUR, seed_value)
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	_host(runtime).clock.set_minutes(600)
	runtime.tick(0)
	return runtime


func _compile(runtime: WyrdRuntime, text: String) -> WyrdCompiledCondition:
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(
		text,
		runtime.content().schema,
		diagnostics,
		"sample.wyrd",
		1,
		1
	)
	assert_false(diagnostics.has_errors(), "%s %s" % [text, diagnostics.format()])
	return compiled


func _change(field: String, to: Variant, keep: Callable) -> Dictionary:
	return {"field": field, "keep_chance_fn": keep, "to": to}


func _keep_none(value: Variant, hop: int) -> float:
	if hop < 0 or value == null:
		return 1.0
	return 0.0


func _waive(value: Variant, hop: int) -> StringName:
	if hop < 0:
		return value
	return &"waived"


func _publish_tokens(data: Dictionary) -> Array:
	var flight: Variant = data.get("flight", {})
	if not (flight is Dictionary):
		return []
	var scheduler: Variant = (flight as Dictionary).get("scheduler", {})
	if not (scheduler is Dictionary):
		return []
	var tokens: Variant = (scheduler as Dictionary).get("publish", [])
	if tokens is Array:
		return tokens
	return []


func _fact_lines(runtime: WyrdRuntime) -> Array:
	var value: Variant = runtime.facts.get(&"harbor.gazette")
	if value == null:
		return []
	var rows: Array = []
	for line in String(value).split("\n"):
		if not line.is_empty():
			rows.append(line)
	return rows


func _lines(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for line in _fact_lines(runtime):
		if not String(line).begins_with("skip "):
			rows.append(line)
	return rows


func _skips(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for line in _fact_lines(runtime):
		if String(line).begins_with("skip "):
			rows.append(line)
	return rows


func _skip_span(first: int, due: int, count: int) -> Array:
	var rows: Array = []
	var number := first
	var minute := due
	for _step in count:
		rows.append("skip harbor_gazette#%d due=%d" % [number, minute])
		number += 1
		minute += 60
	return rows


func _ids(rows: Array) -> Array:
	var ids: Array = []
	for row in rows:
		ids.append(int(row["id"]))
	return ids


func _publish_keys(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	for line in _rows(runtime, "publish"):
		rows.append("%s %s %d" % [String(line["issue"]), String(line["who"]), int(line["deeds"])])
	return rows


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for item in runtime.trace.events:
		if String(item["kind"]) == kind:
			rows.append(item)
	return rows


func _file(text: String) -> Dictionary:
	var source := WyrdSource.new("sample.wyrd", text.strip_edges() + "\n")
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	var unit := WyrdStatements.new().compile(source, tree, diagnostics)
	var codes: Array = []
	var messages: Array = []
	for item in diagnostics.items:
		codes.append(String(item.code))
		messages.append(item.message)
	return {"codes": codes, "messages": messages, "unit": unit}
