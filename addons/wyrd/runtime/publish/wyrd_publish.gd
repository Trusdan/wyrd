class_name WyrdPublish
extends RefCounted

## Periodic issues for compiled documents.
##
## @experimental
## [method enqueue_due] pushes one [code]publish[/code] token per missed issue,
## oldest first, up to [member WyrdConfig.publish_catchup_max]. One token is one
## frozen issue. The handler builds it. Issues past the cap are numbered and
## written as [code]skip[/code] lines in the document fact, so they are not
## published later. The in-memory counter and the queued tokens are not saved.
## [method deeds_known_to] reads the witness index and the believer index.
## A [code]saw[/code] witness counts as [code]known:[/code]. [code]heard[/code],
## [code]inferred[/code], and a rumor believer count as [code]believed:[/code].

var facts: WyrdFactStore
var deeds: WyrdDeedLog
var config_of: Callable = Callable()
var now_of: Callable = Callable()
var members_of: Callable = Callable()
var content_of: Callable = Callable()
var eval_of: Callable = Callable()
var trace_of: Callable = Callable()
var enqueue_of: Callable = Callable()

var _covered: Dictionary = {}
var _memory_n: Dictionary = {}
var _queued: Dictionary = {}


func clear() -> void:
	_covered.clear()
	_memory_n.clear()
	_queued.clear()


## Deed rows any current member witnessed, or believes through a rumor, at or
## after [param since]. A witness uses the deed minute. A believer uses the
## adoption minute. [param filter] empty keeps every verb. Otherwise it is the
## verb. Rows are unique by deed id and sorted by that id. [code]t[/code] is
## the earliest qualifying minute. [code]mode[/code] is [code]known[/code] when
## any included member saw the deed, and [code]believed[/code] otherwise.
## [code]knowers[/code] lists those members once.
func deeds_known_to(group: StringName, since: int, filter: StringName = &"") -> Array:
	var rows: Array = []
	if deeds == null or group == &"":
		return rows
	var start := since if since > 0 else 0
	var verb := String(filter)
	var seen := {}
	for member in _members(String(group)):
		var who := String(member)
		_collect_witnesses(seen, who, start, verb)
		_collect_beliefs(seen, who, start, verb)
	var order: Array = seen.keys()
	order.sort()
	for deed_id in order:
		var entry: Dictionary = seen[deed_id]
		entry.erase("_seen")
		rows.append(entry)
	return rows


## Queues due issues that are not already frozen, skipped, or already queued.
## A visit takes at most the catch-up cap, oldest first. The rest are numbered
## and stored as skip lines in the document fact. The cap is per document.
func enqueue_due() -> void:
	var content := _content()
	if content == null or not enqueue_of.is_valid():
		return
	var now := _now()
	var cap := _cap()
	var ids: Array = content.documents.keys()
	ids.sort()
	for id in ids:
		_enqueue_doc(content.documents[id] as WyrdDocumentDef, now, cap)


## Builds the frozen issue named by an [code]issue[/code] token.
## Other tokens are ignored. The copy is written when the unit runs.
func issue(token: String) -> void:
	if not token.begins_with("issue\t"):
		return
	var parts := token.split("\t")
	if parts.size() != 4:
		return
	var doc := _doc(parts[1])
	if doc == null:
		return
	var number := int(parts[2])
	var due := int(parts[3])
	_queued.erase("%s\t%d" % [doc.id, due])
	var since := due - doc.period_minutes
	if since < 0:
		since = 0
	var window: Array = []
	for row in deeds_known_to(StringName(doc.group), since, StringName(doc.verb_filter)):
		if int(row["t"]) < due:
			window.append(row)
	var claim := _claim(doc, _members(doc.group))
	var slant := _slant(doc)
	if not slant.is_empty():
		claim = {"source": "slant", "value": slant}
	var ids := PackedStringArray()
	for row in window:
		ids.append(str(int(row["id"])))
	var copy_id := "%s#%d" % [doc.id, number]
	var line := "%s due=%d deeds=%d ids=%s claim=%s source=%s" % [
		copy_id,
		due,
		window.size(),
		",".join(ids),
		str(claim["value"]),
		str(claim["source"]),
	]
	_write(doc, line)
	if not trace_of.is_valid():
		return
	trace_of.call({
		"deeds": window.size(),
		"document": doc.id,
		"issue": copy_id,
		"key": copy_id,
		"path": doc.id,
		"who": doc.group,
	})


