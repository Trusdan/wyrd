class_name WyrdDebug
extends RefCounted

## On-demand inspector document. Not saved, and not rebuilt each frame.
##
## @experimental
## [method snapshot] reads the live runtime. An empty section list builds
## every section in [constant SECTIONS]. A named list builds only those
## sections. [param prefix] is applied while each section collects rows: a
## row is kept when its [code]key[/code] begins with that text, and a fact
## row is also kept when its [code]fact[/code] does. Kept rows are then
## sorted and paged. [param offset] and [param limit] page those rows.
## [code]limit[/code] of 0 returns the rest.
## One [code]debug_snapshot[/code] line is logged when tracing is on.

const SECTIONS: PackedStringArray = [
	"facts",
	"roles",
	"quests",
	"dirty",
	"deeds",
	"social",
	"precedence",
	"provenance",
]

var _runtime: WyrdRuntime


func bind(runtime: WyrdRuntime) -> void:
	_runtime = runtime


func snapshot(
	sections: PackedStringArray = PackedStringArray(),
	prefix: String = "",
	offset: int = 0,
	limit: int = 0
) -> Dictionary:
	if _runtime == null:
		push_error("Wyrd.debug.snapshot: runtime is not bound")
		return {}
	var chosen := _choose(sections)
	var page_offset := maxi(offset, 0)
	var page_limit := limit if limit > 0 else 0
	var names: Array = []
	var out := {
		"limit": page_limit,
		"offset": page_offset,
		"prefix": prefix,
	}
	var row_count := 0
	for name in chosen:
		var rows := _rows(String(name), prefix)
		var page := _page(rows, prefix, page_offset, page_limit, String(name) == "facts")
		out[String(name)] = page
		names.append(String(name))
		row_count += (page["rows"] as Array).size()
	out["sections"] = names
	_trace(sections.is_empty(), names, prefix, page_offset, page_limit, row_count)
	return out


func _choose(sections: PackedStringArray) -> PackedStringArray:
	var chosen := PackedStringArray()
	var seen := {}
	var source := SECTIONS if sections.is_empty() else sections
	for name in source:
		var text := String(name).strip_edges()
		if not SECTIONS.has(text):
			push_error("Wyrd.debug.snapshot: unknown section \"%s\"" % text)
			continue
		if seen.has(text):
			continue
		seen[text] = true
		chosen.append(text)
	return chosen


func _rows(section: String, prefix: String) -> Array:
	match section:
		"facts":
			return _facts(prefix)
		"roles":
			return _roles(prefix)
		"quests":
			return _quests(prefix)
		"dirty":
			return _dirty(prefix)
		"deeds":
			return _deeds(prefix)
		"social":
			return _social(prefix)
		"precedence":
			return _precedence(prefix)
		"provenance":
			return _provenance(prefix)
		_:
			return []


func _facts(prefix: String) -> Array:
	var exported := _runtime.facts.export_state()
	var deadlines := {}
	for item in exported.get("evidence", []):
		if not (item is Dictionary):
			continue
		var evidence: Dictionary = item
		var fact := str(evidence.get("key", ""))
		var until := int(evidence.get("until", -1))
		if fact.is_empty() or until < 0:
			continue
		if not deadlines.has(fact) or until < int(deadlines[fact]):
			deadlines[fact] = until
	var rows: Array = []
	var world: Dictionary = exported.get("world", {})
	var world_keys: Array = world.keys()
	world_keys.sort()
	for fact in world_keys:
		var fact_name := String(fact)
		if not _fact_kept("world", "", fact_name, prefix):
			continue
		rows.append(_fact_row("world", "", fact_name, world[fact], deadlines))
	for layer in ["known", "believed", "held"]:
		var owners: Dictionary = exported.get(layer, {})
		var owner_ids: Array = owners.keys()
		owner_ids.sort()
		for owner in owner_ids:
			var bag: Variant = owners[owner]
			if not (bag is Dictionary):
				continue
			var keys: Array = (bag as Dictionary).keys()
			keys.sort()
			for fact in keys:
				var fact_name := String(fact)
				var owner_name := String(owner)
				if not _fact_kept(layer, owner_name, fact_name, prefix):
					continue
				rows.append(_fact_row(layer, owner_name, fact_name, (bag as Dictionary)[fact], deadlines))
	return rows


func _fact_row(layer: String, owner: String, fact: String, value: Variant, deadlines: Dictionary) -> Dictionary:
	var key := "world/%s" % fact if layer == "world" else "%s/%s/%s" % [layer, owner, fact]
	var row := {
		"fact": fact,
		"key": key,
		"layer": layer,
		"owner": owner,
		"value": value,
	}
	if layer == "world" and deadlines.has(fact):
		row["until"] = int(deadlines[fact])
	return row


