extends GutTest

const _Harbor := preload("res://tests/scenario/m9_gullhaven.gd")
const _MANIFEST := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"
const _WORLD := "res://tests/fixtures/gullhaven_world.json"
const _DRY := "res://tests/fixtures/gullhaven_dry_run.txt"
const _SAVE := "user://m9_exit_save.json"


func test_every_template_passes_the_validators() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	var net := _propose(runtime, "nets", "net_delivery")
	assert_not_null(net, _gen(runtime))
	assert_eq(net.template, "net_delivery")
	assert_eq(net.instance, "net_delivery#1")
	assert_eq(str(net.casts.get("sender", "")), "line_fisher")
	assert_eq(_param(net, "net"), "net.mended")
	_assert_reject_is_assumes(runtime)
	assert_eq(runtime.generator.accept(net), "net_delivery#1")
	var caught := _propose(runtime, "catch", "stolen_catch")
	assert_not_null(caught, _gen(runtime))
	assert_eq(caught.instance, "stolen_catch#1")
	assert_true(str(caught.casts.get("victim", "")) != "")
	assert_eq(_param(caught, "catch"), "catch.day")
	assert_eq(runtime.generator.accept(caught), "stolen_catch#1")
	var cut := _propose(runtime, "line", "cut_line")
	assert_not_null(cut, _gen(runtime))
	assert_eq(cut.instance, "cut_line#1")
	assert_eq(str(cut.casts.get("witness", "")), "dock_apprentice")
	assert_eq(str(cut.casts.get("post", "")), "dock.bollard_north")
	assert_eq(runtime.generator.accept(cut), "cut_line#1")
	var walk := _propose(runtime, "walk", "night_walk")
	assert_not_null(walk, _gen(runtime))
	assert_eq(walk.instance, "night_walk#1")
	assert_eq(str(walk.casts.get("walker", "")), "visitor")
	assert_eq(_param(walk, "dest"), "harbor.north_steps")
	assert_eq(runtime.generator.accept(walk), "night_walk#1")
	runtime.facts.set(&"harbor.stew_wanted", true)
	var low := _propose(runtime, "stew-low", "tavern_stew_low", "low")
	assert_not_null(low, _gen(runtime))
	assert_eq(low.instance, "tavern_stew_low#1")
	assert_eq(str(low.casts.get("cook", "")), "tavern_owner")
	assert_eq(runtime.generator.accept(low), "tavern_stew_low#1")
	var mid := _propose(runtime, "stew-mid", "tavern_stew_mid", "mid")
	assert_not_null(mid, _gen(runtime))
	assert_eq(mid.instance, "tavern_stew_mid#1")
	assert_eq(runtime.generator.accept(mid), "tavern_stew_mid#1")
	runtime.facts.set(&"harbor.stew_tier", &"high")
	var high := _propose(runtime, "stew-high", "tavern_stew_high", "high")
	assert_not_null(high, _gen(runtime))
	assert_eq(high.instance, "tavern_stew_high#1")
	assert_eq(runtime.generator.accept(high), "tavern_stew_high#1")
	assert_eq(_rows(runtime, "gen_reject").size(), _assumes_rejects(runtime))
	var hooked := _boot()
	var deeds: WyrdRuntime = hooked["runtime"]
	deeds.facts.set(&"harbor.catch_missing", true)
	deeds.trace.enabled = true
	assert_eq(deeds.generator.pending_count(), 0)
	deeds.deeds.record(&"stole", &"player", &"line_fisher", &"gullhaven")
	assert_eq(deeds.generator.pending_count(), 0)
	deeds.config().scheduler_share_generate = 64
	deeds.deeds.record(&"stole", &"storm_watcher", &"line_fisher", &"gullhaven")
	assert_eq(deeds.generator.pending_count(), 1)
	deeds.tick(0)
	assert_eq(deeds.quests.status("stolen_catch#1"), &"active")
	assert_eq(deeds.quests.template_counter("stolen_catch"), 1)


