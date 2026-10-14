extends RefCounted

const SAMPLE := "res://tests/scenario/pack/sample.wyrdmanifest.tres"
const HARBOR := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"


func open_pack(path: String) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var report := runtime.load_content(load(path) as WyrdContentManifest)
	return {"host": host, "report": report, "runtime": runtime}


func boot_gullhaven(local_tag: bool = false, coins: int = 4) -> Dictionary:
	var opened := open_pack(HARBOR)
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	var tags := PackedStringArray()
	if local_tag:
		tags.append("local")
	host.world.add_entity(&"player", &"person", "traveler", tags, true)
	host.world.add_entity(&"tavern_owner", &"person", "innkeeper", PackedStringArray(), true)
	host.world.add_entity(&"ferry_master", &"person", "ferry master", PackedStringArray(), true)
	host.world.add_entity(&"storm_watcher", &"person", "watcher", PackedStringArray(), true)
	host.world.add_entity(&"dock_apprentice", &"person", "apprentice", PackedStringArray(), true)
	host.world.add_entity(&"dock.bell", &"object", "bell", PackedStringArray(), true)
	runtime.start_new_game(1)
	runtime.roles.assign(&"tavern_owner", &"tavern_owner")
	runtime.roles.assign(&"ferry_master", &"ferry_master")
	runtime.roles.assign(&"storm_watcher", &"storm_watcher")
	runtime.facts.set(&"player.coins", coins)
	runtime.deeds.record(&"arrived", &"player", &"", &"gullhaven")
	runtime.tick(0)
	return opened


func line_rows(runtime: WyrdRuntime) -> Array:
	var rows: Array = []
	while runtime.dialogue.line() != null:
		var line := runtime.dialogue.line()
		rows.append({
			"audio": line.audio,
			"id": line.id,
			"name": line.display_name,
			"speaker": String(line.speaker),
			"text": line.text,
		})
		runtime.dialogue.advance()
	return rows


func ids_of(rows: Array) -> PackedStringArray:
	var ids := PackedStringArray()
	for row in rows:
		ids.append(String(row["id"]))
	return ids


func choose_text(runtime: WyrdRuntime, label: String) -> void:
	for view in runtime.dialogue.choices():
		if view.text == label and view.enabled:
			runtime.dialogue.choose(view.index)
			return
	push_error("missing enabled choice \"%s\"" % label)
