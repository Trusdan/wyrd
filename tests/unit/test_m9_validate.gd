extends GutTest

const MANIFEST := "res://tests/support/m9_validate.wyrdmanifest.tres"
const GENERATE_MANIFEST := "res://tests/support/m9_generate.wyrdmanifest.tres"


func test_exists_excludes_the_id_and_casts_the_next() -> void:
	var found := false
	for seed in range(1, 40):
		var opened := _deny(seed, &"ghost")
		var runtime: WyrdRuntime = opened["runtime"]
		_person(opened["world"], &"ada", "person")
		_person(opened["world"], &"ghost", "person")
		runtime.trace.enabled = true
		var proposal := runtime.generator.propose({"key": "exists", "source": "host", "template": "exists_one"})
		var rejects := _rows(runtime, "gen_reject")
		if rejects.is_empty():
			continue
		found = true
		assert_eq(str(rejects[0].get("rule", "")), "exists")
		assert_eq(str(rejects[0].get("id", "")), "ghost")
		assert_not_null(proposal)
		assert_eq(str(proposal.casts["who"]), "ada")
		var picks := _rows(runtime, "gen_pick")
		assert_eq(str(picks[1].get("seed_key", "")), "pick:host:exists:1")
		var raw := _rows(runtime, "gen_candidates")
		assert_eq(int(raw[0].get("count", 0)), 2)
		assert_eq(int(raw[raw.size() - 1].get("count", 0)), 2)
		assert_false(str(raw[0].get("key", "")).ends_with(":1"))
		assert_true(str(raw[raw.size() - 1].get("key", "")).ends_with(":1"))
		break
	assert_true(found)


func test_unplaced_object_and_untracked_item_pass_without_a_retry() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	var world: WyrdFakeWorld = opened["world"]
	_person(world, &"ada", "person")
	world.add_entity(&"parcel.a", &"item", "Parcel", PackedStringArray(["parcel"]), true)
	runtime.trace.enabled = true
	var proposal := runtime.generator.propose({"key": "place", "source": "host", "template": "unplaced"})
	assert_not_null(proposal)
	assert_eq(str(proposal.casts["who"]), "ada")
	assert_eq(String((opened["host"] as WyrdFakeHost).spatial.place_of(&"ada")), "")
	assert_eq(_rows(runtime, "gen_reject").size(), 0)
	assert_false(_joined_keys(runtime).contains(":1"))
	runtime.trace.clear()
	var carried := runtime.generator.propose({"key": "item", "source": "host", "template": "carried"})
	assert_not_null(carried)
	assert_eq(str((carried.params["item"] as Dictionary)["entity"]), "parcel.a")
	assert_eq(_rows(runtime, "gen_reject").size(), 0)
	var owned := _open(4)
	var second: WyrdRuntime = owned["runtime"]
	(owned["world"] as WyrdFakeWorld).add_entity(&"parcel.a", &"item", "Parcel", PackedStringArray(["parcel"]), true)
	(owned["world"] as WyrdFakeWorld).add_entity(&"ada", &"object", "Ada", PackedStringArray(["person"]), true)
	(owned["host"] as WyrdFakeHost).inventory.set_owner(&"parcel.a", &"ada")
	(owned["host"] as WyrdFakeHost).spatial.set_place(&"ada", &"slip")
	second.trace.enabled = true
	assert_not_null(second.generator.propose({"key": "carried", "source": "host", "template": "carried"}))
	assert_eq(_rows(second, "gen_reject").size(), 0)


func test_place_is_not_rejected_without_a_spatial_adapter() -> void:
	var runtime := WyrdRuntime.new()
	var world := WyrdFakeWorld.new()
	var inventory := WyrdFakeInventory.new()
	runtime.register_adapter(WyrdWorldAdapter, world)
	runtime.register_adapter(WyrdInventoryAdapter, inventory)
	var report := runtime.load_content(load(MANIFEST))
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(4)
	world.add_entity(&"parcel.a", &"item", "Parcel", PackedStringArray(["parcel"]), true)
	runtime.trace.enabled = true
	assert_not_null(runtime.generator.propose({"key": "nospatial", "source": "host", "template": "carried"}))
	assert_eq(_rows(runtime, "gen_reject").size(), 0)


