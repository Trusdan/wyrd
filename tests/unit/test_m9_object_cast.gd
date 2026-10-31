extends GutTest


class Offer extends WyrdWorldAdapter:
	var seen_kind := ""
	var seen_tag := ""
	var _world := WyrdFakeWorld.new()

	func add_entity(id: StringName, entity_kind: StringName, entity_name: String, entity_tags: PackedStringArray, alive: bool) -> void:
		_world.add_entity(id, entity_kind, entity_name, entity_tags, alive)

	func candidates(filter: WyrdEntityFilter) -> PackedStringArray:
		if filter != null:
			seen_kind = String(filter.kind)
			seen_tag = String(filter.tag)
		return _world.candidates(filter)

	func exists(id: StringName) -> bool:
		return _world.exists(id)

	func kind(id: StringName) -> StringName:
		return _world.kind(id)

	func tags(id: StringName) -> PackedStringArray:
		return _world.tags(id)

	func is_alive(id: StringName) -> bool:
		return _world.is_alive(id)

	func display_name(id: StringName) -> String:
		return _world.display_name(id)


class Loose extends WyrdWorldAdapter:
	var order := PackedStringArray()
	var seen_kind := ""
	var seen_tag := ""
	var _world := WyrdFakeWorld.new()

	func add_entity(id: StringName, entity_kind: StringName, entity_name: String, entity_tags: PackedStringArray, alive: bool) -> void:
		_world.add_entity(id, entity_kind, entity_name, entity_tags, alive)

	func candidates(filter: WyrdEntityFilter) -> PackedStringArray:
		if filter != null:
			seen_kind = String(filter.kind)
			seen_tag = String(filter.tag)
		return order

	func exists(id: StringName) -> bool:
		return _world.exists(id)

	func kind(id: StringName) -> StringName:
		return _world.kind(id)

	func tags(id: StringName) -> PackedStringArray:
		return _world.tags(id)

	func is_alive(id: StringName) -> bool:
		return _world.is_alive(id)

	func display_name(id: StringName) -> String:
		return _world.display_name(id)


func test_kind_filter_carries_kind_and_tag() -> void:
	var opened := _boot(_TAGGED, 4)
	var runtime: WyrdRuntime = opened["runtime"]
	var offer := Offer.new()
	offer.add_entity(&"dock.bollard_b", &"object", "South Bollard", PackedStringArray(["bollard"]), true)
	offer.add_entity(&"dock.bollard_a", &"object", "North Bollard", PackedStringArray(["bollard"]), true)
	offer.add_entity(&"bram", &"person", "Bram", PackedStringArray(["bollard"]), true)
	runtime.register_adapter(WyrdWorldAdapter, offer)
	runtime.trace.enabled = true
	runtime.roles.begin_quest("gate")
	assert_eq(offer.seen_kind, "object")
	assert_eq(offer.seen_tag, "bollard")
	var picked := String(runtime.roles.slot_holder("gate", &"post"))
	assert_eq(picked, _expect(["dock.bollard_a", "dock.bollard_b"], 4, 0))
	var row := _cast_event(runtime, "post")
	assert_eq(String(row["kind"]), "cast")
	assert_eq(String(row["slot_kind"]), "object")
	assert_eq(String(row["reason"]), "picked")
	assert_eq(String(row["entity"]), picked)
	assert_false(row.has("role"))
	var bare := _boot(_KIND_ONLY, 4)
	var second: WyrdRuntime = bare["runtime"]
	var open := Offer.new()
	open.add_entity(&"dock.rope", &"object", "rope", PackedStringArray(), true)
	open.add_entity(&"bram", &"person", "Bram", PackedStringArray(), true)
	second.register_adapter(WyrdWorldAdapter, open)
	second.roles.begin_quest("gate")
	assert_eq(open.seen_kind, "object")
	assert_eq(open.seen_tag, "")


