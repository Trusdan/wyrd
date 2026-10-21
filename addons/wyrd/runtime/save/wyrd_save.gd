class_name WyrdSave
extends RefCounted

## JSON-safe snapshot of one runtime. Schema 4 adds [code]generator[/code]
## when a generated quest instance exists. Schema 3 stores in-flight rumors,
## publish counters, and scheduler carry in [code]flight[/code] when any of
## that exists. Schema 2 fills belief bags. A schema 2 document has no
## [code]flight[/code] key and loads with empty in-flight state.
## Evidence deadlines, when any exist, ride in [code]facts.evidence[/code].
## Line-set draw state and director [code]seen[/code] / [code]last_minute[/code],
## when any of that exists, ride in [code]storylets[/code]. An unknown storylet
## id is kept in that bag and ignored. Bark speaker clocks, when any exist,
## ride in [code]bark_speakers[/code]. An unknown speaker id is kept. A missing
## [code]bark_speakers[/code] key clears those clocks and leaves storylet rows.
## Sequence progress, when any exists, rides in [code]sequences[/code]. An unknown
## sequence id is kept. A missing [code]sequences[/code] key clears that bag only.
## Unlocked topic ids, when any exist, ride in [code]topics[/code] as a sorted
## list. An unknown id is kept. A missing [code]topics[/code] key clears that set.
## Read flags and frozen copies, when any exist, ride in [code]documents[/code].
## Read flags are [code](reader, doc)[/code] pairs, not stored facts. A missing
## [code]documents[/code] key clears both lists. Unknown ids are kept and ignored.
## Quest region leaves ride inside the quest row and are omitted when empty.
## An older loader ignores those keys. The unlocked secrecy name is an ordinary
## world fact. The document has no secrecy key.
##
## @experimental
## [member migrations] is the ordered table from schema N to N+1. Step 0 fills
## [code]facts.believed[/code] and [code]facts.held[/code]. Step 1 leaves the
## document as it is. Step 2 adds an empty [code]generator[/code] object when
## the key is missing. It does not write [code]schema_version[/code] and it
## does not change [code]quests[/code]. The file's own version stays in place
## so [method _import_flight] still compares it with
## [constant FLIGHT_SINCE_SCHEMA]. A schema 2 file has no [code]flight[/code]
## key: token queues and the slice come back empty, and the dirty waits stay
## armed. A save from schema 3 on omits [code]flight[/code] only when that set
## was empty, so load clears the dirty waits. [constant FLIGHT_SINCE_SCHEMA]
## pins that rule, and a later schema bump leaves it in place.
## [code]generator[/code] holds instance counters and casts. It is omitted
## when there are no counters. A generated quest row adds [code]template[/code]
## and [code]n[/code]. A missing template keeps those rows, entries, and
## counters, and warns [code]W_SAVE_TEMPLATE[/code]. Schema 5 is refused.
## 64-bit values are lowercase hex. A scene must be closed. A manifest hash
## mismatch warns in a debug build and is silent in a release.

const SCHEMA_VERSION := 4
const FLIGHT_SINCE_SCHEMA := 3

static var migrations: Array = []


static func _static_init() -> void:
	migrations = [
		Callable(WyrdSave, &"_fill_belief_bags"),
		Callable(WyrdSave, &"_keep_document"),
		Callable(WyrdSave, &"_add_generator"),
	]


static func _fill_belief_bags(data: Dictionary) -> Dictionary:
	var facts := _dict(data.get("facts", {}))
	if not (facts.get("believed") is Dictionary):
		facts["believed"] = {}
	if not (facts.get("held") is Dictionary):
		facts["held"] = {}
	data["facts"] = facts
	return data


## Schema 2 documents have no [code]flight[/code] key. Leaving the document
## unchanged is the migration. Load treats the missing key as empty in-flight state.
static func _keep_document(data: Dictionary) -> Dictionary:
	return data


## Schema 3 documents have no [code]generator[/code] key. The empty object is
## the migration. This step does not write [code]schema_version[/code].
static func _add_generator(data: Dictionary) -> Dictionary:
	if not data.has("generator"):
		data["generator"] = {}
	return data


## A [StringName] is [code]{"t": "symbol", "v": "..."}[/code].
## A float is [code]{"t": "float", "v": n}[/code] so [code]1.0[/code] stays a float.
## Bool, int, string, and null stay JSON values.
static func pack_claim(value: Variant) -> Variant:
	if value is StringName:
		return {"t": "symbol", "v": String(value)}
	if typeof(value) == TYPE_FLOAT:
		return {"t": "float", "v": value}
	return value