func test_protected_rejects_unless_the_template_allows_it() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	var world: WyrdFakeWorld = opened["world"]
	_person(world, &"warden", "guarded")
	world.set_protected(&"warden", true)
	runtime.trace.enabled = true
	assert_null(runtime.generator.propose({"key": "prot", "source": "host", "template": "protected_one"}))
	assert_eq(str(_rows(runtime, "gen_reject")[0].get("rule", "")), "protected")
	assert_eq(str(_rows(runtime, "gen_reject")[0].get("id", "")), "warden")
	var allowed := runtime.generator.propose({"key": "ok", "source": "host", "template": "protected_ok"})
	assert_not_null(allowed)
	assert_eq(str(allowed.casts["guard"]), "warden")


func test_bounds_rejects_and_passes_the_pack_id() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	var world: WyrdFakeWorld = opened["world"]
	_person(world, &"ada", "bounded")
	world.set_out_of_bounds(&"ada", true)
	runtime.config().generator_retries = 0
	runtime.trace.enabled = true
	assert_null(runtime.generator.propose({"key": "bounds", "source": "host", "template": "bounds_one"}))
	assert_eq(str(_rows(runtime, "gen_reject")[0].get("rule", "")), "bounds")
	assert_eq(world.bounds_pack, "m9_validate")
	assert_eq(world.bounds_id, "ada")


func test_assumes_reads_the_provisional_param() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	var world: WyrdFakeWorld = opened["world"]
	world.add_entity(&"parcel.dead", &"item", "Dead", PackedStringArray(["parcel"]), false)
	runtime.trace.enabled = true
	assert_null(runtime.generator.propose({"key": "dead", "source": "host", "template": "assumes_one"}))
	assert_eq(str(_rows(runtime, "gen_reject")[0].get("rule", "")), "assumes")
	assert_eq(str(_rows(runtime, "gen_reject")[0].get("id", "")), "assumes.1")
	var other := runtime.quests.create_instance("assumes_one", {}, {"parcel": {"entity": "parcel.dead", "kind": "item"}})
	world.remove_entity(&"parcel.dead")
	world.add_entity(&"parcel.dead", &"item", "Dead", PackedStringArray(["old"]), false)
	world.add_entity(&"parcel.live", &"item", "Live", PackedStringArray(["parcel"]), true)
	assert_eq(other, "assumes_one#1")
	runtime.trace.clear()
	var proposal := runtime.generator.propose({"key": "live", "source": "host", "template": "assumes_one"})
	assert_not_null(proposal)
	assert_eq(str((proposal.params["parcel"] as Dictionary)["entity"]), "parcel.live")
	assert_eq(_rows(runtime, "gen_reject").size(), 0)
	var parts: WyrdTemplateDef = runtime.content().templates["parts"]
	assert_eq(parts.assumption_conds.size(), 2)
	assert_eq(PackedStringArray(parts.assumption_texts), PackedStringArray(["alive(parcel)", "gate.flag"]))


func test_owner_of_reads_inventory_and_is_empty_without_it() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	var world: WyrdFakeWorld = opened["world"]
	_person(world, &"ada", "victim")
	world.add_entity(&"parcel.a", &"item", "Parcel", PackedStringArray(["parcel"]), true)
	(opened["host"] as WyrdFakeHost).inventory.set_owner(&"parcel.a", &"ada")
	runtime.trace.enabled = true
	var proposal := runtime.generator.propose({"key": "own", "source": "host", "template": "owner_one"})
	assert_not_null(proposal)
	assert_eq(_rows(runtime, "gen_reject").size(), 0)
	(opened["host"] as WyrdFakeHost).inventory.set_owner(&"parcel.a", &"bram")
	runtime.trace.clear()
	assert_null(runtime.generator.propose({"key": "other", "source": "host", "template": "owner_one"}))
	assert_eq(str(_rows(runtime, "gen_reject")[0].get("rule", "")), "assumes")
	assert_ne(str(_rows(runtime, "gen_reject")[0].get("rule", "")), "known")
	var bare := WyrdRuntime.new()
	bare.register_adapter(WyrdWorldAdapter, world)
	var report := bare.load_content(load(MANIFEST))
	assert_true(report.ok, report.diagnostics.format())
	bare.start_new_game(4)
	bare.trace.enabled = true
	assert_null(bare.generator.propose({"key": "none", "source": "host", "template": "owner_one"}))
	assert_eq(str(_rows(bare, "gen_reject")[0].get("rule", "")), "assumes")