func test_condition_recheck_sorts_and_ignores_offer_order() -> void:
	var first := _loose(PackedStringArray([
		"bram", "dock.crate", "dock.dead", "dock.bollard_b", "dock.bollard_a",
	]), 6)
	var second := _loose(PackedStringArray([
		"dock.bollard_a", "bram", "dock.bollard_b", "dock.crate", "dock.dead",
	]), 6)
	var expected := _expect(["dock.bollard_a", "dock.bollard_b"], 6, 0)
	assert_eq(String(first["runtime"].roles.slot_holder("gate", &"post")), expected)
	assert_eq(String(second["runtime"].roles.slot_holder("gate", &"post")), expected)
	assert_eq(String(first["world"].seen_kind), "object")
	assert_eq(String(first["world"].seen_tag), "bollard")
	var other := _loose(PackedStringArray(["dock.bollard_b", "dock.bollard_a"]), 9)
	assert_eq(String(other["runtime"].roles.slot_holder("gate", &"post")), _expect(["dock.bollard_a", "dock.bollard_b"], 9, 0))


func test_no_candidate_holds_on_empty_and_traces_empty() -> void:
	var opened := _boot(_EMPTY, 3)
	var runtime: WyrdRuntime = opened["runtime"]
	runtime.trace.enabled = true
	runtime.quests.start("gate")
	assert_eq(runtime.roles.slot_holder("gate", &"post"), &"")
	assert_eq(runtime.roles.slot_state(&"post", "gate"), &"empty")
	assert_eq(runtime.quests.waiting_reason("gate"), "on_empty")
	var row := _cast_event(runtime, "post")
	assert_eq(String(row["reason"]), "empty")
	assert_eq(String(row["entity"]), "")
	assert_eq(String(row["kind"]), "cast")
	assert_eq(String(row["slot_kind"]), "object")
	var printed := _slot_rows(runtime, "empty")
	assert_eq(printed.size(), 1)
	assert_eq(String(printed[0]["reason"]), "no_holder")
	assert_eq(String(printed[0]["kind"]), "slot_state")
	assert_eq(String(printed[0]["slot_kind"]), "object")
	assert_false(printed[0].has("role"))


func test_removing_an_object_locks_gone_once() -> void:
	var opened := _boot(_OBJECT, 2)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"dock.bollard_a", &"object", "North Bollard", PackedStringArray(["bollard"]), true)
	runtime.trace.enabled = true
	runtime.quests.start("gate")
	assert_eq(runtime.roles.slot_holder("gate", &"post"), &"dock.bollard_a")
	assert_eq(runtime.roles.slot_state(&"post", "gate"), &"default")
	var journal: Array = runtime.quests.journal("gate")
	assert_eq(str(journal[journal.size() - 1]["text"]), "The North Bollard holds the mooring.")
	host.world.remove_entity(&"dock.bollard_a")
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"post", "gate"), &"locked_gone")
	assert_eq(runtime.quests.variant_of("gate"), "post.locked_gone")
	journal = runtime.quests.journal("gate")
	assert_eq(str(journal[journal.size() - 1]["text"]), "The mooring post is gone.")
	var gone := _slot_rows(runtime, "locked_gone")
	assert_eq(gone.size(), 1)
	assert_eq(String(gone[0]["kind"]), "slot_state")
	assert_eq(String(gone[0]["reason"]), "gone")
	assert_eq(String(gone[0]["slot_kind"]), "object")
	runtime.tick(0)
	assert_eq(_slot_rows(runtime, "locked_gone").size(), 1)


