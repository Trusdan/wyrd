extends GutTest

## Kind-scaled deed deltas and derived group reputation.


const _BODY := """
language 1
facts
  player.coins : int stored
quest harbor_guild "The Harbor Guild"
  stage post
    ~ record deed paid(actor: player, target: ferry_master, place: gullhaven)
    waits_until false
scene room
  when reputation(player, harbor_guild) >= 70: narrator: Standing. #line:standing
  -> end
"""


func test_kind_scale_multiplies_the_deed_and_not_the_baseline() -> void:
	var runtime := _open()
	runtime.config().set_axis_delta(&"paid", &"affinity", 40.0)
	runtime.config().set_kind_scale(&"apprentice", &"affinity", 2.0)
	runtime.config().set_kind_scale(&"apprentice", &"affinity", 2.0)
	assert_eq(runtime.config().kind_scale(&"apprentice", &"affinity"), 2.0)
	assert_eq(runtime.config().kind_scale(&"patron", &"affinity"), 1.0)
	runtime.social.set_baseline(&"ferry_master", &"player", &"affinity", 10.0)
	runtime.social.set_kind(&"player", &"ferry_master", &"apprentice")
	runtime.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven")
	assert_eq(runtime.social.axis(&"ferry_master", &"player", &"affinity"), 50.0)
	runtime.social.clear_kind(&"player", &"ferry_master", &"apprentice")
	runtime.social.set_kind(&"ferry_master", &"player", &"apprentice")
	assert_eq(runtime.social.axis(&"ferry_master", &"player", &"affinity"), 90.0)
	runtime.social.set_kind(&"ferry_master", &"player", &"patron")
	runtime.config().set_kind_scale(&"patron", &"affinity", 0.5)
	assert_eq(runtime.social.axis(&"ferry_master", &"player", &"affinity"), 50.0)
	runtime.config().set_kind_scale(&"patron", &"affinity", 0.0)
	runtime.social.clear_kind(&"ferry_master", &"player", &"apprentice")
	assert_eq(runtime.social.axis(&"ferry_master", &"player", &"affinity"), 10.0)
	runtime.config().set_kind_scale(&"patron", &"affinity", -1.0)
	assert_eq(runtime.social.axis(&"ferry_master", &"player", &"affinity"), -30.0)
	runtime.social.clear_kind(&"ferry_master", &"player", &"patron")
	runtime.social.clear_kind(&"ferry_master", &"player", &"patron")
	assert_eq(runtime.social.axis(&"ferry_master", &"player", &"affinity"), 50.0)
	runtime.social.clear_baseline(&"ferry_master", &"player", &"affinity")
	runtime.social.clear_baseline(&"ferry_master", &"player", &"affinity")
	assert_eq(runtime.social.axis(&"ferry_master", &"player", &"affinity"), 40.0)
	assert_false(runtime.social.has_kind(&"ferry_master", &"player", &"apprentice"))


func test_reputation_is_the_mean_disposition() -> void:
	var runtime := _boot(_BODY)
	var host := _host(runtime)
	host.world.add_member(&"harbor_guild", &"ferry_master")
	host.world.add_member(&"harbor_guild", &"dock_apprentice")
	host.world.add_member(&"harbor_guild", &"player")
	host.world.add_member(&"harbor_guild", &"ferry_master")
	runtime.social.set_baseline(&"dock_apprentice", &"player", &"affinity", 20.0)
	runtime.trace.enabled = true
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 55.0)
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 55.0)
	var lines := _rows(runtime, "reputation")
	assert_eq(lines.size(), 2)
	assert_eq(String(lines[0]["subject"]), "player")
	assert_eq(String(lines[0]["group"]), "harbor_guild")
	assert_eq(String(lines[0]["who"]), "player")
	assert_eq(String(lines[0]["key"]), "harbor_guild")
	assert_eq(int(lines[0]["members"]), 2)
	assert_eq(float(lines[0]["value"]), 55.0)
	assert_true(_eval(runtime, "reputation(player, harbor_guild) == 55"))
	assert_true(_eval(runtime, "rel(ferry_master, dock_apprentice, apprentice)") == false)
	runtime.social.set_kind(&"ferry_master", &"dock_apprentice", &"apprentice")
	assert_true(_eval(runtime, "rel(ferry_master, dock_apprentice, apprentice)"))
	runtime.social.clear_kind(&"ferry_master", &"dock_apprentice", &"apprentice")
	assert_false(_eval(runtime, "rel(ferry_master, dock_apprentice, apprentice)"))
	assert_eq(runtime.social.reputation(&"player", &"missing"), 0.0)
	assert_eq(runtime.social.reputation(&"player", &""), 0.0)
	runtime.social.members_of = func(_group: StringName) -> Array:
		return ["ferry_master", "ferry_master", "player"]
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 50.0)
	assert_eq(int(_rows(runtime, "reputation")[-1]["members"]), 1)
	runtime.social.register_formula(func(_a: StringName, _b: StringName, _axes: Dictionary) -> int:
		return 80
	)
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 80.0)
	runtime.trace.prefix = "harbor_guild"
	var before := _rows(runtime, "reputation").size()
	runtime.social.reputation(&"player", &"harbor_guild")
	assert_eq(_rows(runtime, "reputation").size(), before + 1)
	runtime.trace.prefix = "dock_apprentice"
	runtime.social.reputation(&"player", &"harbor_guild")
	assert_eq(_rows(runtime, "reputation").size(), before + 1)
	runtime.trace.prefix = ""
	runtime.trace.enabled = false
	runtime.trace.events.clear()
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 80.0)
	assert_eq(runtime.trace.events.size(), 0)
	assert_null(runtime.facts.get(&"player.coins"))
	assert_null(runtime.facts.get_in(&"player.coins", &"known/ferry_master"))
	assert_null(runtime.facts.get_in(&"player.coins", &"believed/ferry_master"))