func test_known_rejects_only_a_different_player_value() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set(&"gate.flag", true)
	runtime.facts.set_in(&"gate.flag", false, &"known/player")
	runtime.trace.enabled = true
	assert_null(runtime.generator.propose({"key": "known", "source": "host", "template": "known_one"}))
	assert_eq(str(_rows(runtime, "gen_reject")[0].get("rule", "")), "known")
	assert_eq(str(_rows(runtime, "gen_reject")[0].get("id", "")), "gate.flag")
	runtime.facts.set_in(&"gate.flag", true, &"known/player")
	runtime.trace.clear()
	assert_not_null(runtime.generator.propose({"key": "same", "source": "host", "template": "known_one"}))
	assert_eq(_rows(runtime, "gen_reject").size(), 0)
	var fresh := _open(4)
	var second: WyrdRuntime = fresh["runtime"]
	second.facts.set(&"gate.flag", true)
	second.trace.enabled = true
	assert_not_null(second.generator.propose({"key": "blank", "source": "host", "template": "known_one"}))
	assert_eq(_rows(second, "gen_reject").size(), 0)


func test_retries_vary_keys_and_then_stop() -> void:
	var limited := _deny(4, &"ghost")
	var runtime: WyrdRuntime = limited["runtime"]
	_person(limited["world"], &"ghost", "person")
	runtime.config().generator_retries = 0
	runtime.trace.enabled = true
	assert_null(runtime.generator.propose({"key": "once", "source": "host", "template": "exists_one"}))
	assert_eq(_rows(runtime, "gen_reject").size(), 1)
	assert_eq(str(_propose_row(runtime).get("reason", "")), "rejected")
	assert_false(_joined_keys(runtime).contains(":1"))
	assert_eq(runtime.quests.template_counter("exists_one"), 0)
	assert_eq(runtime.generator.pending_creations().size(), 0)
	# exists excludes the only id, so the next attempt is no_candidate and stops.
	# A known conflict excludes nothing, so the decision uses every retry.
	var full := _open(4)
	var again: WyrdRuntime = full["runtime"]
	again.facts.set(&"gate.flag", true)
	again.facts.set_in(&"gate.flag", false, &"known/player")
	again.trace.enabled = true
	assert_null(again.generator.propose({"key": "all", "source": "host", "template": "known_one"}))
	assert_eq(_rows(again, "gen_reject").size(), 9)
	assert_eq(str(_propose_row(again).get("reason", "")), "rejected")
	assert_true(_joined_keys(again).contains("pick:host:all:1"))
	assert_true(_joined_keys(again).contains("pick:host:all:8"))
	assert_eq(again.quests.template_counter("known_one"), 0)
	var negative := _deny(4, &"ghost")
	var third: WyrdRuntime = negative["runtime"]
	_person(negative["world"], &"ghost", "person")
	third.config().generator_retries = -3
	third.trace.enabled = true
	assert_null(third.generator.propose({"key": "neg", "source": "host", "template": "exists_one"}))
	assert_eq(_rows(third, "gen_reject").size(), 1)
	var seed := _exists_seed()
	var left_run := _deny_ready(seed)
	var right_run := _deny_ready(seed)
	assert_eq(_trace_text(left_run), _trace_text(right_run))
	var left := _gen_lines(left_run)
	assert_true(left.contains("rule=exists"))
	assert_true(left.contains(":1"))


