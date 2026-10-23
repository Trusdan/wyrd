extends GutTest

## Copy-on-write load, the deed shape walk, and the expiry index.
## Each result is the same document the plain path returns. No timings.


func test_a_save_with_nothing_to_rewrite_is_returned() -> void:
	var content := _content()
	var deeds: Array = [_deed()]
	var doc := {
		"deeds": {"next": 2, "rows": deeds},
		"quests": {
			"ferry_toll": {"stage": "arrive", "status": "active"},
			"lantern": {
				"regions": {"wick": {"entered": true, "stage": "trim", "step_at": 0}},
				"stage": "watch",
				"status": "active",
			},
		},
	}
	var before: Dictionary = doc.duplicate(true)
	var got: Dictionary = WyrdSaveMigrate.resolve_stages(doc, content)
	assert_eq(got["rows"], [])
	assert_eq(got["diagnostics"], [])
	assert_true(is_same(got["doc"], doc))
	assert_eq(doc, before)
	assert_true(is_same(doc["deeds"]["rows"], deeds))
	var aliases := {"verb": {"paid": "settle"}, "role": {"ferry_master": "dock_master"}}
	var aliased: Dictionary = WyrdSaveMigrate.apply_aliases(doc, aliases)
	assert_eq(aliased["rows"], [])
	assert_true(is_same(aliased["doc"], doc))
	assert_eq(String(doc["deeds"]["rows"][0]["verb"]), "arrived")


func test_a_rewrite_leaves_the_input_save() -> void:
	var content := _content()
	var deeds: Array = [_deed()]
	var doc := {
		"deeds": {"next": 2, "rows": deeds},
		"quests": {
			"ferry_toll": {"stage": "gone", "status": "active", "trail": ["arrive"]},
			"lantern": {
				"regions": {"wick": {"entered": false, "stage": "old", "step_at": 1}},
				"stage": "watch",
				"status": "active",
			},
		},
	}
	var before: Dictionary = doc.duplicate(true)
	var got: Dictionary = WyrdSaveMigrate.resolve_stages(doc, content)
	assert_eq(doc, before)
	assert_true(is_same(doc["deeds"]["rows"], deeds))
	assert_false(is_same(got["doc"], doc))
	assert_eq(String(doc["quests"]["ferry_toll"]["stage"]), "gone")
	assert_eq(String(got["doc"]["quests"]["ferry_toll"]["stage"]), "depart")
	assert_eq(String(got["doc"]["quests"]["lantern"]["regions"]["wick"]["stage"]), "trim")
	assert_eq(String(doc["quests"]["lantern"]["regions"]["wick"]["stage"]), "old")
	var ids: Array = []
	for row in got["rows"]:
		ids.append(String((row as Dictionary)["id"]))
	ids.sort()
	assert_eq(ids, ["ferry_toll", "lantern/wick"])
	var again: Dictionary = WyrdSaveMigrate.resolve_stages(got["doc"], content)
	assert_eq(again["rows"], [])
	assert_true(is_same(again["doc"], got["doc"]))
	doc["deeds"]["rows"][0]["verb"] = "paid"
	var aliased: Dictionary = WyrdSaveMigrate.apply_aliases(doc, {"verb": {"paid": "settle"}})
	assert_eq(String(doc["deeds"]["rows"][0]["verb"]), "paid")
	assert_eq(String(aliased["doc"]["deeds"]["rows"][0]["verb"]), "settle")
	assert_false(is_same(aliased["doc"], doc))
	assert_eq(aliased["rows"].size(), 1)


func test_deed_shape_matches_the_generic_first_issue() -> void:
	assert_eq(WyrdSave.check_shape({"deeds": {"rows": [_deed(), _named_deed()]}}, null), [])
	assert_eq(WyrdSave.check_shape({"deeds": {"rows": [{}]}, "minutes": 1.0}, null), [])
	assert_eq(
		WyrdSave.check_shape({"deeds": {"rows": [{"actor": 1, "id": "nope"}]}}, null),
		["save field deeds.rows.0.actor must be a string"]
	)
	assert_eq(
		WyrdSave.check_shape({"deeds": {"rows": [_deed(), {"actor": 1}]}}, null),
		["save field deeds.rows.1.actor must be a string"]
	)
	assert_eq(
		WyrdSave.check_shape({"deeds": {"rows": [{"id": 1.5}]}}, null),
		["save field deeds.rows.0.id must be an int"]
	)
	assert_eq(
		WyrdSave.check_shape({"deeds": {"rows": ["row"]}}, null),
		["save field deeds.rows.0 must be a dictionary"]
	)
	assert_eq(
		WyrdSave.check_shape({"deeds": {"rows": [{"tags": "rope"}]}}, null),
		["save field deeds.rows.0.tags must be an array"]
	)
	assert_eq(
		WyrdSave.check_shape({"deeds": {"rows": [{"tags": [1]}]}}, null),
		["save field deeds.rows.0.tags.0 must be a string"]
	)
	assert_eq(
		WyrdSave.check_shape({"deeds": {"rows": [{"memorable": 1}]}}, null),
		["save field deeds.rows.0.memorable must be a bool"]
	)
	assert_eq(
		WyrdSave.check_shape({"deeds": {"rows": [{"magnitude": "1"}]}}, null),
		["save field deeds.rows.0.magnitude must be a number"]
	)
	assert_eq(
		WyrdSave.check_shape({"deeds": {"rows": [{"believers": {"who": "ada"}}]}}, null),
		["save field deeds.rows.0.believers must be an array"]
	)
	assert_eq(
		WyrdSave.check_shape({"deeds": {"rows": [{"believers": [{"t": 1.5, "who": "ada"}]}]}}, null),
		["save field deeds.rows.0.believers.0.t must be an int"]
	)
	assert_eq(
		WyrdSave.check_shape({"deeds": {"rows": [{"believers": [{"who": 1}]}]}}, null),
		["save field deeds.rows.0.believers.0.who must be a string"]
	)
	assert_eq(
		WyrdSave.check_shape({"deeds": {"next": 2, "rows": [_deed()]}, "minutes": "soon"}, null),
		["save field minutes must be an int"]
	)