func test_each_validator_rejects_a_gullhaven_template() -> void:
	var missing := _boot()
	var runtime: WyrdRuntime = missing["runtime"]
	var world: WyrdFakeWorld = missing["host"].world
	world.remove_entity(&"pier_fisher")
	world.deny_exists = &"line_fisher"
	runtime.trace.enabled = true
	assert_null(_propose(runtime, "gone", "net_delivery"))
	assert_eq(str(_rows(runtime, "gen_reject")[0].get("rule", "")), "exists")
	assert_eq(str(_rows(runtime, "gen_propose")[-1].get("reason", "")), "rejected")
	assert_eq(str(runtime.generator.why_not("net_delivery").get("reason", "")), "no_candidate")
	assert_eq(runtime.quests.template_counter("net_delivery"), 0)
	var guarded := _boot()
	var host: WyrdRuntime = guarded["runtime"]
	(guarded["host"].world as WyrdFakeWorld).remove_entity(&"pier_fisher")
	(guarded["host"].world as WyrdFakeWorld).set_protected(&"line_fisher", true)
	host.trace.enabled = true
	assert_null(_propose(host, "guard", "net_delivery"))
	assert_true(_has_rule(host, "protected"))
	assert_true(_has_key_suffix(host, ":1"))
	assert_eq(host.quests.template_counter("net_delivery"), 0)
	var known := _boot()
	var reader: WyrdRuntime = known["runtime"]
	reader.facts.set(&"harbor.boat_adrift", true)
	reader.facts.set_in(&"harbor.boat_adrift", false, &"known/player")
	reader.trace.enabled = true
	assert_null(_propose(reader, "adrift", "cut_line"))
	var known_row: Dictionary = _rule_row(reader, "known")
	assert_eq(str(known_row.get("id", "")), "harbor.boat_adrift")
	assert_eq(reader.quests.template_counter("cut_line"), 0)
	var outside := _boot()
	var bounded: WyrdRuntime = outside["runtime"]
	var bounds_world: WyrdFakeWorld = outside["host"].world
	bounds_world.set_out_of_bounds(&"net.mended", true)
	bounded.trace.enabled = true
	assert_null(_propose(bounded, "out", "net_delivery"))
	assert_true(_has_rule(bounded, "bounds"))
	assert_eq(bounds_world.bounds_pack, "harbor")
	assert_eq(bounded.quests.template_counter("net_delivery"), 0)
	var assumed := _boot()
	var thief: WyrdRuntime = assumed["runtime"]
	var fishers: WyrdFakeWorld = assumed["host"].world
	fishers.remove_entity(&"pier_fisher")
	(assumed["host"] as WyrdFakeHost).inventory.set_owner(&"catch.day", &"line_fisher")
	thief.trace.enabled = true
	assert_null(_propose(thief, "owned", "stolen_catch"))
	var assume_row: Dictionary = _rule_row(thief, "assumes")
	assert_eq(str(assume_row.get("id", "")), "assumes.2")
	assert_eq(thief.quests.template_counter("stolen_catch"), 0)


func test_two_seed_one_runs_match_and_a_second_witness_changes_cut_line() -> void:
	var first := _seven(false)
	var second := _seven(false)
	assert_eq(JSON.stringify(first.trace.snapshot()), JSON.stringify(second.trace.snapshot()))
	var changed := _seven(true)
	var found := WyrdTrace.diff(first.trace.snapshot(), changed.trace.snapshot())
	assert_false(found.is_empty(), "\n".join(found))
	assert_true(found[0].contains("gen_candidates"), found[0])
	var index := int(found[0].get_slice(" ", 0))
	var row: Dictionary = first.trace.snapshot()[index]
	assert_eq(str(row.get("kind", "")), "gen_candidates")
	assert_true(str(row.get("key", "")).contains("cut_line"), str(row.get("key", "")))