func test_pr6_unplaced_object_cast_keeps_attempt_zero_keys() -> void:
	var opened := _generate(4)
	var runtime: WyrdRuntime = opened["runtime"]
	_people(opened["host"])
	runtime.facts.set(&"guild.errand", true)
	runtime.trace.enabled = true
	var proposal := runtime.generator.propose({"key": "cast", "source": "host"})
	assert_not_null(proposal)
	assert_eq(proposal.template, "errand")
	assert_eq(proposal.instance, "errand#1")
	var courier := str(proposal.casts["courier"])
	assert_true(courier == "ada" or courier == "bram")
	assert_eq(String((opened["host"] as WyrdFakeHost).spatial.place_of(StringName(courier))), "")
	assert_eq(_rows(runtime, "gen_reject").size(), 0)
	assert_eq(_rows(runtime, "gen_cap").size(), 0)
	var keys := _joined_keys(runtime)
	assert_eq(keys, "pick:host:cast\ncast:errand#1.courier\ncast:errand#1.partner\nparam:errand#1.parcel\nparam:errand#1.site")
	assert_eq(_gen_lines(runtime), "\n".join(PackedStringArray([
		"wyrd gen_tier source=host key=cast tier= eligible=1",
		"wyrd gen_pick source=host key=cast template=errand score=2/1 band=1 seed_key=pick:host:cast",
		"wyrd gen_candidates key=cast:errand#1.courier count=2 digest=c12b8f089b2cc5d3",
		"wyrd gen_cast instance=errand#1 slot=courier kind=object entity=bram",
		"wyrd gen_candidates key=cast:errand#1.partner count=4 digest=4c8dbdc8a165c775",
		"wyrd gen_cast instance=errand#1 slot=partner kind=object entity=bram",
		"wyrd gen_candidates key=param:errand#1.parcel count=2 digest=720255433eb27633",
		"wyrd gen_bind instance=errand#1 param=parcel kind=item entity=parcel.b",
		"wyrd gen_candidates key=param:errand#1.site count=2 digest=ac82b90e24d5b3ef",
		"wyrd gen_bind instance=errand#1 param=site kind=object entity=dock.b",
		"wyrd gen_propose source=host key=cast ok=true reason=proposed proposal=p1",
	])))


func test_cap_logs_before_gen_tier_and_counts_a_reservation() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.quests.create_instance("capped")
	runtime.trace.enabled = true
	assert_null(runtime.generator.propose({"key": "cap", "source": "host", "template": "capped"}))
	var cap: Dictionary = _rows(runtime, "gen_cap")[0]
	assert_eq(int(cap.get("active", -1)), 1)
	assert_eq(int(cap.get("reserved", -1)), 0)
	assert_eq(int(cap.get("max", -1)), 1)
	assert_lt(_index(runtime, "gen_cap"), _index(runtime, "gen_tier"))
	assert_eq(str(runtime.generator.why_not("capped").get("reason", "")), "filtered")
	assert_eq(str(runtime.generator.why_not("capped").get("filter", "")), "cap")
	var reserved := _open(4)
	var second: WyrdRuntime = reserved["runtime"]
	second.trace.enabled = true
	second.generator.fulfill({"key": "one", "origin": "host", "payload": {}, "source": "host", "template": "capped", "tier": ""})
	second.trace.clear()
	second.generator.fulfill({"key": "two", "origin": "host", "payload": {}, "source": "host", "template": "capped", "tier": ""})
	var held: Dictionary = _rows(second, "gen_cap")[0]
	assert_eq(int(held.get("active", -1)), 0)
	assert_eq(int(held.get("reserved", -1)), 1)
	assert_eq(int(held.get("max", -1)), 1)
	var open_plain := _open(4)
	var third: WyrdRuntime = open_plain["runtime"]
	_person(open_plain["world"], &"ada", "person")
	third.trace.enabled = true
	assert_not_null(third.generator.propose({"key": "free", "source": "host", "template": "unplaced"}))
	assert_eq(_rows(third, "gen_cap").size(), 0)


