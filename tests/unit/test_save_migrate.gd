extends GutTest

## Pure alias rewrite. No runtime.


func test_each_kind_is_rewritten() -> void:
	var doc := _full_doc()
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, _aliases())
	var quests: Dictionary = got["doc"]["quests"]
	assert_eq(String(quests["ferry_toll"]["stage"]), "depart")
	assert_eq(String(quests["ferry_job#3"]["stage"]), "sign")
	var roles: Dictionary = got["doc"]["roles"]
	assert_false(roles["bindings"].has("ferry_master"))
	assert_eq(String(roles["bindings"]["dock_master"]["holder"]), "player")
	assert_true(roles["defs"].has("dock_master"))
	assert_eq(roles["told"]["dock_master"], ["dock_clerk"])
	assert_eq(String(roles["pending"]["dock_master"]["departed"]), "ada")
	assert_eq(roles["abolished"], ["dock_master"])
	assert_eq(String(roles["frozen"]["ferry_toll"]["ferry"]["holder"]), "player")
	var verbs: Array = []
	for row in got["doc"]["deeds"]["rows"]:
		verbs.append(String((row as Dictionary)["verb"]))
	assert_eq(verbs, ["settle", "arrived", "settle"])
	assert_eq(String(got["doc"]["deeds"]["rows"][0]["id"]), "1")
	var read: Array = got["doc"]["documents"]["read"]
	assert_eq(String(read[0]["doc"]), "tide_notice")
	assert_eq(String(read[0]["reader"]), "player")
	var copies: Array = got["doc"]["documents"]["copies"]
	assert_eq(String(copies[0]["doc"]), "tide_notice")
	assert_eq(String(copies[0]["copy"]), "kept")
	assert_eq(int(copies[0]["record"]["n"]), 1)
	assert_eq(got["rows"], [
		_row("document:harbor_gazette", "harbor_gazette", "tide_notice", 2, ""),
		_row("role:ferry_master", "ferry_master", "dock_master", 5, ""),
		_row("stage:ferry_job#3", "hire", "sign", 1, ""),
		_row("stage:ferry_toll", "offer", "depart", 1, ""),
		_row("verb:paid", "paid", "settle", 2, ""),
	])
	assert_eq(got["diagnostics"], [])


func test_template_stage_tables_apply_to_generated_rows() -> void:
	var doc := {
		"quests": {
			"other#9": {"n": 9, "stage": "hire", "template": "ferry_job"},
			"ferry_job#3": {"n": 3, "stage": "hire"},
		},
	}
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, _aliases())
	var quests: Dictionary = got["doc"]["quests"]
	assert_eq(String(quests["other#9"]["stage"]), "sign")
	assert_eq(String(quests["ferry_job#3"]["stage"]), "sign")
	assert_eq(String(quests["other#9"]["template"]), "ferry_job")
	assert_eq(got["rows"], [
		_row("stage:ferry_job#3", "hire", "sign", 1, ""),
		_row("stage:other#9", "hire", "sign", 1, ""),
	])


func test_a_stage_without_a_table_stays() -> void:
	var doc := {
		"quests": {
			"dock_errand": {"stage": "offer"},
			"ferry_toll": {"stage": "arrive"},
		},
	}
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, _aliases())
	var quests: Dictionary = got["doc"]["quests"]
	assert_eq(String(quests["dock_errand"]["stage"]), "offer")
	assert_eq(String(quests["ferry_toll"]["stage"]), "arrive")
	assert_eq(got["rows"], [])
	assert_eq(got["diagnostics"], [])
	var returned: Dictionary = got["doc"]
	returned["marker"] = true
	assert_true(doc.has("marker"))


func test_region_leaves_stay() -> void:
	var doc := {
		"quests": {
			"ferry_toll": {
				"journal": [{"date": "", "id": "j", "minutes": 0, "text": "offer"}],
				"regions": {
					"dock": {
						"regions": {"inner": {"stage": "hire"}},
						"stage": "offer",
					},
				},
				"stage": "offer",
			},
		},
	}
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, _aliases())
	var row: Dictionary = got["doc"]["quests"]["ferry_toll"]
	assert_eq(String(row["stage"]), "depart")
	assert_eq(String(row["regions"]["dock"]["stage"]), "offer")
	assert_eq(String(row["regions"]["dock"]["regions"]["inner"]["stage"]), "hire")
	assert_eq(String(row["journal"][0]["text"]), "offer")
	assert_eq(got["rows"], [_row("stage:ferry_toll", "offer", "depart", 1, "")])