func _enqueue_doc(doc: WyrdDocumentDef, now: int, cap: int) -> void:
	if doc == null or doc.period_minutes <= 0:
		return
	var missed := _missed(doc, now)
	var take := missed.size()
	if cap < take:
		take = cap
	var number := int(_published(doc)["n"])
	for index in missed.size():
		number += 1
		var due := int(missed[index])
		_memory_n[doc.id] = number
		if index < take:
			_queued["%s\t%d" % [doc.id, due]] = true
			enqueue_of.call("issue\t%s\t%d\t%d" % [doc.id, number, due])
		else:
			_write(doc, "skip %s#%d due=%d" % [doc.id, number, due])
	_covered[doc.id] = now


func _missed(doc: WyrdDocumentDef, now: int) -> Array:
	var out: Array = []
	if now < doc.delay_minutes or doc.period_minutes <= 0:
		return out
	var due := doc.delay_minutes
	var covered := int(_covered.get(doc.id, -1))
	if covered >= doc.delay_minutes:
		var steps := _div_floor(covered - doc.delay_minutes, doc.period_minutes) + 1
		due = doc.delay_minutes + steps * doc.period_minutes
	var issued: Dictionary = _published(doc)["dues"]
	var guard := 0
	while due <= now and guard < 100000:
		guard += 1
		var key := "%s\t%d" % [doc.id, due]
		if not issued.has(due) and not _queued.has(key):
			out.append(due)
		due += doc.period_minutes
	return out


func _published(doc: WyrdDocumentDef) -> Dictionary:
	var number := int(_memory_n.get(doc.id, 0))
	var dues := {}
	var prefix := "%s#" % doc.id
	for raw in _fact_text(doc).split("\n"):
		var line := raw.strip_edges()
		if line.is_empty():
			continue
		var parts := line.split(" ")
		var head := parts[0]
		var copy := ""
		if head == "skip":
			if parts.size() < 2:
				continue
			copy = parts[1]
		elif head.begins_with(prefix):
			copy = head
		if not copy.begins_with(prefix):
			continue
		var num_text := copy.substr(prefix.length())
		if not num_text.is_valid_int():
			continue
		var found := int(num_text)
		if found > number:
			number = found
		var due := _field(line, "due")
		if due >= 0:
			dues[due] = true
	return {"dues": dues, "n": number}


func _claim(doc: WyrdDocumentDef, members: PackedStringArray) -> Dictionary:
	if doc.claim_key.is_empty() or facts == null:
		return {"source": "none", "value": ""}
	var key := StringName(doc.claim_key)
	var names: Array = []
	for member in members:
		names.append(String(member))
	names.sort()
	for who in names:
		var believed: Variant = facts.get_in(key, StringName("believed/%s" % who))
		if believed != null:
			return {"source": "belief", "value": String(believed)}
	for who in names:
		var known: Variant = facts.get_in(key, StringName("known/%s" % who))
		if known != null:
			return {"source": "known", "value": String(known)}
	var world: Variant = facts.get_in(key, &"world")
	if world != null:
		return {"source": "world", "value": String(world)}
	return {"source": "none", "value": ""}


func _slant(doc: WyrdDocumentDef) -> String:
	if not eval_of.is_valid():
		return ""
	for fragment in doc.fragments:
		var cond: WyrdCompiledCondition = fragment.get("when") as WyrdCompiledCondition
		if cond != null and bool(eval_of.call(cond)):
			return String(fragment.get("slant", ""))
	return ""


func _write(doc: WyrdDocumentDef, line: String) -> void:
	if doc.fact_key.is_empty() or facts == null:
		return
	var key := StringName(doc.fact_key)
	var prior: Variant = facts.get_in(key, &"world")
	var text := ""
	if prior != null:
		text = String(prior)
	if not text.is_empty():
		text += "\n"
	text += line
	if not facts.set_in(key, text, &"world"):
		push_error("WyrdPublish.issue: could not store %s" % line.split(" ")[0])