func test_expiry_abandons_on_time_and_keeps_created() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.facts.set(&"gate.expire", true)
	var id := runtime.quests.create_instance("lasting")
	assert_eq(runtime.quests.template_counter("lasting"), 1)
	runtime.tick(119)
	assert_eq(runtime.now_minutes(), 119)
	assert_eq(runtime.quests.status(id), &"active")
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.tick(1)
	assert_eq(runtime.now_minutes(), 120)
	assert_eq(runtime.quests.status(id), &"abandoned")
	assert_eq(str(_rows(runtime, "gen_expire")[0].get("reason", "")), "timeout")
	assert_eq(str(_rows(runtime, "gen_expire")[0].get("instance", "")), id)
	assert_eq(runtime.quests.template_counter("lasting"), 1)
	assert_eq(_journal(runtime, id), "Keep this note.")
	var deferred := _open(4)
	var waiting: WyrdRuntime = deferred["runtime"]
	var held := waiting.quests.create_instance("lasting")
	waiting.tick(119)
	waiting.dialogue.open_scene("expire.bet")
	assert_eq(waiting.dialogue.open_quest_id(), held)
	waiting.trace.enabled = true
	waiting.tick(1)
	assert_eq(waiting.quests.status(held), &"active")
	assert_eq(_rows(waiting, "gen_expire").size(), 0)
	assert_true(waiting.dialogue.is_open())
	var side := _open(4)
	var other: WyrdRuntime = side["runtime"]
	var left := other.quests.create_instance("lasting")
	var right := other.quests.create_instance("beside")
	other.dialogue.open_scene("other.bet")
	assert_eq(other.dialogue.open_quest_id(), right)
	other.trace.enabled = true
	other.tick(120)
	assert_eq(other.quests.status(left), &"abandoned")
	assert_true(other.dialogue.is_open())
	assert_eq(other.dialogue.open_quest_id(), right)
	var saved := _open(4)
	var source: WyrdRuntime = saved["runtime"]
	var made := source.quests.create_instance("lasting")
	assert_eq(int(source.quests.export_generator()["instances"][made]["created"]), 0)
	var parsed: Variant = JSON.parse_string(JSON.stringify(source.save_state(), "\t", true))
	var loaded := _open(9)
	var fresh: WyrdRuntime = loaded["runtime"]
	assert_true(fresh.load_state(parsed).ok)
	assert_eq(int(fresh.quests.export_generator()["instances"][made]["created"]), 0)
	var plain := _open(4)
	var quiet: WyrdRuntime = plain["runtime"]
	quiet.quests.create_instance("plain")
	assert_false(JSON.stringify(quiet.quests.export_generator()).contains("\"created\""))


