class_name WyrdSave
extends RefCounted

## JSON-safe snapshot of one runtime. Schema 2 fills belief bags on older saves.
##
## @experimental
## [member migrations] is the ordered table from schema N to N+1. Step 0 fills
## [code]facts.believed[/code] and [code]facts.held[/code]. 64-bit values are
## lowercase hex. A scene must be closed. A manifest hash mismatch warns in a
## debug build and is silent in a release.

const SCHEMA_VERSION := 2

static var migrations: Array = []


static func _static_init() -> void:
	migrations = [Callable(WyrdSave, &"_fill_belief_bags")]


static func _fill_belief_bags(data: Dictionary) -> Dictionary:
	var facts := _dict(data.get("facts", {}))
	if not (facts.get("believed") is Dictionary):
		facts["believed"] = {}
	if not (facts.get("held") is Dictionary):
		facts["held"] = {}
	data["facts"] = facts
	return data


static func capture(runtime: WyrdRuntime) -> Dictionary:
	var content := runtime.content()
	var packs: Array = []
	var language_version := 1
	if content != null:
		language_version = content.language_version
		packs.append({
			"hash": WyrdRng.format_u64(content.manifest_hash),
			"id": content.pack_id,
		})
	return {
		"content": {"packs": packs},
		"deeds": runtime.deeds.export_state(),
		"facts": runtime.facts.export_state(),
		"language_version": language_version,
		"minutes": runtime.play_minutes(),
		"provenance": runtime.effects.export_state(),
		"quests": runtime.quests.export_state(),
		"rng": runtime.export_rng(),
		"roles": runtime.roles.export_state(),
		"schema_version": SCHEMA_VERSION,
		"seed": WyrdRng.format_u64(runtime.game_seed()),
		"social": runtime.social.export_state(),
	}


static func apply(runtime: WyrdRuntime, data: Dictionary) -> WyrdLoadReport:
	var report := WyrdLoadReport.new()
	var content := runtime.content()
	if content == null:
		report.diagnostics.add(WyrdDiagnostic.E_SAVE_VERSION, "load content before loading a save", "", 1, 1)
		return report
	var working := data.duplicate(true)
	var version := _whole(working.get("schema_version", -1), -1)
	if version < 1:
		report.diagnostics.add(WyrdDiagnostic.E_SAVE_VERSION, "save schema_version is missing", "", 1, 1)
		return report
	var guard := 0
	while version < SCHEMA_VERSION and guard < 8:
		if version - 1 >= migrations.size() or not _callable(migrations[version - 1]):
			report.diagnostics.add(WyrdDiagnostic.E_SAVE_VERSION, "no migration from save schema %d" % version, "", 1, 1)
			return report
		var step: Callable = migrations[version - 1]
		var next: Variant = step.call(working)
		if not (next is Dictionary):
			report.diagnostics.add(WyrdDiagnostic.E_SAVE_VERSION, "migration %d did not return a save" % version, "", 1, 1)
			return report
		working = next
		version += 1
		guard += 1
	if version != SCHEMA_VERSION:
		report.diagnostics.add(WyrdDiagnostic.E_SAVE_VERSION, "no migration from save schema %d" % version, "", 1, 1)
		return report
	var seed_row := WyrdRng.parse_u64(String(working.get("seed", "")))
	if seed_row.is_empty():
		report.diagnostics.add(WyrdDiagnostic.E_SAVE_VERSION, "save seed is not 16 hex digits", "", 1, 1)
		return report
	var packs: Array = []
	var listed: Variant = _dict(working.get("content", {})).get("packs", [])
	if listed is Array:
		packs = listed
	if not packs.is_empty() and packs[0] is Dictionary:
		var hash_row := WyrdRng.parse_u64(String((packs[0] as Dictionary).get("hash", "")))
		if hash_row.is_empty():
			report.diagnostics.add(WyrdDiagnostic.E_SAVE_VERSION, "content hash is not 16 hex digits", "", 1, 1)
			return report
		if int(hash_row["n"]) != content.manifest_hash and OS.is_debug_build():
			report.diagnostics.add(
				WyrdDiagnostic.W_SAVE_MANIFEST,
				"content manifest hash differs from the save",
				"",
				1,
				1,
				WyrdDiagnostic.SEVERITY_WARNING
			)
	var rng_data := _dict(working.get("rng", {}))
	for stream_name in rng_data.keys():
		if not (rng_data[stream_name] is Dictionary) or WyrdRng.from_state(rng_data[stream_name]) == null:
			report.diagnostics.add(WyrdDiagnostic.E_SAVE_VERSION, "RNG stream \"%s\" is not a state" % String(stream_name), "", 1, 1)
			return report
	runtime.restore_clock(int(seed_row["n"]), _whole(working.get("minutes", 0), 0))
	runtime.facts.import_state(_dict(working.get("facts", {})))
	runtime.deeds.import_state(_dict(working.get("deeds", {})))
	runtime.social.import_state(_dict(working.get("social", {})))
	runtime.roles.import_state(_dict(working.get("roles", {})))
	runtime.quests.import_state(_dict(working.get("quests", {})))
	runtime.effects.import_state(_dict(working.get("provenance", {})))
	if not runtime.import_rng(rng_data):
		report.diagnostics.add(WyrdDiagnostic.E_SAVE_VERSION, "RNG streams were rejected", "", 1, 1)
		return report
	report.ok = true
	report.manifest_hash = content.manifest_hash
	return report


static func _dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


static func _whole(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return fallback


static func _callable(value: Variant) -> bool:
	return value is Callable and (value as Callable).is_valid()