func test_expire_index_matches_a_full_scan() -> void:
	var opened := _open()
	var runtime: WyrdRuntime = opened["runtime"]
	var first := runtime.quests.create_instance("lasting")
	var quiet := runtime.quests.create_instance("brief")
	var second := runtime.quests.create_instance("lasting")
	assert_eq(first, "lasting#1")
	assert_eq(quiet, "brief#1")
	assert_eq(second, "lasting#2")
	assert_eq(_indexed(runtime.quests), ["lasting#1", "lasting#2"])
	assert_eq(_could_expire(runtime.quests), ["lasting#1", "lasting#2"])
	var unknown := _open()
	var other: WyrdRuntime = unknown["runtime"]
	other.quests.import_state({"gone#1": {"n": 1, "stage": "work", "status": "active", "template": "gone"}})
	assert_false(other.quests._expiring.has("gone#1"))
	assert_eq(_indexed(other.quests), _could_expire(other.quests))
	assert_false(runtime.quests._expiring.has("ferry"))
	assert_false(runtime.quests._expiring.has("brief#1"))
	runtime.tick(119)
	var due := _due(runtime.quests, 120)
	assert_eq(due, ["lasting#1", "lasting#2"])
	runtime.trace.enabled = true
	runtime.trace.clear()
	runtime.tick(1)
	var expired: Array = []
	for row in runtime.trace.events:
		if str(row.get("kind", "")) == "gen_expire":
			expired.append(str(row.get("instance", "")))
	assert_eq(expired, due)
	assert_eq(runtime.quests.status(first), &"abandoned")
	assert_eq(runtime.quests.status(second), &"abandoned")
	assert_eq(runtime.quests.status(quiet), &"active")
	assert_eq(runtime.quests.status("ferry"), &"dormant")
	var saved := runtime.quests.export_state()
	var loaded := _open()
	var fresh: WyrdRuntime = loaded["runtime"]
	fresh.quests.import_state(saved)
	assert_eq(_indexed(fresh.quests), _could_expire(fresh.quests))
	assert_eq(_indexed(fresh.quests), ["lasting#1", "lasting#2"])
	fresh.start_new_game(5)
	assert_eq(_indexed(fresh.quests), [])
	assert_eq(_could_expire(fresh.quests), [])


func _deed() -> Dictionary:
	return {
		"actor": "ada",
		"believers": [{"t": 1.0, "who": "bea", "extra": true}],
		"id": 1.0,
		"magnitude": 1,
		"memorable": false,
		"perception": ["saw"],
		"place": "dock",
		"t": 3,
		"tags": ["rope"],
		"target": "crate",
		"verb": "arrived",
		"visibility": "public",
		"witnesses": ["bea"],
		"zz_extra": 1,
	}


func _named_deed() -> Dictionary:
	return {"actor": StringName("ada"), "id": 2, "verb": StringName("arrived")}


func _indexed(quests: WyrdQuestRunner) -> Array:
	var ids: Array = quests._expiring.keys()
	ids.sort()
	return ids


func _could_expire(quests: WyrdQuestRunner) -> Array:
	var ids: Array = quests._states.keys()
	ids.sort()
	var out: Array = []
	for quest_id in ids:
		var state := quests._states.get(String(quest_id)) as WyrdQuestRunner.QuestState
		if state == null or state.template == "" or quests._expires_minutes(state.template) <= 0:
			continue
		out.append(String(quest_id))
	return out


func _due(quests: WyrdQuestRunner, now: int) -> Array:
	var out: Array = []
	for quest_id in _could_expire(quests):
		var key := String(quest_id)
		var state := quests._states.get(key) as WyrdQuestRunner.QuestState
		if state.status != quests.AVAILABLE and state.status != quests.ACTIVE:
			continue
		var created := now
		if quests._created.has(key):
			created = int(quests._created[key])
		if now - created < quests._expires_minutes(state.template):
			continue
		out.append(key)
	return out


func _open() -> Dictionary:
	var runtime := WyrdRuntime.new()
	var path := "user://wyrd_m11_perf.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_SOURCE.strip_edges() + "\n")
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(5)
	return {"runtime": runtime}


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
	return content


const _SOURCE := """
language 1
quest ferry "Ferry"
  start when false
  stage wait
    waits_until false
template lasting "Lasting"
  expires: 2h
  stage work
    waits_until false
template brief "Brief"
  stage work
    waits_until false
"""


const _STAGE_SOURCE := """
language 1
quest ferry_toll "Ferry Toll"
  on_missing_stage: depart
  stage arrive
    waits_until false
  stage depart
    waits_until false
quest lantern "Lantern"
  stage watch
    waits_until false
    region wick
      stage trim
        waits_until false
      stage dark
        waits_until false
"""