func _roles(prefix: String) -> Array:
	var exported := _runtime.roles.export_state()
	var bindings: Dictionary = exported.get("bindings", {})
	var defs: Dictionary = exported.get("defs", {})
	var ids: Array = []
	var seen := {}
	for role in bindings.keys():
		var name := String(role)
		if not seen.has(name):
			seen[name] = true
			ids.append(name)
	for role in defs.keys():
		var name := String(role)
		if not seen.has(name):
			seen[name] = true
			ids.append(name)
	ids.sort()
	var rows: Array = []
	for role in ids:
		var role_name := String(role)
		if not _text_matches(role_name, prefix):
			continue
		var binding: Dictionary = bindings.get(role, {})
		var spec: Dictionary = defs.get(role, {})
		var history: Array = []
		for item in binding.get("history", []):
			if item is Dictionary:
				history.append((item as Dictionary).duplicate(true))
		rows.append({
			"history": history,
			"holder": String(binding.get("holder", "")),
			"key": role_name,
			"since": int(binding.get("since", 0)),
			"status": String(binding.get("status", "")),
			"strategy": String(spec.get("strategy", "")),
		})
	return rows


func _quests(prefix: String) -> Array:
	var exported := _runtime.quests.export_state()
	var ids: Array = exported.keys()
	ids.sort()
	var rows: Array = []
	for quest_id in ids:
		var item: Variant = exported[quest_id]
		if not (item is Dictionary):
			continue
		var quest_name := String(quest_id)
		if not _text_matches(quest_name, prefix):
			continue
		var row: Dictionary = item
		var regions: Dictionary = {}
		var packed: Variant = row.get("regions", {})
		if packed is Dictionary:
			regions = (packed as Dictionary).duplicate(true)
		rows.append({
			"key": quest_name,
			"regions": regions,
			"stage": String(row.get("stage", "")),
			"status": String(row.get("status", "")),
			"variant": String(row.get("variant", "")),
			"waiting": String(row.get("waiting", "")),
		})
	return rows


func _dirty(prefix: String) -> Array:
	var content := _runtime.content()
	var rows: Array = []
	for index in _runtime.condition_count():
		if not _runtime.condition_dirty(index):
			continue
		var found := {}
		if content != null:
			found = content.condition_at(index)
		var record := str(found.get("record", ""))
		if not _text_matches(record, prefix):
			continue
		rows.append({
			"index": index,
			"key": record,
			"record": record,
			"site": str(found.get("site", "")),
		})
	return rows


func _deeds(prefix: String) -> Array:
	var rows: Array = []
	var filtering := not prefix.is_empty()
	for index in _runtime.deeds.size():
		if filtering:
			var key := "%s/%s/%s" % [
				String(_runtime.deeds.actor_at(index)),
				String(_runtime.deeds.verb_at(index)),
				String(_runtime.deeds.target_at(index)),
			]
			if not key.begins_with(prefix):
				continue
		var deed := _runtime.deeds.row_at(index)
		var actor := str(deed.get("actor", ""))
		var verb := str(deed.get("verb", ""))
		var target := str(deed.get("target", ""))
		var witnesses: Array = []
		for witness in deed.get("witnesses", []):
			witnesses.append(str(witness))
		rows.append({
			"actor": actor,
			"id": int(deed.get("id", 0)),
			"key": "%s/%s/%s" % [actor, verb, target],
			"magnitude": float(deed.get("magnitude", 0.0)),
			"memorable": bool(deed.get("memorable", false)),
			"place": str(deed.get("place", "")),
			"t": int(deed.get("t", 0)),
			"target": target,
			"verb": verb,
			"weight": _runtime.deeds.weight_at(index),
			"witnesses": witnesses,
		})
	return rows


func _social(prefix: String) -> Array:
	var exported := _runtime.social.export_state()
	var pairs := {}
	for item in exported.get("baselines", []):
		if item is Dictionary:
			var row: Dictionary = item
			_note_pair(pairs, str(row.get("source", "")), str(row.get("target", "")), prefix)
	for item in exported.get("kinds", []):
		if item is Dictionary:
			var row: Dictionary = item
			_note_pair(pairs, str(row.get("source", "")), str(row.get("target", "")), prefix)
	for index in _runtime.deeds.size():
		var actor := String(_runtime.deeds.actor_at(index))
		if actor.is_empty():
			continue
		_note_pair(pairs, String(_runtime.deeds.target_at(index)), actor, prefix)
		for witness in _runtime.deeds.witnesses_at(index):
			_note_pair(pairs, witness, actor, prefix)
	var names := _axis_names()
	var rows: Array = []
	for key in pairs.keys():
		var pair: Dictionary = pairs[key]
		var source := String(pair["source"])
		var target := String(pair["target"])
		var axes := {}
		for axis_name in names:
			axes[axis_name] = _runtime.social.axis(StringName(source), StringName(target), StringName(axis_name))
		rows.append({
			"axes": axes,
			"disposition": _runtime.social.disposition(StringName(source), StringName(target)),
			"key": "%s/%s" % [source, target],
			"source": source,
			"target": target,
		})
	return rows