func test_save_mid_generation_reloads_and_the_next_proposal_matches() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var net := _propose(runtime, "nets", "net_delivery")
	assert_eq(runtime.generator.accept(net), "net_delivery#1")
	var walk := _propose(runtime, "walk", "night_walk")
	assert_eq(runtime.generator.accept(walk), "night_walk#1")
	assert_eq(runtime.quests.stage("net_delivery#1"), "carry")
	assert_true(runtime.quests.waiting_reason("net_delivery#1").begins_with("waits_until"))
	var before: Dictionary = runtime.quests.export_generator()
	assert_false((before["instances"]["net_delivery#1"] as Dictionary).has("created"))
	assert_true((before["instances"]["night_walk#1"] as Dictionary).has("created"))
	assert_eq(int((before["instances"]["night_walk#1"] as Dictionary)["created"]), runtime.now_minutes())
	var net_journal := _texts(runtime, "net_delivery#1")
	var walk_journal := _texts(runtime, "night_walk#1")
	var parsed: Variant = JSON.parse_string(JSON.stringify(runtime.save_state(), "\t", true))
	var loaded := _boot()
	var fresh: WyrdRuntime = loaded["runtime"]
	var report := fresh.load_state(parsed)
	assert_true(report.ok, report.diagnostics.format())
	assert_false(report.diagnostics.has_warnings(), report.diagnostics.format())
	assert_eq(JSON.stringify(fresh.quests.export_generator()), JSON.stringify(before))
	assert_eq(_texts(fresh, "net_delivery#1"), net_journal)
	assert_eq(_texts(fresh, "night_walk#1"), walk_journal)
	assert_eq(fresh.quests.stage("net_delivery#1"), "carry")
	assert_eq(fresh.quests.stage("night_walk#1"), "walk")
	runtime.facts.set(&"harbor.boat_adrift", true)
	fresh.facts.set(&"harbor.boat_adrift", true)
	runtime.trace.enabled = true
	fresh.trace.enabled = true
	var live := runtime.generator.propose({"key": "next", "source": "save"})
	var again := fresh.generator.propose({"key": "next", "source": "save"})
	assert_not_null(live, _gen(runtime))
	assert_not_null(again, _gen(fresh))
	assert_eq(live.template, "cut_line")
	assert_eq(again.template, "cut_line")
	assert_eq(JSON.stringify(live.casts), JSON.stringify(again.casts))
	assert_eq(JSON.stringify(live.params), JSON.stringify(again.params))
	assert_eq(_decisions(runtime), _decisions(fresh))


