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
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, _aliases())
	var rewritten := {
		"publish": {
			"counters": {"tide_notice": 2},
			"covered": {"tide_notice": 10},
			"cursor": "issue\ttide_notice\t2\t60",
			"queued": ["tide_notice\t60"],
		},
		"rumor": {
			"jobs": [{"deed": "1", "verb": "settle"}],
			"reach": [{"deed": "1", "place": "dock", "verb": "settle"}],
		},
	}
	assert_eq(JSON.stringify(got["doc"]["flight"], "\t", true), JSON.stringify(rewritten, "\t", true))
	assert_eq(String(got["doc"]["facts"]["world"]["note"]), "skip harbor_gazette#2 due=60")
	assert_eq(int(got["doc"]["generator"]["counters"]["ferry_job"]), 3)
	assert_false(got["rows"].is_empty())


func test_trail_entries_are_rewritten_and_merged() -> void:
	var doc := {
		"quests": {
			"ferry_toll": {
				"stage": "offer",
				"trail": ["arrive", "offer", "old_stop", "offer"],
			},
		},
	}
	var aliases := {
		"stage": {
			"ferry_toll": {"offer": "depart", "old_stop": "depart"},
		},
	}
	var before := JSON.stringify(doc, "\t", true)
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, aliases)
	assert_eq(JSON.stringify(doc, "\t", true), before)
	var row: Dictionary = got["doc"]["quests"]["ferry_toll"]
	assert_eq(String(row["stage"]), "depart")
	assert_eq(row["trail"], ["arrive", "depart"])
	assert_eq(got["rows"], [
		_row("stage:ferry_toll", "offer", "depart", 1, ""),
		_row("trail:ferry_toll:offer", "offer", "depart", 2, ""),
		_row("trail:ferry_toll:old_stop", "old_stop", "depart", 1, ""),
	])
	assert_eq(got["diagnostics"], [])
	var second: Dictionary = WyrdSaveMigrate.apply_aliases(got["doc"], aliases)
	assert_eq(second["rows"], [])
	assert_eq(second["diagnostics"], [])
	var stayed := {
		"quests": {
			"ferry_toll": {"stage": "offer", "trail": ["arrive"]},
		},
	}
	var only_stage: Dictionary = WyrdSaveMigrate.apply_aliases(stayed, {"stage": {"ferry_toll": {"offer": "depart"}}})
	assert_eq(only_stage["doc"]["quests"]["ferry_toll"]["trail"], ["arrive"])
	assert_eq(only_stage["rows"], [_row("stage:ferry_toll", "offer", "depart", 1, "")])


func test_publish_stores_are_rewritten() -> void:
	var doc := {"flight": _publish_flight()}
	var before := JSON.stringify(doc, "\t", true)
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, _document_aliases())
	assert_eq(JSON.stringify(doc, "\t", true), before)
	assert_eq(JSON.stringify(got["doc"]["flight"], "\t", true), JSON.stringify(_publish_flight_moved(), "\t", true))
	assert_eq(got["rows"], [_row("document:harbor_gazette", "harbor_gazette", "tide_notice", 5, "")])
	assert_eq(got["diagnostics"], [])
	var second: Dictionary = WyrdSaveMigrate.apply_aliases(got["doc"], _document_aliases())
	assert_eq(second["rows"], [])


func test_a_read_of_the_new_id_does_not_drop_publish_state() -> void:
	var doc := {
		"documents": {
			"read": [
				{"doc": "tide_notice", "reader": "player"},
				{"doc": "harbor_gazette", "reader": "ada"},
			],
		},
		"flight": _publish_flight(),
	}
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, _document_aliases())
	var read: Array = got["doc"]["documents"]["read"]
	assert_eq(String(read[0]["doc"]), "tide_notice")
	assert_eq(String(read[1]["doc"]), "tide_notice")
	assert_eq(String(read[1]["reader"]), "ada")
	assert_eq(int(got["doc"]["flight"]["publish"]["counters"]["tide_notice"]), 2)
	assert_eq(got["rows"], [_row("document:harbor_gazette", "harbor_gazette", "tide_notice", 6, "")])
	assert_eq(got["diagnostics"], [])


func test_each_publish_collision_drops_the_old_state() -> void:
	_assert_publish_drop(_with_counter(), 7, {"tide_notice": 9}, {}, [], "", [])
	_assert_publish_drop(_with_covered(), 7, {}, {"tide_notice": 4}, [], "", [])
	_assert_publish_drop(_with_queued(), 7, {}, {}, ["tide_notice\t30"], "", [])
	_assert_publish_drop(_with_cursor(), 6, {}, {}, [], "issue\ttide_notice\t1\t10", [])
	_assert_publish_drop(_with_token(), 7, {}, {}, [], "", ["issue\ttide_notice\t9\t15"])