func test_why_not_records_the_last_decision_and_clears() -> void:
	var opened := _open(4)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.config().pressure_tiers = PackedStringArray(["low", "mid"])
	runtime.trace.enabled = true
	assert_null(runtime.generator.propose({"key": "tier", "source": "host", "template": "tiered", "tier": "low"}))
	var filtered: Dictionary = runtime.generator.why_not("tiered")
	assert_eq(str(filtered.get("reason", "")), "filtered")
	assert_eq(str(filtered.get("filter", "")), "tier")
	runtime.facts.set(&"gate.rank", true)
	runtime.generator.propose({"key": "rank", "source": "host"})
	assert_eq(str(runtime.generator.why_not("rank_low").get("reason", "")), "not_picked")
	assert_eq(str(runtime.generator.why_not("rank_high").get("reason", "")), "proposed")
	assert_null(runtime.generator.propose({"key": "gap", "source": "host", "template": "gap_one"}))
	var missing: Dictionary = runtime.generator.why_not("gap_one")
	assert_eq(str(missing.get("reason", "")), "no_candidate")
	assert_eq(str(missing.get("name", "")), "ghost")
	var denied := _deny(4, &"ghost")
	var host: WyrdRuntime = denied["runtime"]
	_person(denied["world"], &"ghost", "person")
	host.config().generator_retries = 0
	assert_null(host.generator.propose({"key": "no", "source": "host", "template": "exists_one"}))
	var rejected: Dictionary = host.generator.why_not("exists_one")
	assert_eq(str(rejected.get("reason", "")), "rejected")
	var rules: Array = rejected.get("rules", [])
	assert_eq(str((rules[0] as Dictionary).get("rule", "")), "exists")
	assert_eq(str((rules[0] as Dictionary).get("id", "")), "ghost")
	assert_eq(int((rules[0] as Dictionary).get("attempt", -1)), 0)
	assert_eq(str(host.generator.why_not("nope").get("reason", "")), "missing")
	host.generator.clear()
	assert_eq(str(host.generator.why_not("exists_one").get("reason", "")), "")
	var kept := _open(4)
	var source: WyrdRuntime = kept["runtime"]
	_person(kept["world"], &"ada", "person")
	var proposal := source.generator.propose({"key": "keep", "source": "host", "template": "unplaced"})
	source.generator.accept(proposal)
	assert_eq(str(source.generator.why_not("unplaced").get("reason", "")), "created")
	var parsed: Variant = JSON.parse_string(JSON.stringify(source.save_state(), "\t", true))
	var loaded := _open(2)
	var fresh: WyrdRuntime = loaded["runtime"]
	assert_true(fresh.load_state(parsed).ok)
	assert_eq(str(fresh.generator.why_not("unplaced").get("reason", "")), "")


func test_generate_dry_run_and_template_why_not() -> void:
	_write_world("user://m9_validate_world.json", {
		"entities": {
			"ada": {"alive": true, "kind": "object", "name": "Ada", "tags": ["person"]},
		},
	})
	_write_world("user://m9_validate_dead.json", {
		"entities": {
			"parcel.a": {"alive": false, "kind": "item", "name": "Parcel", "tags": ["parcel"]},
		},
	})
	var proposed: Dictionary = WyrdCli.execute(PackedStringArray([
		"generate", "--dry-run", "--manifest", "res://tests/support/m9_validate.wyrdmanifest.tres",
		"--source", "cli", "--key", "once", "--template", "unplaced",
		"--world", "user://m9_validate_world.json", "--seed", "4",
	]))
	assert_eq(int(proposed["exit_code"]), 0)
	var proposal_text := str(proposed["output"])
	assert_true(proposal_text.contains("wyrd gen_propose source=cli key=once ok=true reason=proposed proposal=p1"))
	assert_true(proposal_text.ends_with("proposal template=unplaced instance=unplaced#1 casts=who=ada params=\n"))
	assert_false(proposal_text.contains("gen_reject"))
	var rejected: Dictionary = WyrdCli.execute(PackedStringArray([
		"generate", "--dry-run", "--manifest", "res://tests/support/m9_validate.wyrdmanifest.tres",
		"--source", "cli", "--key", "no", "--template", "assumes_one",
		"--world", "user://m9_validate_dead.json",
	]))
	assert_eq(int(rejected["exit_code"]), 0)
	var none_text := str(rejected["output"])
	assert_true(none_text.contains("none reason=rejected"))
	assert_true(none_text.contains("  rule=assumes id=assumes.1 attempt=0"))
	assert_true(none_text.contains("wyrd gen_reject template=assumes_one instance=assumes_one#1 rule=assumes id=assumes.1 attempt=0"))
	var bare: Dictionary = WyrdCli.execute(PackedStringArray([
		"generate", "--manifest", "res://tests/support/m9_validate.wyrdmanifest.tres",
		"--source", "cli", "--key", "once",
	]))
	assert_eq(int(bare["exit_code"]), 1)
	assert_eq(str(bare["output"]), "wyrd: generate needs --dry-run\n")
	var why: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--manifest", "res://tests/support/m9_validate.wyrdmanifest.tres",
		"--world", "user://m9_validate_world.json", "unplaced",
	]))
	assert_eq(int(why["exit_code"]), 0)
	assert_eq(str(why["output"]), "why_not template=unplaced reason=proposed\n")
	var why_no: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--manifest", "res://tests/support/m9_validate.wyrdmanifest.tres",
		"--world", "user://m9_validate_dead.json", "assumes_one",
	]))
	assert_eq(int(why_no["exit_code"]), 0)
	assert_true(str(why_no["output"]).begins_with("why_not template=assumes_one reason=rejected\n"))
	assert_true(str(why_no["output"]).contains("  rule=assumes id=assumes.1 attempt=0\n"))
	var unknown: Dictionary = WyrdCli.execute(PackedStringArray([
		"why-not", "--manifest", "res://tests/support/m9_validate.wyrdmanifest.tres", "missing.rumor",
	]))
	assert_eq(int(unknown["exit_code"]), 1)
	assert_eq(str(unknown["output"]), "wyrd: unknown storylet \"missing.rumor\"\n")
	assert_push_error("unknown storylet")
	assert_true(WyrdCli.command_lines().has("generate: --dry-run shows one proposal or why there is none"))