func test_item_owner_change_locks_moved_and_save_keeps_owner() -> void:
	var opened := _boot(_ITEM, 5)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"coin.toll", &"item", "harbor coin", PackedStringArray(["toll"]), true)
	host.world.add_entity(&"dock.bollard_a", &"object", "North Bollard", PackedStringArray(["bollard"]), true)
	host.inventory.set_owner(&"coin.toll", &"player")
	runtime.trace.enabled = true
	runtime.quests.start("gate")
	assert_eq(runtime.roles.slot_holder("gate", &"coin"), &"coin.toll")
	assert_eq(runtime.roles.slot_state(&"coin", "gate"), &"default")
	var saved := runtime.save_state()
	var frozen: Dictionary = (saved["roles"] as Dictionary)["frozen"]
	var gate: Dictionary = frozen["gate"]
	assert_false((gate["post"] as Dictionary).has("owner"))
	assert_eq(String((gate["coin"] as Dictionary)["owner"]), "player")
	assert_eq(String((gate["coin"] as Dictionary)["holder"]), "coin.toll")
	var cast := _cast_event(runtime, "coin")
	assert_eq(String(cast["kind"]), "cast")
	assert_eq(String(cast["owner"]), "player")
	assert_eq(String(cast["slot_kind"]), "item")
	host.inventory.set_owner(&"coin.toll", &"bram")
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"coin", "gate"), &"locked_gone")
	var moved := _slot_rows(runtime, "locked_gone")
	assert_eq(moved.size(), 1)
	assert_eq(String(moved[0]["kind"]), "slot_state")
	assert_eq(String(moved[0]["reason"]), "moved")
	assert_eq(String(moved[0]["slot_kind"]), "item")
	var fresh := _boot(_ITEM, 1)
	var loaded: WyrdRuntime = fresh["runtime"]
	var next: WyrdFakeHost = fresh["host"]
	next.world.add_entity(&"coin.toll", &"item", "harbor coin", PackedStringArray(["toll"]), true)
	next.world.add_entity(&"dock.bollard_a", &"object", "North Bollard", PackedStringArray(["bollard"]), true)
	next.inventory.set_owner(&"coin.toll", &"player")
	loaded.trace.enabled = true
	var report := loaded.load_state(JSON.parse_string(JSON.stringify(saved)))
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(_cast_count(loaded), 0)
	assert_eq(loaded.roles.slot_holder("gate", &"coin"), &"coin.toll")
	assert_eq(loaded.roles.slot_holder("gate", &"post"), &"dock.bollard_a")
	assert_eq(loaded.roles.slot_state(&"coin", "gate"), &"default")
	assert_eq(loaded.roles.slot_state(&"post", "gate"), &"default")
	var again: Dictionary = (loaded.save_state()["roles"] as Dictionary)["frozen"]["gate"]
	assert_eq(String((again["coin"] as Dictionary)["owner"]), "player")
	assert_false((again["post"] as Dictionary).has("owner"))


func test_without_inventory_there_is_no_moved_and_exists_still_applies() -> void:
	var runtime := WyrdRuntime.new()
	var world := WyrdFakeWorld.new()
	world.add_entity(&"coin.toll", &"item", "harbor coin", PackedStringArray(["toll"]), true)
	runtime.register_adapter(WyrdWorldAdapter, world)
	var path := "user://wyrd_m9_object_cast.wyrd"
	_write(path, _BARE_ITEM)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	assert_true(runtime.load_content(manifest).ok)
	runtime.start_new_game(4)
	runtime.trace.enabled = true
	runtime.quests.start("gate")
	assert_eq(runtime.roles.slot_holder("gate", &"coin"), &"coin.toll")
	var saved := runtime.save_state()
	var snap: Dictionary = ((saved["roles"] as Dictionary)["frozen"] as Dictionary)["gate"]["coin"]
	assert_false(snap.has("owner"))
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"coin", "gate"), &"default")
	assert_eq(_slot_rows(runtime, "locked_gone").size(), 0)
	world.remove_entity(&"coin.toll")
	runtime.tick(0)
	assert_eq(runtime.roles.slot_state(&"coin", "gate"), &"locked_gone")
	assert_eq(String(_slot_rows(runtime, "locked_gone")[0]["reason"]), "gone")


func test_kind_slots_do_not_read_disposition() -> void:
	var opened := _boot(_OBJECT, 2)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	host.world.add_entity(&"dock.bollard_a", &"object", "North Bollard", PackedStringArray(["bollard"]), true)
	host.world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	runtime.quests.start("gate")
	runtime.social.set_baseline(&"dock.bollard_a", &"player", &"affinity", -400.0)
	runtime.trace.enabled = true
	runtime.trace.clear()
	var resolved: Dictionary = runtime.roles.resolve_slot("gate", &"post", true)
	assert_eq(String(resolved["state"]), "default")
	assert_eq(String(resolved["reason"]), "holder")
	for row in runtime.trace.events:
		assert_ne(String(row.get("kind", "")), "social_cache")
		if String(row.get("kind", "")) == "slot_state":
			assert_ne(String(row.get("state", "")), "hostile")


