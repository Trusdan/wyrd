extends GutTest

const _Facade := preload("res://addons/wyrd/runtime/wyrd.gd")
const _HARBOR := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"


func test_harbor_loads_and_hash_is_stable() -> void:
	var first := _open()
	var report: WyrdLoadReport = first["report"]
	assert_true(report.ok, report.diagnostics.format())
	assert_eq(report.error_count(), 0)
	var runtime: WyrdRuntime = first["runtime"]
	var content := runtime.content()
	assert_eq(content.pack_id, "harbor")
	assert_eq(content.manifest_hash, report.manifest_hash)
	assert_ne(content.manifest_hash, 0)
	assert_true(content.quests.has("ferry_toll"))
	assert_true(content.scenes.has("toll.offer_room"))
	assert_true(content.scenes.has("toll.depart"))
	assert_true(content.lines.has("a91f"))
	assert_gt(content.conditions.size(), 0)
	assert_eq(content.deps.entries > 0, true)
	var second := _open()
	var again: WyrdLoadReport = second["report"]
	assert_eq(again.manifest_hash, report.manifest_hash)
	var pack := WyrdLinkedPack.new()
	pack.pack_id = "harbor"
	pack.units = [
		{"hash": "0000000000000001", "path": "b.wyrd"},
		{"hash": "0000000000000002", "path": "a.wyrd"},
	]
	var forward := WyrdContent.hash_pack(pack)
	pack.units = [
		{"hash": "0000000000000002", "path": "a.wyrd"},
		{"hash": "0000000000000001", "path": "b.wyrd"},
	]
	assert_eq(WyrdContent.hash_pack(pack), forward)
	pack.pack_id = "other"
	assert_ne(WyrdContent.hash_pack(pack), forward)


func test_broken_pack_is_refused_and_runtime_stays_empty() -> void:
	var runtime := WyrdRuntime.new()
	var good := load(_HARBOR) as WyrdContentManifest
	assert_true(runtime.load_content(good).ok)
	assert_gt(runtime.condition_count(), 0)
	var path := "user://wyrd_s2a_broken.wyrd"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("this is not a content file\n")
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"broken"
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_false(report.ok)
	assert_gt(report.error_count(), 0)
	assert_eq(report.manifest_hash, 0)
	assert_null(runtime.content())
	assert_eq(runtime.condition_count(), 0)
	assert_null(runtime.facts.get(&"player.coins"))


func test_facade_forwards_load_tick_and_facts() -> void:
	var facade = _Facade.new()
	var host := WyrdFakeHost.new()
	host.register_into(facade._runtime)
	var report: WyrdLoadReport = facade.load_content(load(_HARBOR) as WyrdContentManifest)
	assert_true(report.ok, report.diagnostics.format())
	facade.start_new_game(3)
	facade.facts.set(&"player.coins", 4)
	assert_eq(facade.facts.get(&"player.coins"), 4)
	facade.tick(5)
	assert_eq(facade.now_minutes(), 5)
	assert_eq(facade.condition_count(), facade.content().conditions.size())
	assert_eq(facade.get_version(), WyrdRuntime.new().get_version())
	facade.free()


func test_register_adapter_and_function() -> void:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	assert_same(runtime.adapter(WyrdWorldAdapter), host.world)
	assert_false(runtime.register_function(&"has_tag", func(_args: Array) -> bool: return true, [&"entity", &"symbol"], &"bool"))
	assert_push_error("already registered")
	assert_false(runtime.register_function(&"has_tag", func(_args: Array) -> bool: return true, [&"int"], &"bool"))
	assert_push_error("does not match")
	var meter := func(args: Array) -> int: return int(args[0]) + 4
	assert_true(runtime.register_function(&"meter", meter, [&"int"], &"int"))
	assert_false(runtime.register_function(&"meter", meter, [&"int"], &"int"))
	assert_push_error("already registered")
	var compiled := WyrdCompiledCondition.new()
	compiled.code = PackedInt32Array([
		WyrdOpcodes.PUSH_CONST, 0, WyrdOpcodes.CALL, 1, 1,
	])
	compiled.consts = [3, &"meter"]
	assert_eq(WyrdRpnEval.new().eval(compiled, {}, runtime.function_table()), 7)


func _open() -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var report := runtime.load_content(load(_HARBOR) as WyrdContentManifest)
	runtime.start_new_game(11)
	return {"host": host, "report": report, "runtime": runtime}