func test_every_route_plays_headless() -> void:
	var delivered := _boot()
	var runtime: WyrdRuntime = delivered["runtime"]
	var harness: RefCounted = delivered["harness"]
	var net := _propose(runtime, "nets", "net_delivery")
	assert_eq(runtime.generator.accept(net), "net_delivery#1")
	assert_eq(_texts(runtime, "net_delivery#1")[0], "fisher wants a net carried to the harbor factor.")
	(delivered["host"] as WyrdFakeHost).inventory.set_owner(&"net.mended", &"net_mender")
	runtime.tick(0)
	runtime.tick(0)
	assert_eq(runtime.quests.status("net_delivery#1"), &"completed")
	assert_eq(runtime.quests.outcome("net_delivery#1", "net"), "done")
	assert_eq(runtime.facts.get(&"harbor.net_fate"), &"delivered")
	assert_false(runtime.facts.get(&"harbor.nets_wanted"))
	assert_eq(_texts(runtime, "net_delivery#1")[1], "The net reached the harbor factor.")
	var returned := _boot()
	var catcher: WyrdRuntime = returned["runtime"]
	(returned["host"].world as WyrdFakeWorld).remove_entity(&"pier_fisher")
	var stolen := _propose(catcher, "catch", "stolen_catch")
	assert_eq(str(stolen.casts.get("victim", "")), "line_fisher")
	assert_eq(catcher.generator.accept(stolen), "stolen_catch#1")
	assert_eq(_texts(catcher, "stolen_catch#1")[0], "Someone took fisher's catch from the drying racks.")
	(returned["host"] as WyrdFakeHost).inventory.set_owner(&"catch.day", &"line_fisher")
	catcher.tick(0)
	catcher.tick(0)
	assert_eq(catcher.quests.status("stolen_catch#1"), &"completed")
	assert_eq(catcher.quests.outcome("stolen_catch#1", "catch"), "done")
	assert_eq(catcher.facts.get(&"harbor.catch_fate"), &"returned")
	assert_eq(_texts(catcher, "stolen_catch#1")[1], "The catch is back with fisher.")
	var looked := _boot()
	var cutter: WyrdRuntime = looked["runtime"]
	var cut_harness: RefCounted = looked["harness"]
	var cut := _propose(cutter, "line", "cut_line")
	assert_eq(cutter.generator.accept(cut), "cut_line#1")
	assert_eq(_texts(cutter, "cut_line#1")[0], "Nia saw a mooring line cut at the north bollard.")
	_choose(cutter, cut_harness, "cut.ask", "Thank them and look at the line")
	cutter.tick(0)
	assert_eq(cutter.quests.status("cut_line#1"), &"completed")
	assert_eq(cutter.quests.outcome("cut_line#1", "line"), "done")
	assert_eq(cutter.facts.get(&"harbor.line_fate"), &"found")
	assert_eq(_texts(cutter, "cut_line#1")[1], "The cut line has been looked at.")
	var left := _boot()
	var waiting: WyrdRuntime = left["runtime"]
	var left_harness: RefCounted = left["harness"]
	assert_eq(waiting.generator.accept(_propose(waiting, "line", "cut_line")), "cut_line#1")
	_choose(waiting, left_harness, "cut.ask", "Leave it for now")
	assert_eq(waiting.quests.status("cut_line#1"), &"active")
	assert_eq(waiting.quests.stage("cut_line#1"), "ask")
	var gone := _boot()
	var missing: WyrdRuntime = gone["runtime"]
	var gone_harness: RefCounted = gone["harness"]
	assert_eq(missing.generator.accept(_propose(missing, "line", "cut_line")), "cut_line#1")
	# The ask scene stays offered until it ends, so a tick cannot adopt the variant yet.
	_choose(missing, gone_harness, "cut.ask", "Leave it for now")
	(gone["host"].world as WyrdFakeWorld).remove_entity(&"dock.bollard_north")
	missing.tick(0)
	assert_eq(missing.quests.variant_of("cut_line#1"), "post.locked_gone")
	assert_true(_joined(missing, "cut_line#1").contains("The bollard is gone before anyone could look."))
	var empty := _boot()
	var none: WyrdRuntime = empty["runtime"]
	(empty["host"].world as WyrdFakeWorld).remove_entity(&"dock.bollard_north")
	none.trace.enabled = true
	assert_null(_propose(none, "line", "cut_line"))
	assert_eq(str(none.generator.why_not("cut_line").get("reason", "")), "no_candidate")
	assert_eq(none.quests.template_counter("cut_line"), 0)
	var walked := _boot()
	var guide: WyrdRuntime = walked["runtime"]
	var walk_harness: RefCounted = walked["harness"]
	assert_eq(guide.generator.accept(_propose(guide, "walk", "night_walk")), "night_walk#1")
	assert_eq(_texts(guide, "night_walk#1")[0], "visitor asks to be walked to the north steps.")
	_choose(guide, walk_harness, "night.walk", "Walk them there")
	assert_eq(guide.quests.status("night_walk#1"), &"completed")
	assert_eq(guide.quests.outcome("night_walk#1", "walk"), "done")
	assert_eq(_texts(guide, "night_walk#1")[1], "visitor reached the north steps.")
	var expired := _boot()
	var night: WyrdRuntime = expired["runtime"]
	var night_harness: RefCounted = expired["harness"]
	night.trace.enabled = true
	assert_eq(night.generator.accept(_propose(night, "walk", "night_walk")), "night_walk#1")
	var kept := _texts(night, "night_walk#1")
	_choose(night, night_harness, "night.walk", "Not tonight")
	night.tick(360)
	assert_eq(night.quests.status("night_walk#1"), &"abandoned")
	assert_eq(str(_rows(night, "gen_expire")[0].get("instance", "")), "night_walk#1")
	assert_eq(str(_rows(night, "gen_expire")[0].get("reason", "")), "timeout")
	assert_eq(_texts(night, "night_walk#1"), kept)
	assert_not_null(harness)