func _fact_text(doc: WyrdDocumentDef) -> String:
	if doc.fact_key.is_empty() or facts == null:
		return ""
	var prior: Variant = facts.get_in(StringName(doc.fact_key), &"world")
	if prior == null:
		return ""
	return String(prior)


func _doc(id: String) -> WyrdDocumentDef:
	var content := _content()
	if content == null or not content.documents.has(id):
		return null
	return content.documents[id] as WyrdDocumentDef


func _content() -> WyrdContent:
	if not content_of.is_valid():
		return null
	var raw: Variant = content_of.call()
	if raw is WyrdContent:
		return raw as WyrdContent
	return null


func _members(group: String) -> PackedStringArray:
	var rows := PackedStringArray()
	if group.is_empty() or not members_of.is_valid():
		return rows
	var raw: Variant = members_of.call(StringName(group))
	if raw is PackedStringArray:
		rows = (raw as PackedStringArray).duplicate()
	elif raw is Array:
		for item in raw:
			rows.append(String(item))
	rows.sort()
	return rows


func _collect_witnesses(seen: Dictionary, who: String, start: int, verb: String) -> void:
	for index in deeds.witness_indexes(StringName(who)):
		var row := deeds.row_at(int(index))
		var at := int(row["t"])
		if at < start:
			continue
		if not verb.is_empty() and String(row["verb"]) != verb:
			continue
		var layer := "known" if _witness_mode(row, who) == "saw" else "believed"
		_include(seen, row, who, layer, at)


func _collect_beliefs(seen: Dictionary, who: String, start: int, verb: String) -> void:
	for hit in deeds.believer_deeds(StringName(who)):
		var at := int(hit["t"])
		if at < start:
			continue
		var index := deeds.index_of(int(hit["id"]))
		if index < 0:
			continue
		var row := deeds.row_at(index)
		if not verb.is_empty() and String(row["verb"]) != verb:
			continue
		_include(seen, row, who, "believed", at)


func _include(seen: Dictionary, row: Dictionary, who: String, layer: String, at: int) -> void:
	var deed_id := int(row["id"])
	if not seen.has(deed_id):
		seen[deed_id] = {
			"actor": String(row["actor"]),
			"id": deed_id,
			"knowers": [],
			"mode": "believed",
			"place": String(row["place"]),
			"t": at,
			"verb": String(row["verb"]),
			"_seen": {},
		}
	var entry: Dictionary = seen[deed_id]
	if at < int(entry["t"]):
		entry["t"] = at
	var known: Dictionary = entry["_seen"]
	if known.has(who):
		if layer == "known":
			_mark_known(entry, who)
		seen[deed_id] = entry
		return
	known[who] = true
	entry["_seen"] = known
	var knowers: Array = entry["knowers"]
	knowers.append({"layer": layer, "who": who})
	entry["knowers"] = knowers
	if layer == "known":
		entry["mode"] = "known"
	seen[deed_id] = entry


func _mark_known(entry: Dictionary, who: String) -> void:
	var knowers: Array = entry["knowers"]
	for item in knowers:
		if item is Dictionary and String(item.get("who", "")) == who:
			item["layer"] = "known"
	entry["knowers"] = knowers
	entry["mode"] = "known"


func _witness_mode(row: Dictionary, who: String) -> String:
	var witnesses: PackedStringArray = row["witnesses"]
	var modes: PackedStringArray = row["perception"]
	for index in witnesses.size():
		if witnesses[index] == who:
			if index < modes.size():
				return String(modes[index])
			return "saw"
	return ""


func _now() -> int:
	if not now_of.is_valid():
		return 0
	return maxi(int(now_of.call()), 0)


func _cap() -> int:
	if not config_of.is_valid():
		return 3
	var config: Variant = config_of.call()
	if config is WyrdConfig:
		return maxi((config as WyrdConfig).publish_catchup_max, 0)
	return 3


func _field(line: String, name: String) -> int:
	var needle := "%s=" % name
	for part in line.split(" "):
		if not part.begins_with(needle):
			continue
		var rest := part.substr(needle.length())
		if rest.is_valid_int():
			return int(rest)
	return -1


static func _div_floor(numer: int, denom: int) -> int:
	if denom == 0:
		return 0
	return int(floor(float(numer) / float(denom)))