func test_rumor_verbs_are_rewritten_and_facts_stay() -> void:
	var doc := {
		"facts": {
			"known": {"dock_clerk": {"role.ferry_master.holder": true}},
			"world": {"note": "skip harbor_gazette#2 due=60"},
		},
		"flight": {
			"rumor": {
				"jobs": [{"deed": "1", "verb": "paid"}, {"deed": "2", "verb": "arrived"}],
				"reach": [{"deed": "1", "place": "dock", "verb": "paid"}],
			},
		},
		"generator": {"counters": {"ferry_job": 3}},
	}
	var before_facts := JSON.stringify(doc["facts"], "\t", true)
	var got: Dictionary = WyrdSaveMigrate.apply_aliases(doc, {"verb": {"paid": "settle"}})
	assert_eq(String(got["doc"]["flight"]["rumor"]["jobs"][0]["verb"]), "settle")
	assert_eq(String(got["doc"]["flight"]["rumor"]["jobs"][1]["verb"]), "arrived")
	assert_eq(String(got["doc"]["flight"]["rumor"]["reach"][0]["verb"]), "settle")
	assert_eq(JSON.stringify(got["doc"]["facts"], "\t", true), before_facts)
	assert_eq(int(got["doc"]["generator"]["counters"]["ferry_job"]), 3)
	assert_eq(got["rows"], [_row("verb:paid", "paid", "settle", 2, "")])
	assert_eq(got["diagnostics"], [])
	var second: Dictionary = WyrdSaveMigrate.apply_aliases(got["doc"], {"verb": {"paid": "settle"}})
	assert_eq(second["rows"], [])


func test_alias_wins_over_on_missing_stage() -> void:
	var content := _content()
	var doc := {
		"quests": {
			"tide_bell": {"stage": "offer", "status": "active", "trail": ["offer"]},
		},
	}
	var aliased: Dictionary = WyrdSaveMigrate.apply_aliases(doc, {"stage": {"tide_bell": {"offer": "toll"}}})
	assert_eq(String(aliased["doc"]["quests"]["tide_bell"]["stage"]), "toll")
	assert_eq(aliased["doc"]["quests"]["tide_bell"]["trail"], ["toll"])
	var got: Dictionary = WyrdSaveMigrate.resolve_stages(aliased["doc"], content)
	assert_eq(got["rows"], [])
	assert_eq(String(got["doc"]["quests"]["tide_bell"]["stage"]), "toll")


func test_each_fallback_is_chosen_in_order() -> void:
	var content := _content()
	var doc := {
		"quests": {
			"dock_errand": {"stage": "gone", "status": "active", "trail": ["wait", "hire", "gone"]},
			"ferry_toll": {"stage": "gone", "status": "active", "trail": ["arrive", "mid"]},
			"plain": {"stage": "gone", "status": "active"},
		},
	}
	var before := JSON.stringify(doc, "\t", true)
	var got: Dictionary = WyrdSaveMigrate.resolve_stages(doc, content)
	assert_eq(JSON.stringify(doc, "\t", true), before)
	var quests: Dictionary = got["doc"]["quests"]
	assert_eq(String(quests["ferry_toll"]["stage"]), "depart")
	assert_eq(String(quests["dock_errand"]["stage"]), "hire")
	assert_eq(String(quests["plain"]["stage"]), "only")
	assert_eq(got["rows"], [
		_stage_row("dock_errand", "gone", "hire"),
		_stage_row("ferry_toll", "gone", "depart"),
		_stage_row("plain", "gone", "only"),
	])
	assert_eq(String(got["diagnostics"][0]["message"]), "saved stage \"gone\" of \"dock_errand\" is gone; moved to \"hire\"")
	assert_eq(String(got["diagnostics"][1]["code"]), "W_SAVE_STAGE")
	var second: Dictionary = WyrdSaveMigrate.resolve_stages(got["doc"], content)
	assert_eq(second["rows"], [])
	assert_eq(JSON.stringify(second["doc"], "\t", true), JSON.stringify(got["doc"], "\t", true))


