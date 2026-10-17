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
	assert_false(String(runtime.facts.get(&"harbor.gazette")).contains("due=240"))
	assert_eq(_rows(runtime, "publish").size(), 3)
	assert_eq(String(_rows(runtime, "publish")[0]["issue"]), "harbor_gazette#1")
	assert_eq(int(_rows(runtime, "publish")[2]["deeds"]), 0)
	runtime.tick(0)
	assert_eq(_lines(runtime).size(), 3)


func test_catchup_zero_publishes_nothing() -> void:
	var runtime := _boot(_HOUR, 4)
	runtime.config().publish_catchup_max = 0
	runtime.facts.set(&"harbor.toll_fate", &"lost_at_sea")
	_host(runtime).clock.set_minutes(600)
	runtime.tick(0)
	assert_null(runtime.facts.get(&"harbor.gazette"))
	assert_eq(runtime.scheduler().carry("publish"), 0)
	runtime.config().publish_catchup_max = -2
	runtime.tick(0)
	assert_null(runtime.facts.get(&"harbor.gazette"))


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
	assert_eq(int(data["schema_version"]), 2)
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
	assert_false(JSON.stringify(pending).contains("issue\t"))
	var resumed := _boot(_HOUR, 1)
	assert_true(resumed.load_state(pending).ok)
	assert_eq(resumed.scheduler().carry("publish"), 0)
	assert_null(resumed.facts.get(&"harbor.gazette"))
	resumed.config().scheduler_work_per_tick = 64
	_host(resumed).clock.set_minutes(60)
	resumed.tick(0)
	assert_eq(_lines(resumed), ["harbor_gazette#1 due=60 deeds=0 ids= claim=lost_at_sea source=world"])


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


func _lines(runtime: WyrdRuntime) -> Array:
	var value: Variant = runtime.facts.get(&"harbor.gazette")
	if value == null:
		return []
	var rows: Array = []
	for line in String(value).split("\n"):
		if not line.is_empty():
			rows.append(line)
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