func test_rejection_and_expiry_replay_with_an_empty_diff() -> void:
	var seed := _exists_seed()
	var opened := _deny(seed, &"ghost")
	var runtime: WyrdRuntime = opened["runtime"]
	_person(opened["world"], &"ada", "person")
	_person(opened["world"], &"ghost", "person")
	runtime.trace.enabled = true
	var rejected_proposal := runtime.generator.propose({"key": "replay", "source": "host"})
	assert_not_null(rejected_proposal)
	assert_eq(rejected_proposal.template, "exists_one")
	var recorded := runtime.trace.snapshot()
	var replayed := _deny(seed, &"ghost")
	var second: WyrdRuntime = replayed["runtime"]
	_person(replayed["world"], &"ada", "person")
	_person(replayed["world"], &"ghost", "person")
	second.trace.enabled = true
	WyrdTrace.replay(second, recorded)
	assert_eq(WyrdTrace.diff(recorded, second.trace.snapshot()), PackedStringArray())
	var expired := _open(4)
	var host: WyrdRuntime = expired["runtime"]
	host.facts.set(&"gate.expire", true)
	host.trace.enabled = true
	var proposal := host.generator.propose({"key": "age", "source": "host"})
	assert_eq(proposal.template, "lasting")
	host.generator.accept(proposal)
	host.tick(120)
	var expiry := host.trace.snapshot()
	var again := _open(4)
	var third: WyrdRuntime = again["runtime"]
	third.facts.set(&"gate.expire", true)
	third.trace.enabled = true
	WyrdTrace.replay(third, expiry)
	assert_eq(WyrdTrace.diff(expiry, third.trace.snapshot()), PackedStringArray())


func test_expires_duration_parses_and_rejects_a_bad_unit() -> void:
	var file := _file("""
		language 1
		template hour "Hour"
		  expires: 2h
		  stage work
		    waits_until false
	""")
	assert_eq(file.templates[0].expires_minutes, 120)
	var bad := _diagnostics("""
		language 1
		template bad "Bad"
		  expires: 2x
		  stage work
		    waits_until false
	""")
	assert_true(bad.format().contains("E_TEMPLATE_SYNTAX"))
	var zero := _diagnostics("""
		language 1
		template zero "Zero"
		  expires: 0h
		  stage work
		    waits_until false
	""")
	assert_true(zero.format().contains("expires must be greater than 0"))


func _open(seed: int) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var report := runtime.load_content(load(MANIFEST))
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(seed)
	return {"host": host, "runtime": runtime, "world": host.world}


func _deny(seed: int, denied: StringName) -> Dictionary:
	var opened := _open(seed)
	var world: WyrdFakeWorld = opened["world"]
	world.deny_exists = denied
	return opened


func _deny_ready(seed: int) -> WyrdRuntime:
	var opened := _deny(seed, &"ghost")
	_person(opened["world"], &"ada", "person")
	_person(opened["world"], &"ghost", "person")
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	runtime.generator.propose({"key": "pair", "source": "host", "template": "exists_one"})
	return runtime