func test_a_generated_row_uses_its_template() -> void:
	var content := _content()
	var doc := {
		"quests": {
			"ferry_job#1": {"n": 1, "stage": "hire", "status": "active", "template": "ferry_job", "trail": ["wait", "hire"]},
			"other#9": {"n": 9, "stage": "hire", "template": "ferry_job"},
		},
	}
	var got: Dictionary = WyrdSaveMigrate.resolve_stages(doc, content)
	assert_eq(String(got["doc"]["quests"]["ferry_job#1"]["stage"]), "sign")
	assert_eq(String(got["doc"]["quests"]["other#9"]["stage"]), "sign")
	assert_eq(got["doc"]["quests"]["ferry_job#1"]["trail"], ["wait", "hire", "sign"])
	assert_eq(got["rows"], [
		_stage_row("ferry_job#1", "hire", "sign"),
		_stage_row("other#9", "hire", "sign"),
	])


func test_a_moved_row_arrives_entered() -> void:
	var content := _content()
	var quest: WyrdQuestDef = content.quests["ferry_toll"]
	var depart := _stage_named(quest, "depart")
	var doc := {
		"quests": {
			"ferry_toll": {
				"entered": false,
				"held_empty": true,
				"host_fields": ["note"],
				"host_returns": {"map": {"ok": true}},
				"host_screen": "map",
				"journal": [{"id": "j_arrive", "text": "In."}],
				"offered": "dock.talk",
				"outcomes": {"route": "done"},
				"regions": {"stale": {"stage": "x"}},
				"scene_done": true,
				"slots": ["ferry"],
				"stage": "gone",
				"status": "active",
				"step_at": 0,
				"trail": ["arrive", "mid"],
				"variant": "ferry.empty",
				"waiting": "scene:dock.talk",
			},
		},
		"roles": {"frozen": {"ferry_toll": {"ferry": {"holder": "player"}}}},
	}
	var got: Dictionary = WyrdSaveMigrate.resolve_stages(doc, content)
	var row: Dictionary = got["doc"]["quests"]["ferry_toll"]
	assert_eq(String(row["stage"]), "depart")
	assert_true(bool(row["entered"]))
	assert_eq(String(row["variant"]), "")
	assert_eq(int(row["step_at"]), WyrdQuestRunner.entry_step_count(depart))
	assert_eq(WyrdQuestRunner.entry_step_count(depart), 2)
	assert_eq(String(row["offered"]), "")
	assert_eq(String(row["waiting"]), "")
	assert_eq(String(row["host_screen"]), "")
	assert_false(bool(row["scene_done"]))
	assert_false(bool(row["held_empty"]))
	assert_eq(row["host_fields"], [])
	assert_false(row.has("regions"))
	assert_eq(String(row["status"]), "active")
	assert_eq(row["outcomes"], {"route": "done"})
	assert_eq(row["slots"], ["ferry"])
	assert_eq(row["host_returns"], {"map": {"ok": true}})
	assert_eq(row["journal"], [{"id": "j_arrive", "text": "In."}])
	assert_eq(row["trail"], ["arrive", "mid", "depart"])
	assert_eq(got["doc"]["roles"]["frozen"]["ferry_toll"]["ferry"]["holder"], "player")
	assert_eq(got["rows"], [_stage_row("ferry_toll", "gone", "depart")])


func test_a_region_leaf_restarts() -> void:
	var content := _content()
	var doc := {
		"quests": {
			"lantern_watch": {
				"regions": {
					"rope": {"entered": true, "stage": "old", "step_at": 1},
					"wick": {
						"entered": false,
						"regions": {"glass": {"entered": false, "stage": "fog", "step_at": 0}},
						"stage": "ember",
						"step_at": 0,
					},
				},
				"stage": "watch",
				"status": "active",
				"variant": "",
			},
		},
	}
	var got: Dictionary = WyrdSaveMigrate.resolve_stages(doc, content)
	var wick: Dictionary = got["doc"]["quests"]["lantern_watch"]["regions"]["wick"]
	assert_eq(String(wick["stage"]), "trim")
	assert_true(bool(wick["entered"]))
	assert_eq(int(wick["step_at"]), 1)
	assert_eq(String(wick["regions"]["glass"]["stage"]), "clear")
	assert_true(bool(wick["regions"]["glass"]["entered"]))
	assert_eq(int(wick["regions"]["glass"]["step_at"]), 1)
	assert_eq(String(got["doc"]["quests"]["lantern_watch"]["regions"]["rope"]["stage"]), "old")
	assert_eq(got["rows"], [_stage_row("lantern_watch/wick", "ember", "trim")])
	var second: Dictionary = WyrdSaveMigrate.resolve_stages(got["doc"], content)
	assert_eq(second["rows"], [])