func test_stew_favor_climbs_three_tiers() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var harbor := _Harbor.new()
	runtime.config().scheduler_share_generate = 64
	runtime.trace.enabled = true
	var fish := 1
	for round_name in ["low", "mid", "high"]:
		runtime.facts.set(&"harbor.stew_wanted", true)
		var tier := String(harbor.stew_tier(runtime))
		assert_eq(tier, round_name)
		assert_true(harbor.offer(runtime, &"tavern", "stew-%s" % round_name, StringName(tier)))
		harbor.run(runtime, 0)
		var instance := "tavern_stew_%s#1" % round_name
		assert_eq(runtime.quests.status(instance), &"active", instance)
		(opened["host"] as WyrdFakeHost).inventory.set_count(&"player", &"fish", fish)
		runtime.config().scheduler_share_generate = 0
		harbor.run(runtime, 0)
		harbor.run(runtime, 0)
		runtime.config().scheduler_share_generate = 64
		assert_eq(runtime.quests.status(instance), &"completed", _gen(runtime))
		fish += 1
	assert_eq(_stew_tiers(runtime), PackedStringArray(["low", "mid", "high"]))
	assert_eq(runtime.facts.get(&"harbor.stew_tier"), &"high")
	assert_eq(runtime.facts.get(&"harbor.stew_favors"), 3)
	assert_eq(_texts(runtime, "tavern_stew_high#1")[1], "The whole room eats from the pot. That makes 3 pots of stew.")


func test_cap_and_retry_keys() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var net := _propose(runtime, "nets", "net_delivery")
	assert_eq(runtime.generator.accept(net), "net_delivery#1")
	runtime.trace.enabled = true
	runtime.trace.clear()
	assert_null(_propose(runtime, "again", "net_delivery"))
	var cap: Dictionary = _rows(runtime, "gen_cap")[0]
	assert_eq(str(cap.get("template", "")), "net_delivery")
	assert_eq(int(cap.get("active", -1)), 1)
	assert_lt(_index(runtime, "gen_cap"), _index(runtime, "gen_tier"))
	var guarded := _boot()
	var host: WyrdRuntime = guarded["runtime"]
	(guarded["host"].world as WyrdFakeWorld).remove_entity(&"pier_fisher")
	(guarded["host"].world as WyrdFakeWorld).set_protected(&"line_fisher", true)
	host.trace.enabled = true
	assert_null(_propose(host, "guard", "net_delivery"))
	assert_eq(host.quests.template_counter("net_delivery"), 0)
	assert_true(_has_key_suffix(host, ":1"))