func _exists_seed() -> int:
	for seed in range(1, 40):
		var runtime := _deny_ready(seed)
		if _rows(runtime, "gen_reject").size() > 0 and runtime.generator.proposal("p1") != null:
			return seed
	return 1


func _generate(seed: int) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var report := runtime.load_content(load(GENERATE_MANIFEST))
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(seed)
	return {"host": host, "runtime": runtime}


func _person(world: WyrdFakeWorld, id: StringName, tag: String) -> void:
	world.add_entity(id, &"object", String(id), PackedStringArray([tag]), true)


func _people(host: WyrdFakeHost) -> void:
	host.world.add_entity(&"ada", &"object", "Ada", PackedStringArray(["runner", "guide_a"]), true)
	host.world.add_entity(&"bram", &"object", "Bram", PackedStringArray(["runner", "guide_b"]), true)
	host.world.add_entity(&"parcel.a", &"item", "Parcel", PackedStringArray(["parcel"]), true)
	host.world.add_entity(&"parcel.b", &"item", "Other", PackedStringArray(["parcel"]), true)
	host.world.add_entity(&"dock.a", &"object", "Bollard", PackedStringArray(["bollard"]), true)
	host.world.add_entity(&"dock.b", &"object", "Post", PackedStringArray(["bollard"]), true)
	host.inventory.set_owner(&"parcel.a", &"player")
	host.inventory.set_owner(&"parcel.b", &"bram")
	host.spatial.set_place(&"dock.a", &"slip")
	host.spatial.set_place(&"dock.b", &"pier")
	host.spatial.set_place(&"parcel.a", &"bench")


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var out: Array = []
	for row in runtime.trace.events:
		if str(row.get("kind", "")) == kind:
			out.append(row)
	return out


func _propose_row(runtime: WyrdRuntime) -> Dictionary:
	var rows := _rows(runtime, "gen_propose")
	if rows.is_empty():
		return {}
	return rows[rows.size() - 1]


func _index(runtime: WyrdRuntime, kind: String) -> int:
	for i in runtime.trace.events.size():
		if str(runtime.trace.events[i].get("kind", "")) == kind:
			return i
	return -1


func _joined_keys(runtime: WyrdRuntime) -> String:
	var lines := PackedStringArray()
	for row in runtime.trace.events:
		var kind := str(row.get("kind", ""))
		if kind == "gen_pick" or kind == "gen_candidates":
			var key := str(row.get("seed_key", ""))
			if key.is_empty():
				key = str(row.get("key", ""))
			lines.append(key)
	return "\n".join(lines)


func _gen_lines(runtime: WyrdRuntime) -> String:
	var lines := PackedStringArray()
	for row in runtime.trace.events:
		var text := WyrdCli._format_gen(row)
		if not text.is_empty():
			lines.append(text)
	return "\n".join(lines)


func _trace_text(runtime: WyrdRuntime) -> String:
	return JSON.stringify(runtime.trace.snapshot())


func _journal(runtime: WyrdRuntime, quest_id: String) -> String:
	var rows: Array = runtime.quests.journal(quest_id)
	if rows.is_empty():
		return ""
	return str((rows[0] as Dictionary).get("text", ""))


func _write_world(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _file(body: String) -> WyrdFileDef:
	var diagnostics := WyrdDiagnostics.new()
	var file := _compile(body, diagnostics)
	assert_false(diagnostics.has_errors(), diagnostics.format())
	return file


func _diagnostics(body: String) -> WyrdDiagnostics:
	var diagnostics := WyrdDiagnostics.new()
	_compile(body, diagnostics)
	return diagnostics


func _compile(body: String, diagnostics: WyrdDiagnostics) -> WyrdFileDef:
	var lines := PackedStringArray()
	for line in body.strip_edges().split("\n"):
		if line.begins_with("\t\t"):
			lines.append(line.substr(2))
		else:
			lines.append(line)
	var source := WyrdSource.new("res://validate.wyrd", "\n".join(lines) + "\n")
	var tree := WyrdParser.new().parse(source, diagnostics)
	return WyrdStatements.new().compile(source, tree, diagnostics)