## Inverse of [method pack_claim]. A whole JSON number that was not tagged
## comes back as an int. A tagged float stays a float.
static func unpack_claim(value: Variant) -> Variant:
	if value is Dictionary:
		var row: Dictionary = value
		var tag := str(row.get("t", ""))
		if tag == "symbol":
			return StringName(str(row.get("v", "")))
		if tag == "float":
			return float(row.get("v", 0.0))
	if typeof(value) == TYPE_FLOAT and value == floor(value):
		if value >= -2147483648.0 and value <= 2147483647.0:
			return int(value)
	return value


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
	var data := {
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
	if runtime.storylets != null:
		var drawn := runtime.storylets.export_state()
		if not drawn.is_empty():
			data["storylets"] = drawn
		var speakers := runtime.storylets.export_speakers()
		if not speakers.is_empty():
			data["bark_speakers"] = speakers
	if runtime.sequences != null:
		var sequences := runtime.sequences.export_state()
		if not sequences.is_empty():
			data["sequences"] = sequences
	if runtime.topics != null:
		var topics := runtime.topics.export_state()
		if not topics.is_empty():
			var names: Array = []
			for topic in topics:
				names.append(String(topic))
			data["topics"] = names
	if runtime.documents != null:
		var documents := runtime.documents.export_state()
		if not documents.is_empty():
			data["documents"] = documents
	var flight := _capture_flight(runtime)
	if not flight.is_empty():
		data["flight"] = flight
	var generator := runtime.quests.export_generator()
	if not generator.is_empty():
		data["generator"] = generator
	return data


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
	var generator := {}
	if working.get("generator") is Dictionary:
		generator = working.get("generator")
	runtime.quests.import_generator(generator, report)
	runtime.quests.import_state(_dict(working.get("quests", {})))
	runtime.effects.import_state(_dict(working.get("provenance", {})))
	if not runtime.import_rng(rng_data):
		report.diagnostics.add(WyrdDiagnostic.E_SAVE_VERSION, "RNG streams were rejected", "", 1, 1)
		return report
	if runtime.storylets != null:
		if working.has("storylets"):
			runtime.storylets.import_state(_dict(working.get("storylets", {})))
		else:
			runtime.storylets.clear_draws()
		if working.has("bark_speakers"):
			runtime.storylets.import_speakers(_dict(working.get("bark_speakers", {})))
		else:
			runtime.storylets.clear_speakers()
	if runtime.sequences != null:
		if working.has("sequences"):
			runtime.sequences.import_state(_dict(working.get("sequences", {})))
		else:
			runtime.sequences.clear()
	if runtime.topics != null:
		if working.has("topics") and working.get("topics") is Array:
			runtime.topics.import_state(working.get("topics"))
		else:
			runtime.topics.clear()
	if runtime.documents != null:
		if working.has("documents") and working.get("documents") is Dictionary:
			runtime.documents.import_state(working.get("documents"))
		else:
			runtime.documents.clear()
	_import_flight(runtime, working, report)
	report.ok = true
	report.manifest_hash = content.manifest_hash
	return report


static func _capture_flight(runtime: WyrdRuntime) -> Dictionary:
	var out := {}
	if runtime.publish != null:
		var publish := runtime.publish.export_state()
		if not publish.is_empty():
			out["publish"] = publish
	if runtime.rumors != null:
		var rumor := runtime.rumors.export_state()
		if not rumor.is_empty():
			out["rumor"] = rumor
	var scheduler := {}
	if runtime.scheduler() != null:
		scheduler = runtime.scheduler().export_carry()
	var slice := runtime.slice_remainder_units()
	if slice != 0:
		var ordered := {}
		if scheduler.has("cache_refresh"):
			ordered["cache_refresh"] = scheduler["cache_refresh"]
		if scheduler.has("publish"):
			ordered["publish"] = scheduler["publish"]
		if scheduler.has("rumor"):
			ordered["rumor"] = scheduler["rumor"]
		ordered["slice"] = slice
		if scheduler.has("waits"):
			ordered["waits"] = scheduler["waits"]
		scheduler = ordered
	if not scheduler.is_empty():
		out["scheduler"] = scheduler
	return out


static func _import_flight(runtime: WyrdRuntime, data: Dictionary, report: WyrdLoadReport) -> void:
	if not data.has("flight"):
		runtime.set_slice_remainder(0)
		if runtime.scheduler() != null:
			runtime.scheduler().clear_carry()
			if _whole(data.get("schema_version", -1), -1) >= FLIGHT_SINCE_SCHEMA:
				runtime.scheduler().clear_dirty()
		if runtime.rumors != null:
			runtime.rumors.clear_flight()
		if runtime.publish != null:
			runtime.publish.clear()
		return
	var flight := _dict(data.get("flight", {}))
	var dropped := {}
	if runtime.rumors != null:
		for row in runtime.rumors.import_state(_dict(flight.get("rumor", {}))):
			var policy_id := str(row.get("policy", ""))
			var deed_id := str(row.get("deed", ""))
			dropped[deed_id] = true
			report.diagnostics.add(
				WyrdDiagnostic.E_SAVE_POLICY,
				WyrdRumor.missing_policy_message(policy_id, deed_id),
				"",
				1,
				1
			)
	if runtime.publish != null:
		runtime.publish.import_state(_dict(flight.get("publish", {})))
	var scheduler := _dict(flight.get("scheduler", {}))
	if not dropped.is_empty():
		scheduler = _without_rumor_deeds(scheduler, dropped)
	if runtime.scheduler() != null:
		runtime.scheduler().import_carry(scheduler)
	runtime.set_slice_remainder(_whole(scheduler.get("slice", 0), 0))


## Drops rumor tokens whose deed was refused. Other queues stay in order.
static func _without_rumor_deeds(scheduler: Dictionary, dropped: Dictionary) -> Dictionary:
	var raw: Variant = scheduler.get("rumor", [])
	if not (raw is Array):
		return scheduler
	var kept: Array = []
	for item in raw:
		var token := String(item)
		if dropped.has(_rumor_token_deed(token)):
			continue
		kept.append(token)
	var out := scheduler.duplicate()
	if kept.is_empty():
		out.erase("rumor")
	else:
		out["rumor"] = kept
	return out


static func _rumor_token_deed(token: String) -> String:
	var parts := token.split("\t")
	if parts.size() >= 2 and parts[0] == "reach":
		return parts[1]
	if parts.is_empty():
		return ""
	return parts[0]


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