func test_a_nested_leaf_restarts() -> void:
	var content := _content()
	var doc := {
		"quests": {
			"lantern_watch": {
				"regions": {
					"wick": {
						"entered": true,
						"regions": {"glass": {"entered": false, "stage": "gone", "step_at": 4}},
						"stage": "trim",
						"step_at": 3,
					},
				},
				"stage": "watch",
				"variant": "",
			},
		},
	}
	var got: Dictionary = WyrdSaveMigrate.resolve_stages(doc, content)
	var wick: Dictionary = got["doc"]["quests"]["lantern_watch"]["regions"]["wick"]
	assert_eq(String(wick["stage"]), "trim")
	assert_eq(int(wick["step_at"]), 3)
	assert_true(bool(wick["entered"]))
	var glass: Dictionary = wick["regions"]["glass"]
	assert_eq(String(glass["stage"]), "clear")
	assert_true(bool(glass["entered"]))
	assert_eq(int(glass["step_at"]), 1)
	assert_eq(got["rows"], [_stage_row("lantern_watch/wick/glass", "gone", "clear")])


func test_a_variant_body_restarts_its_own_region() -> void:
	var content := _content()
	var doc := {
		"quests": {
			"lantern_watch": {
				"regions": {
					"lamp": {"entered": false, "stage": "gone", "step_at": 0},
					"wick": {"entered": true, "stage": "dark", "step_at": 1},
				},
				"stage": "watch",
				"variant": "ferry.empty",
			},
		},
	}
	var got: Dictionary = WyrdSaveMigrate.resolve_stages(doc, content)
	var regions: Dictionary = got["doc"]["quests"]["lantern_watch"]["regions"]
	assert_eq(String(regions["wick"]["stage"]), "dark")
	assert_eq(String(regions["lamp"]["stage"]), "lit")
	assert_true(bool(regions["lamp"]["entered"]))
	assert_eq(int(regions["lamp"]["step_at"]), 1)
	assert_eq(got["rows"], [_stage_row("lantern_watch/lamp", "gone", "lit")])


func test_missing_quests_and_templates_stay() -> void:
	var content := _content()
	var doc := {
		"quests": {
			"ferry_job#9": {"n": 9, "stage": "hire", "template": "gone_job"},
			"old_errand": {"journal": [{"id": "j"}], "stage": "wait"},
			"plain": {"stage": "", "status": "dormant"},
		},
	}
	var got: Dictionary = WyrdSaveMigrate.resolve_stages(doc, content)
	assert_eq(got["rows"], [])
	assert_eq(got["diagnostics"], [])
	var returned: Dictionary = got["doc"]
	returned["marker"] = true
	assert_true(doc.has("marker"))
	doc.erase("marker")


func _assert_publish_drop(flight: Dictionary, count: int, counters: Dictionary, covered: Dictionary, queued: Array, cursor: String, tokens_left: Array) -> void:
	var got: Dictionary = WyrdSaveMigrate.apply_aliases({"flight": flight}, _document_aliases())
	var publish: Dictionary = got["doc"]["flight"]["publish"]
	assert_eq(publish.get("counters", {}), counters)
	assert_eq(publish.get("covered", {}), covered)
	assert_eq(publish.get("queued", []), queued)
	assert_eq(String(publish.get("cursor", "")), cursor)
	if cursor.is_empty():
		assert_false(publish.has("beliefs"))
		assert_false(publish.has("claim"))
	else:
		assert_eq(publish["beliefs"], [{"who": "bea"}])
		assert_eq(publish["claim"], {"source": "world", "value": "kept"})
	var tokens: Array = got["doc"]["flight"]["scheduler"]["publish"]
	assert_eq(tokens, tokens_left)
	assert_false(JSON.stringify(got["doc"]["flight"]).contains("harbor_gazette"))
	assert_eq(got["rows"], [_row("document:harbor_gazette", "harbor_gazette", "tide_notice", count, "W_SAVE_ALIAS")])
	assert_eq(got["diagnostics"].size(), 1)
	assert_eq(String(got["diagnostics"][0]["code"]), "W_SAVE_ALIAS")
	assert_eq(String(got["diagnostics"][0]["message"]), "saved document \"harbor_gazette\" was dropped because \"tide_notice\" is also saved")


func _publish_flight() -> Dictionary:
	return {
		"publish": {
			"beliefs": [{"deed": "1", "t": 1, "who": "ada"}],
			"claim": {"source": "world", "value": "old"},
			"counters": {"harbor_gazette": 2},
			"covered": {"harbor_gazette": 10},
			"cursor": "issue\tharbor_gazette\t2\t60",
			"queued": ["harbor_gazette\t60"],
		},
		"scheduler": {"publish": ["issue\tharbor_gazette\t2\t60"]},
	}