func test_collisions_keep_the_new_data() -> void:
	_assert_role_map_collision()
	_assert_abolished_collision()
	_assert_read_collision()
	_assert_copy_collision()
	_assert_two_olds_one_new()


func test_empty_tables_return_the_input() -> void:
	var doc := {"quests": {"ferry_toll": {"stage": "offer"}}}
	for aliases in [{}, {"stage": {}}, {"other": {"a": "b"}}, {"verb": "nope"}]:
		var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, aliases)
		assert_eq(got["rows"], [])
		assert_eq(got["diagnostics"], [])
		var returned: Dictionary = got["doc"]
		returned["marker"] = true
		assert_true(doc.has("marker"))
		doc.erase("marker")


func test_the_input_is_not_mutated() -> void:
	var doc := _full_doc()
	var before := JSON.stringify(doc, "\t", true)
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, _aliases())
	assert_eq(JSON.stringify(doc, "\t", true), before)
	assert_ne(got["doc"], doc)
	assert_false(got["rows"].is_empty())


func test_a_second_run_adds_no_rows() -> void:
	var first: Dictionary = WyrdSaveMigrate.apply_aliases(_full_doc(), _aliases())
	var second: Dictionary = WyrdSaveMigrate.apply_aliases(first["doc"], _aliases())
	assert_eq(second["rows"], [])
	assert_eq(second["diagnostics"], [])
	assert_eq(JSON.stringify(second["doc"], "\t", true), JSON.stringify(first["doc"], "\t", true))


func test_the_same_input_gives_the_same_output() -> void:
	var aliases := _aliases()
	var doc := _full_doc()
	var left: Dictionary = WyrdSaveMigrate.apply_aliases(doc, aliases)
	var right: Dictionary = WyrdSaveMigrate.apply_aliases(doc, aliases)
	assert_eq(JSON.stringify(left, "\t", true), JSON.stringify(right, "\t", true))


func test_publish_and_rumor_rows_stay() -> void:
	var doc := _full_doc()
	var flight: Dictionary = {
		"publish": {
			"counters": {"harbor_gazette": 2},
			"covered": {"harbor_gazette": 10},
			"cursor": "issue\tharbor_gazette\t2\t60",
			"queued": ["harbor_gazette\t60"],
		},
		"rumor": {
			"jobs": [{"deed": "1", "verb": "paid"}],
			"reach": [{"deed": "1", "place": "dock", "verb": "paid"}],
		},
	}
	doc["facts"] = {"world": {"note": "skip harbor_gazette#2 due=60"}}
	doc["flight"] = flight
	doc["generator"] = {"counters": {"ferry_job": 3}}
	var before_flight := JSON.stringify(flight, "\t", true)
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, _aliases())
	assert_eq(JSON.stringify(got["doc"]["flight"], "\t", true), before_flight)
	assert_eq(String(got["doc"]["facts"]["world"]["note"]), "skip harbor_gazette#2 due=60")
	assert_eq(int(got["doc"]["generator"]["counters"]["ferry_job"]), 3)
	assert_false(got["rows"].is_empty())


func _assert_role_map_collision() -> void:
	var doc := {
		"roles": {
			"bindings": {
				"dock_master": {"holder": "ada", "history": [1]},
				"ferry_master": {"holder": "player", "history": []},
			},
			"told": {"ferry_master": ["dock_clerk"]},
		},
	}
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, _aliases())
	var bindings: Dictionary = got["doc"]["roles"]["bindings"]
	assert_false(bindings.has("ferry_master"))
	assert_eq(String(bindings["dock_master"]["holder"]), "ada")
	assert_eq(bindings["dock_master"]["history"], [1])
	assert_eq(got["doc"]["roles"]["told"]["dock_master"], ["dock_clerk"])
	assert_eq(got["rows"], [
		_row("role:ferry_master", "ferry_master", "dock_master", 1, ""),
		_row("role:ferry_master", "ferry_master", "dock_master", 1, "W_SAVE_ALIAS"),
	])
	_assert_one_drop(got, "role", "ferry_master", "dock_master")


func _assert_abolished_collision() -> void:
	var doc := {"roles": {"abolished": ["ferry_master", "dock_master"]}}
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, _aliases())
	assert_eq(got["doc"]["roles"]["abolished"], ["dock_master"])
	assert_eq(got["rows"], [
		_row("role:ferry_master", "ferry_master", "dock_master", 1, "W_SAVE_ALIAS"),
	])
	_assert_one_drop(got, "role", "ferry_master", "dock_master")