func _precedence(prefix: String) -> Array:
	var agents := {}
	var facts := _runtime.facts.export_state()
	for layer in ["known", "believed"]:
		var owners: Variant = facts.get(layer, {})
		if owners is Dictionary:
			for owner in (owners as Dictionary).keys():
				_note_agent(agents, String(owner), prefix)
	var bindings: Dictionary = _runtime.roles.export_state().get("bindings", {})
	for role in bindings.keys():
		var binding: Variant = bindings[role]
		if binding is Dictionary:
			_note_agent(agents, String((binding as Dictionary).get("holder", "")), prefix)
	for index in _runtime.deeds.size():
		var actor := String(_runtime.deeds.actor_at(index))
		_note_agent(agents, actor, prefix)
		_note_agent(agents, String(_runtime.deeds.target_at(index)), prefix)
		for witness in _runtime.deeds.witnesses_at(index):
			_note_agent(agents, witness, prefix)
	var rows: Array = []
	for agent in agents.keys():
		var groups: Array = []
		for group in _runtime.group_precedence(StringName(String(agent))):
			groups.append(String(group))
		rows.append({"groups": groups, "key": String(agent)})
	return rows


func _provenance(prefix: String) -> Array:
	var exported := _runtime.effects.export_state()
	var keys: Array = exported.keys()
	keys.sort()
	var rows: Array = []
	for fact in keys:
		var item: Variant = exported[fact]
		if not (item is Dictionary):
			continue
		var fact_name := String(fact)
		if not _text_matches(fact_name, prefix):
			continue
		var row: Dictionary = item
		rows.append({
			"choice": String(row.get("choice", "")),
			"key": fact_name,
			"scene": String(row.get("scene", "")),
			"time": int(row.get("time", 0)),
		})
	return rows


func _page(rows: Array, prefix: String, offset: int, limit: int, also_fact: bool) -> Dictionary:
	var filtered: Array = []
	for item in rows:
		if item is Dictionary and _matches(item, prefix, also_fact):
			filtered.append(item)
	filtered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _before(a, b))
	var total := filtered.size()
	var start := mini(offset, total)
	var ending := total if limit <= 0 else mini(start + limit, total)
	var page: Array = []
	for index in range(start, ending):
		page.append(filtered[index])
	return {"limit": limit, "offset": offset, "rows": page, "total": total}


func _matches(row: Dictionary, prefix: String, also_fact: bool) -> bool:
	if _text_matches(str(row.get("key", "")), prefix):
		return true
	return also_fact and _text_matches(str(row.get("fact", "")), prefix)


func _text_matches(text: String, prefix: String) -> bool:
	return prefix.is_empty() or text.begins_with(prefix)


func _fact_kept(layer: String, owner: String, fact: String, prefix: String) -> bool:
	if prefix.is_empty():
		return true
	if fact.begins_with(prefix):
		return true
	var key := "world/%s" % fact if layer == "world" else "%s/%s/%s" % [layer, owner, fact]
	return key.begins_with(prefix)


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var left := str(a.get("key", ""))
	var right := str(b.get("key", ""))
	if left != right:
		return left < right
	if a.has("id") or b.has("id"):
		return int(a.get("id", 0)) < int(b.get("id", 0))
	if a.has("index") or b.has("index"):
		return int(a.get("index", 0)) < int(b.get("index", 0))
	return false


func _axis_names() -> Array:
	var names: Array = ["affinity"]
	var cfg := _runtime.config()
	if cfg != null:
		for axis_name in cfg.axis_names:
			var text := String(axis_name)
			if not names.has(text):
				names.append(text)
	names.sort()
	return names


func _note_pair(pairs: Dictionary, source: String, target: String, prefix: String) -> void:
	if source.is_empty() or target.is_empty():
		return
	var key := "%s/%s" % [source, target]
	if not _text_matches(key, prefix):
		return
	pairs[key] = {"source": source, "target": target}


func _note_agent(agents: Dictionary, agent: String, prefix: String) -> void:
	if agent.is_empty() or not _text_matches(agent, prefix):
		return
	agents[agent] = true


func _trace(all_sections: bool, names: Array, prefix: String, offset: int, limit: int, rows: int) -> void:
	var section_token := "*"
	if not all_sections:
		section_token = ",".join(names) if not names.is_empty() else "-"
	var prefix_token := prefix if not prefix.is_empty() else "-"
	var fields := {
		"key": prefix,
		"limit": limit,
		"offset": offset,
		"path": section_token,
		"prefix": prefix_token,
		"rows": rows,
		"sections": section_token,
	}
	var line := "wyrd debug snapshot sections=%s prefix=%s offset=%d limit=%d rows=%d" % [
		section_token, prefix_token, offset, limit, rows
	]
	_runtime.trace_debug_snapshot(fields, line)