const _TAGGED := """
language 1
quest gate "Gate"
  slot post kind: object mode: cast(has_tag(candidate, bollard))
  stage hold
    waits_until false
"""

const _KIND_ONLY := """
language 1
quest gate "Gate"
  slot post kind: object mode: cast(alive(candidate))
  stage hold
    waits_until false
"""

const _LOOSE := """
language 1
quest gate "Gate"
  slot post kind: object mode: cast(has_tag(candidate, bollard) and kind(candidate) == object and alive(candidate))
  stage hold
    waits_until false
"""

const _EMPTY := """
language 1
quest gate "Gate"
  on_empty: wait
  slot post kind: object mode: cast(has_tag(candidate, bollard))
  stage hold
    journal: {holder(post).name} waits. #line:j_hold
    waits_until false
"""

const _OBJECT := """
language 1
quest gate "Gate"
  slot post kind: object mode: cast(has_tag(candidate, bollard))
  stage hold
    journal: The {holder(post).name} holds the mooring. #line:holds
    waits_until false
    variant post.empty:
      journal: No bollard stands for the mooring. #line:empty
      waits_until false
    variant post.locked_gone:
      journal: The mooring post is gone. #line:gone
      waits_until false
"""

const _ITEM := """
language 1
quest gate "Gate"
  slot post kind: object mode: cast(has_tag(candidate, bollard))
  slot coin kind: item mode: cast(has_tag(candidate, toll))
  stage hold
    waits_until false
    variant post.locked_gone:
      waits_until false
    variant post.empty:
      waits_until false
    variant coin.locked_gone:
      waits_until false
    variant coin.empty:
      waits_until false
"""

const _BARE_ITEM := """
language 1
quest gate "Gate"
  slot coin kind: item mode: cast(has_tag(candidate, toll))
  stage hold
    waits_until false
    variant coin.locked_gone:
      waits_until false
    variant coin.empty:
      waits_until false
"""


func _boot(body: String, seed_value: int) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var path := "user://wyrd_m9_object_cast.wyrd"
	_write(path, body)
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(seed_value)
	return {"host": host, "runtime": runtime}


func _loose(order: PackedStringArray, seed_value: int) -> Dictionary:
	var opened := _boot(_LOOSE, seed_value)
	var runtime: WyrdRuntime = opened["runtime"]
	var world := Loose.new()
	world.add_entity(&"dock.bollard_a", &"object", "North Bollard", PackedStringArray(["bollard"]), true)
	world.add_entity(&"dock.bollard_b", &"object", "South Bollard", PackedStringArray(["bollard"]), true)
	world.add_entity(&"dock.dead", &"object", "Old Bollard", PackedStringArray(["bollard"]), false)
	world.add_entity(&"dock.crate", &"object", "crate", PackedStringArray(), true)
	world.add_entity(&"bram", &"person", "Bram", PackedStringArray(["bollard"]), true)
	world.order = order
	runtime.register_adapter(WyrdWorldAdapter, world)
	runtime.roles.begin_quest("gate")
	return {"runtime": runtime, "world": world}


func _expect(ids: Array, seed_value: int, now: int) -> String:
	var sorted: Array = ids.duplicate()
	sorted.sort()
	var rng := WyrdRng.for_decision(seed_value, &"cast", &"gate|post", now)
	return String(sorted[rng.randi_bounded(sorted.size())])


func _cast_count(runtime: WyrdRuntime) -> int:
	var count := 0
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "cast":
			count += 1
	return count


func _cast_event(runtime: WyrdRuntime, slot_name: String) -> Dictionary:
	var found := {}
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "cast" and String(row.get("slot", "")) == slot_name:
			found = row
	return found


func _slot_rows(runtime: WyrdRuntime, state_name: String) -> Array:
	var rows: Array = []
	for row in runtime.trace.events:
		if String(row.get("kind", "")) == "slot_state" and String(row.get("state", "")) == state_name:
			rows.append(row)
	return rows


func _write(path: String, body: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