func _assert_read_collision() -> void:
	var doc := {
		"documents": {
			"read": [
				{"doc": "harbor_gazette", "reader": "ada"},
				{"doc": "harbor_gazette", "reader": "bea"},
				{"doc": "tide_notice", "reader": "bea"},
			],
		},
	}
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, _aliases())
	assert_eq(got["doc"]["documents"]["read"], [
		{"doc": "tide_notice", "reader": "ada"},
		{"doc": "tide_notice", "reader": "bea"},
	])
	assert_eq(got["rows"], [
		_row("document:harbor_gazette", "harbor_gazette", "tide_notice", 1, ""),
		_row("document:harbor_gazette", "harbor_gazette", "tide_notice", 1, "W_SAVE_ALIAS"),
	])
	_assert_one_drop(got, "document", "harbor_gazette", "tide_notice")


func _assert_copy_collision() -> void:
	var doc := {
		"documents": {
			"copies": [
				{"copy": "kept", "doc": "harbor_gazette", "record": {"v": "old"}},
				{"copy": "kept", "doc": "tide_notice", "record": {"v": "new"}},
				{"copy": "other", "doc": "harbor_gazette", "record": {"v": "move"}},
			],
		},
	}
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, _aliases())
	assert_eq(got["doc"]["documents"]["copies"], [
		{"copy": "kept", "doc": "tide_notice", "record": {"v": "new"}},
		{"copy": "other", "doc": "tide_notice", "record": {"v": "move"}},
	])
	assert_eq(got["rows"], [
		_row("document:harbor_gazette", "harbor_gazette", "tide_notice", 1, ""),
		_row("document:harbor_gazette", "harbor_gazette", "tide_notice", 1, "W_SAVE_ALIAS"),
	])
	_assert_one_drop(got, "document", "harbor_gazette", "tide_notice")


func _assert_two_olds_one_new() -> void:
	var aliases := _aliases()
	aliases["role"] = {"boatman": "dock_master", "ferry_master": "dock_master"}
	var doc := {
		"roles": {
			"bindings": {
				"boatman": {"holder": "ada"},
				"ferry_master": {"holder": "bea"},
			},
		},
	}
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, aliases)
	var bindings: Dictionary = got["doc"]["roles"]["bindings"]
	assert_eq(bindings.size(), 1)
	assert_eq(String(bindings["dock_master"]["holder"]), "ada")
	assert_eq(got["rows"], [
		_row("role:boatman", "boatman", "dock_master", 1, ""),
		_row("role:ferry_master", "ferry_master", "dock_master", 1, "W_SAVE_ALIAS"),
	])
	_assert_one_drop(got, "role", "ferry_master", "dock_master")


func _assert_one_drop(got: Dictionary, kind: String, old: String, new_id: String) -> void:
	assert_eq(got["diagnostics"].size(), 1)
	var note: Dictionary = got["diagnostics"][0]
	assert_eq(String(note["code"]), "W_SAVE_ALIAS")
	assert_eq(String(note["severity"]), "warning")
	assert_eq(
		String(note["message"]),
		"saved %s \"%s\" was dropped because \"%s\" is also saved" % [kind, old, new_id]
	)


func _full_doc() -> Dictionary:
	return {
		"deeds": {
			"rows": [
				{"actor": "player", "id": "1", "verb": "paid"},
				{"actor": "player", "id": "2", "verb": "arrived"},
				{"actor": "ada", "id": "3", "verb": "paid"},
			],
		},
		"documents": {
			"copies": [{"copy": "kept", "doc": "harbor_gazette", "record": {"n": 1}}],
			"read": [{"doc": "harbor_gazette", "reader": "player"}],
		},
		"quests": {
			"ferry_job#3": {"n": 3, "stage": "hire", "template": "ferry_job"},
			"ferry_toll": {"stage": "offer", "status": "active"},
		},
		"roles": {
			"abolished": ["ferry_master"],
			"bindings": {"ferry_master": {"holder": "player"}},
			"defs": {"ferry_master": {"scope": "world"}},
			"frozen": {"ferry_toll": {"ferry": {"holder": "player", "status": "locked"}}},
			"pending": {"ferry_master": {"departed": "ada", "since": 1}},
			"told": {"ferry_master": ["dock_clerk"]},
		},
	}


func _aliases() -> Dictionary:
	return {
		"document": {"harbor_gazette": "tide_notice"},
		"role": {"ferry_master": "dock_master"},
		"stage": {
			"ferry_job": {"hire": "sign"},
			"ferry_toll": {"offer": "depart"},
		},
		"verb": {"paid": "settle", "pay": "settle"},
	}


func _row(id: String, from_id: String, to_id: String, count: int, code: String) -> Dictionary:
	return {
		"code": code,
		"count": count,
		"from": from_id,
		"id": id,
		"kind": "alias",
		"to": to_id,
	}