func test_generate_dry_run_matches_the_fixture() -> void:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set(&"harbor.nets_wanted", true)
	var file := FileAccess.open(_SAVE, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(JSON.stringify(runtime.save_state(), "\t", true))
	file.close()
	var result: Dictionary = WyrdCli.execute(PackedStringArray([
		"generate", "--dry-run", "--manifest", _MANIFEST,
		"--save", _SAVE, "--world", _WORLD,
		"--source", "exit", "--key", "one", "--seed", "1",
	]))
	assert_eq(int(result["exit_code"]), 0, str(result["output"]))
	var text := str(result["output"])
	assert_true(text.contains("instance=net_delivery#1"))
	assert_true(text.contains("sender=line_fisher"))
	assert_true(text.contains("net=net.mended"))
	assert_eq(text, FileAccess.get_file_as_string(_DRY))


func test_net_and_night_routes_replay() -> void:
	var delivered := _record_net()
	var again := _boot()
	var fresh: WyrdRuntime = again["runtime"]
	fresh.facts.set(&"harbor.nets_wanted", true)
	fresh.trace.enabled = true
	_replay_net(fresh, again["host"], delivered)
	assert_eq(WyrdTrace.diff(delivered, fresh.trace.snapshot()), PackedStringArray())
	var walked := _record_night("Walk them there")
	var walked_again := _boot()
	var guide: WyrdRuntime = walked_again["runtime"]
	guide.facts.set(&"harbor.visitor_waiting", true)
	guide.trace.enabled = true
	WyrdTrace.replay(guide, walked)
	assert_eq(WyrdTrace.diff(walked, guide.trace.snapshot()), PackedStringArray())
	var expired := _record_night("Not tonight")
	var night := _boot()
	var host: WyrdRuntime = night["runtime"]
	host.facts.set(&"harbor.visitor_waiting", true)
	host.trace.enabled = true
	WyrdTrace.replay(host, expired)
	assert_eq(WyrdTrace.diff(expired, host.trace.snapshot()), PackedStringArray())


func _record_net() -> Array:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set(&"harbor.nets_wanted", true)
	runtime.trace.enabled = true
	var proposal := runtime.generator.propose({"key": "nets", "source": "route"})
	assert_eq(runtime.generator.accept(proposal), "net_delivery#1")
	(opened["host"] as WyrdFakeHost).inventory.set_owner(&"net.mended", &"net_mender")
	runtime.tick(0)
	runtime.tick(0)
	assert_eq(runtime.quests.status("net_delivery#1"), &"completed")
	return runtime.trace.snapshot()


func _record_night(label: String) -> Array:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	var harness: RefCounted = opened["harness"]
	runtime.facts.set(&"harbor.visitor_waiting", true)
	runtime.trace.enabled = true
	var proposal := runtime.generator.propose({"key": "walk", "source": "route"})
	assert_eq(runtime.generator.accept(proposal), "night_walk#1")
	_choose(runtime, harness, "night.walk", label)
	if label == "Not tonight":
		runtime.tick(360)
		assert_eq(runtime.quests.status("night_walk#1"), &"abandoned")
	else:
		assert_eq(runtime.quests.status("night_walk#1"), &"completed")
	return runtime.trace.snapshot()


func _replay_net(runtime: WyrdRuntime, host: Variant, recorded: Array) -> void:
	var at := recorded.size()
	for i in recorded.size():
		if str((recorded[i] as Dictionary).get("kind", "")) == "tick":
			at = i
			break
	WyrdTrace.replay(runtime, recorded.slice(0, at))
	(host as WyrdFakeHost).inventory.set_owner(&"net.mended", &"net_mender")
	WyrdTrace.replay(runtime, recorded.slice(at))


func _decisions(runtime: WyrdRuntime) -> String:
	var rule := RegEx.new()
	rule.compile("proposal=p\\d+")
	return rule.sub(_gen(runtime), "proposal=p", true)


func _seven(extra_witness: bool) -> WyrdRuntime:
	var opened := _boot()
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	_propose(runtime, "nets", "net_delivery")
	_propose(runtime, "catch", "stolen_catch")
	if extra_witness:
		(opened["host"].world as WyrdFakeWorld).add_entity(&"south_hand", &"person", "south hand", PackedStringArray(["dock"]), true)
	_propose(runtime, "line", "cut_line")
	_propose(runtime, "walk", "night_walk")
	runtime.facts.set(&"harbor.stew_wanted", true)
	_propose(runtime, "stew-low", "tavern_stew_low", "low")
	_propose(runtime, "stew-mid", "tavern_stew_mid", "mid")
	runtime.facts.set(&"harbor.stew_tier", &"high")
	_propose(runtime, "stew-high", "tavern_stew_high", "high")
	return runtime


func _boot() -> Dictionary:
	var opened: Dictionary = _Harbor.new().boot_generated(1)
	var report: WyrdLoadReport = opened["report"]
	assert_true(report.ok, report.diagnostics.format())
	return opened


func _propose(runtime: WyrdRuntime, key: String, template_id: String, tier: String = "") -> WyrdProposal:
	_arm(runtime, template_id)
	return runtime.generator.propose({
		"key": key,
		"source": "exit",
		"template": template_id,
		"tier": tier,
	})


func _arm(runtime: WyrdRuntime, template_id: String) -> void:
	match template_id:
		"net_delivery":
			runtime.facts.set(&"harbor.nets_wanted", true)
		"stolen_catch":
			runtime.facts.set(&"harbor.catch_missing", true)
		"cut_line":
			runtime.facts.set(&"harbor.boat_adrift", true)
		"night_walk":
			runtime.facts.set(&"harbor.visitor_waiting", true)
		"tavern_stew_low", "tavern_stew_mid", "tavern_stew_high":
			runtime.facts.set(&"harbor.stew_wanted", true)


func _choose(runtime: WyrdRuntime, harness: RefCounted, scene_id: String, label: String) -> void:
	assert_eq(runtime.quests.offered_scene(_scene_quest(runtime, scene_id)), scene_id)
	runtime.dialogue.open_scene(scene_id)
	harness.line_rows(runtime)
	harness.choose_text(runtime, label)
	harness.line_rows(runtime)
	runtime.tick(0)


func _scene_quest(runtime: WyrdRuntime, scene_id: String) -> String:
	if scene_id == "cut.ask":
		return "cut_line#1"
	return "night_walk#1"


func _param(proposal: WyrdProposal, param_name: String) -> String:
	var snap: Variant = proposal.params.get(param_name, {})
	if snap is Dictionary:
		return str((snap as Dictionary).get("entity", ""))
	return ""


func _texts(runtime: WyrdRuntime, quest_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for row in runtime.quests.journal(quest_id):
		out.append(str((row as Dictionary).get("text", "")))
	return out


func _joined(runtime: WyrdRuntime, quest_id: String) -> String:
	return "\n".join(_texts(runtime, quest_id))


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var out: Array = []
	for row in runtime.trace.events:
		if str(row.get("kind", "")) == kind:
			out.append(row)
	return out


func _index(runtime: WyrdRuntime, kind: String) -> int:
	for i in runtime.trace.events.size():
		if str(runtime.trace.events[i].get("kind", "")) == kind:
			return i
	return -1


func _gen(runtime: WyrdRuntime) -> String:
	var lines := PackedStringArray()
	for row in runtime.trace.events:
		var text := WyrdCli._format_gen(row)
		if not text.is_empty():
			lines.append(text)
	return "\n".join(lines)


func _has_rule(runtime: WyrdRuntime, rule: String) -> bool:
	return not _rule_row(runtime, rule).is_empty()


func _rule_row(runtime: WyrdRuntime, rule: String) -> Dictionary:
	for row in _rows(runtime, "gen_reject"):
		if str(row.get("rule", "")) == rule:
			return row
	return {}


func _has_key_suffix(runtime: WyrdRuntime, suffix: String) -> bool:
	for row in runtime.trace.events:
		var key := str(row.get("key", ""))
		if key.is_empty():
			key = str(row.get("seed_key", ""))
		if key.ends_with(suffix):
			return true
	return false


func _assumes_rejects(runtime: WyrdRuntime) -> int:
	var count := 0
	for row in _rows(runtime, "gen_reject"):
		if str(row.get("rule", "")) == "assumes" and str(row.get("template", "")) == "net_delivery":
			count += 1
	return count


func _assert_reject_is_assumes(runtime: WyrdRuntime) -> void:
	for row in _rows(runtime, "gen_reject"):
		if str(row.get("template", "")) != "net_delivery":
			continue
		assert_eq(str(row.get("rule", "")), "assumes")


func _stew_tiers(runtime: WyrdRuntime) -> PackedStringArray:
	var out := PackedStringArray()
	for row in _rows(runtime, "gen_tier"):
		if str(row.get("key", "")).begins_with("stew-"):
			out.append(str(row.get("tier", "")))
	return out