func _publish_flight_moved() -> Dictionary:
	return {
		"publish": {
			"beliefs": [{"deed": "1", "t": 1, "who": "ada"}],
			"claim": {"source": "world", "value": "old"},
			"counters": {"tide_notice": 2},
			"covered": {"tide_notice": 10},
			"cursor": "issue\ttide_notice\t2\t60",
			"queued": ["tide_notice\t60"],
		},
		"scheduler": {"publish": ["issue\ttide_notice\t2\t60"]},
	}


func _old_publish() -> Dictionary:
	return {
		"publish": {
			"beliefs": [{"deed": "1", "t": 1, "who": "ada"}],
			"claim": {"source": "world", "value": "old"},
			"counters": {"harbor_gazette": 2},
			"covered": {"harbor_gazette": 10},
			"cursor": "issue\tharbor_gazette\t2\t60",
			"queued": ["harbor_gazette\t60", "harbor_gazette\t120"],
		},
		"scheduler": {
			"publish": ["issue\tharbor_gazette\t2\t60", "issue\tharbor_gazette\t3\t120"],
		},
	}


func _with_counter() -> Dictionary:
	var flight := _old_publish()
	flight["publish"]["counters"]["tide_notice"] = 9
	return flight


func _with_covered() -> Dictionary:
	var flight := _old_publish()
	flight["publish"]["covered"]["tide_notice"] = 4
	return flight


func _with_queued() -> Dictionary:
	var flight := _old_publish()
	var queued: Array = flight["publish"]["queued"]
	queued.append("tide_notice\t30")
	return flight


func _with_cursor() -> Dictionary:
	var flight := _old_publish()
	flight["publish"]["cursor"] = "issue\ttide_notice\t1\t10"
	flight["publish"]["beliefs"] = [{"who": "bea"}]
	flight["publish"]["claim"] = {"source": "world", "value": "kept"}
	return flight


func _with_token() -> Dictionary:
	var flight := _old_publish()
	var tokens: Array = flight["scheduler"]["publish"]
	tokens.push_front("issue\ttide_notice\t9\t15")
	return flight


func _document_aliases() -> Dictionary:
	return {"document": {"harbor_gazette": "tide_notice"}}


func _content() -> WyrdContent:
	var source := WyrdSource.new("sample.wyrd", _STAGE_SOURCE)
	var diagnostics := WyrdDiagnostics.new()
	var tree := WyrdParser.new().parse(source, diagnostics)
	var unit := WyrdStatements.new().compile(source, tree, diagnostics)
	var errors: Array = []
	for item in diagnostics.items:
		if item.severity == WyrdDiagnostic.SEVERITY_ERROR:
			errors.append(item.message)
	assert_eq(errors, [])
	var content := WyrdContent.new()
	for quest in unit.quests:
		content.quests[quest.id] = quest
	for template in unit.templates:
		content.templates[template.id] = template
	return content


func _stage_named(quest: WyrdQuestDef, stage_id: String) -> WyrdStageDef:
	for stage in quest.stages:
		if stage.id == stage_id:
			return stage
	return null


func _stage_row(id: String, from_id: String, to_id: String) -> Dictionary:
	return {
		"code": "W_SAVE_STAGE",
		"count": 1,
		"from": from_id,
		"id": id,
		"kind": "missing_stage",
		"to": to_id,
	}


const _STAGE_SOURCE := """
language 1
facts
  world.stage_moved : bool stored

quest ferry_toll "Ferry Toll"
  on_missing_stage: depart
  stage arrive
    journal: In. #line:j_arrive
    waits_until false
  stage mid
    waits_until false
  stage depart
    journal: Left. #line:j_depart
    ~ set world.stage_moved = true
    -> done
  stage done
    waits_until false

quest dock_errand "Dock Errand"
  stage wait
    waits_until false
  stage hire
    waits_until false

quest plain "Plain"
  stage only
    waits_until false

quest tide_bell "Tide Bell"
  on_missing_stage: silence
  stage toll
    waits_until false
  stage silence
    waits_until false

template ferry_job "Ferry Job"
  stage sign
    journal: Signed. #line:j_sign
    ~ set world.stage_moved = true
    waits_until false

quest lantern_watch "Lantern Watch"
  slot ferry = ferry_master mode: live
  stage watch
    waits_until false
    variant ferry.empty:
      region lamp
        stage lit
          journal: Lit. #line:j_lit
        stage out
          waits_until false
    region wick
      stage trim
        journal: Trim. #line:j_trim
        region glass
          stage clear
            journal: Clear. #line:j_clear
          stage fog
            waits_until false
      stage dark
        waits_until false
"""


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