func test_save_keeps_kinds_and_reputation_is_not_a_bag() -> void:
	var runtime := _boot(_BODY)
	var host := _host(runtime)
	host.world.add_member(&"harbor_guild", &"ferry_master")
	host.world.add_member(&"harbor_guild", &"player")
	runtime.config().set_axis_delta(&"paid", &"affinity", 40.0)
	runtime.config().set_kind_scale(&"apprentice", &"affinity", 2.0)
	runtime.social.set_kind(&"ferry_master", &"player", &"apprentice")
	runtime.social.set_baseline(&"ferry_master", &"player", &"affinity", 10.0)
	runtime.tick(0)
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 95.0)
	var saved := runtime.save_state()
	assert_false(JSON.stringify(saved).contains("kind_scale"))
	assert_false(JSON.stringify(saved).contains("reputation"))
	var fresh := _boot(_BODY)
	_host(fresh).world.add_member(&"harbor_guild", &"ferry_master")
	_host(fresh).world.add_member(&"harbor_guild", &"player")
	fresh.config().set_axis_delta(&"paid", &"affinity", 40.0)
	fresh.config().set_kind_scale(&"apprentice", &"affinity", 2.0)
	fresh.trace.enabled = true
	assert_true(fresh.load_state(saved).ok)
	assert_eq(fresh.trace.events.size(), 0)
	assert_true(fresh.social.has_kind(&"ferry_master", &"player", &"apprentice"))
	assert_eq(fresh.social.reputation(&"player", &"harbor_guild"), 95.0)
	assert_true(_same(saved, fresh.save_state()))
	var other := _played(11)
	var again := _played(4)
	assert_eq(other.social.reputation(&"player", &"harbor_guild"), again.social.reputation(&"player", &"harbor_guild"))
	assert_eq(other.social.axis(&"ferry_master", &"player", &"affinity"), again.social.axis(&"ferry_master", &"player", &"affinity"))


func test_scene_wakes_when_reputation_crosses_the_line() -> void:
	var quiet := _boot(_BODY)
	_host(quiet).world.add_member(&"harbor_guild", &"ferry_master")
	quiet.tick(0)
	quiet.tick(0)
	assert_eq(_flag(quiet, "standing"), 0)
	assert_eq(quiet.social.reputation(&"player", &"harbor_guild"), 50.0)
	var runtime := _boot(_BODY)
	_host(runtime).world.add_member(&"harbor_guild", &"ferry_master")
	_host(runtime).world.add_member(&"harbor_guild", &"player")
	runtime.config().set_axis_delta(&"paid", &"affinity", 40.0)
	runtime.tick(0)
	assert_eq(_flag(runtime, "standing"), 0)
	runtime.tick(0)
	assert_eq(_flag(runtime, "standing"), 1)
	assert_eq(runtime.social.reputation(&"player", &"harbor_guild"), 70.0)


func test_bare_reputation_is_not_a_bool() -> void:
	var file := _file("""
language 1
scene room
  when reputation(player, harbor_guild): narrator: Standing. #line:standing
  -> end
""")
	assert_true(file.codes.has("E_NOT_BOOL"), str(file.messages))


func _played(seed_value: int) -> WyrdRuntime:
	var runtime := _open()
	runtime.start_new_game(seed_value)
	_host(runtime).world.add_member(&"harbor_guild", &"ferry_master")
	runtime.config().set_axis_delta(&"paid", &"affinity", 40.0)
	runtime.config().set_kind_scale(&"apprentice", &"affinity", 2.0)
	runtime.social.set_kind(&"ferry_master", &"player", &"apprentice")
	runtime.social.set_baseline(&"ferry_master", &"player", &"affinity", 10.0)
	runtime.deeds.record(&"paid", &"player", &"ferry_master", &"gullhaven")
	return runtime


func _open() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	runtime.set_meta(&"host", host)
	runtime.start_new_game(4)
	return runtime


func _boot(body: String) -> WyrdRuntime:
	var runtime := _open()
	var path := "user://wyrd_m5_reputation.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(4)
	return runtime


func _host(runtime: WyrdRuntime) -> WyrdFakeHost:
	return runtime.get_meta(&"host") as WyrdFakeHost


func _file(text: String) -> Dictionary:
	var source := WyrdSource.new("sample.wyrd", text)
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	var unit := WyrdStatements.new().compile(source, tree, diagnostics)
	var codes: Array = []
	var messages: Array = []
	for item in diagnostics.items:
		codes.append(String(item.code))
		messages.append(item.message)
	return {"codes": codes, "messages": messages, "unit": unit}


func _eval(runtime: WyrdRuntime, text: String) -> bool:
	var diagnostics := WyrdDiagnostics.new()
	var compiled := WyrdCondition.new().compile(text, runtime.content().schema, diagnostics, "sample.wyrd", 1, 1)
	assert_false(diagnostics.has_errors(), "%s %s" % [text, diagnostics.format()])
	return runtime.eval_bool(compiled)


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var rows: Array = []
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == kind:
			rows.append(row)
	return rows


func _flag(runtime: WyrdRuntime, record: String) -> int:
	var content := runtime.content()
	for i in content.conditions.size():
		if content.records[i] == record and content.sites[i] == "when":
			return int(runtime.condition_flags()[i])
	return -1


func _same(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key in left.keys():
			if not right.has(key) or not _same(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for i in left.size():
			if not _same(left[i], right[i]):
				return false
		return true
	return left == right
