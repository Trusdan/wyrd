class_name WyrdSaveMigrate
extends RefCounted

## Rewrites saved ids through a pack's resolved [code]was:[/code] tables.
##
## @experimental
## [method apply_aliases] is pure. It does not change [param doc] or
## [param aliases], and it does not read a runtime, a config, a clock, or an
## RNG. The same inputs always return the same document, rows, and diagnostics.
## Empty tables return [param doc] itself and no rows. A second call on the
## returned document adds no rows: chains are already resolved, so one lookup
## is the final id.
##
## The return value is [code]doc[/code] (a rewritten copy, or [param doc] when
## nothing changed), [code]rows[/code], and [code]diagnostics[/code]. Each row
## matches [method WyrdLoadReport.add_row]: [code]kind[/code] is [code]alias[/code],
## [code]id[/code] is [code]stage:<quest row id>[/code], [code]role:<old>[/code],
## [code]document:<old>[/code], or [code]verb:<old>[/code], [code]from[/code] is
## the old id, and [code]to[/code] is the final id. A rewrite row has an empty
## [code]code[/code]. A dropped old id has [code]W_SAVE_ALIAS[/code].
## [code]count[/code] is how many saved entries were rewritten or dropped.
## Each diagnostic is [code]code[/code], [code]message[/code], and
## [code]severity[/code] ([code]warning[/code]).


static func apply_aliases(doc: Dictionary, aliases: Dictionary) -> Dictionary:
	if not _has_table(aliases):
		return _none(doc)
	var copy: Dictionary = doc.duplicate(true)
	var rewrites: Dictionary = {}
	var drops: Dictionary = {}
	_rewrite_stages(copy, _kind(aliases, "stage"), rewrites)
	_rewrite_roles(copy, _kind(aliases, "role"), rewrites, drops)
	_rewrite_verbs(copy, _kind(aliases, "verb"), rewrites)
	_rewrite_documents(copy, _kind(aliases, "document"), rewrites, drops)
	if rewrites.is_empty() and drops.is_empty():
		return _none(doc)
	return {
		"diagnostics": _diagnostics(drops),
		"doc": copy,
		"rows": _rows(rewrites, drops),
	}


static func _none(doc: Dictionary) -> Dictionary:
	return {"diagnostics": [], "doc": doc, "rows": []}


static func _has_table(aliases: Dictionary) -> bool:
	for kind in ["document", "role", "stage", "verb"]:
		var table: Variant = aliases.get(kind, {})
		if table is Dictionary and not (table as Dictionary).is_empty():
			return true
	return false


static func _kind(aliases: Dictionary, kind: String) -> Dictionary:
	var table: Variant = aliases.get(kind, {})
	if table is Dictionary:
		return table
	return {}


static func _mapped(table: Dictionary, old: String) -> String:
	if old.is_empty() or not table.has(old):
		return ""
	var new_id := String(table[old])
	if new_id.is_empty() or new_id == old:
		return ""
	return new_id


static func _subject(kind: String, old: String, quest_id: String = "") -> String:
	if kind == "stage":
		return "stage:%s" % quest_id
	return "%s:%s" % [kind, old]


static func _bump(bag: Dictionary, subject: String, kind: String, old: String, new_id: String) -> void:
	if not bag.has(subject):
		bag[subject] = {"count": 0, "from": old, "kind": kind, "to": new_id}
	var row: Dictionary = bag[subject]
	row["count"] = int(row["count"]) + 1


static func _stage_scope(quest_id: String, row: Dictionary) -> String:
	var named := str(row.get("template", ""))
	if named != "":
		return named
	var hash := quest_id.find("#")
	if hash > 0:
		return quest_id.substr(0, hash)
	return quest_id


static func _rewrite_stages(doc: Dictionary, tables: Dictionary, rewrites: Dictionary) -> void:
	if tables.is_empty():
		return
	var quests: Variant = doc.get("quests", {})
	if not (quests is Dictionary):
		return
	var block: Dictionary = quests
	var ids: Array = block.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	for quest_id in ids:
		var item: Variant = block[quest_id]
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var scope := _stage_scope(String(quest_id), row)
		var found: Variant = tables.get(scope, {})
		if not (found is Dictionary):
			continue
		var old := str(row.get("stage", ""))
		var new_id := _mapped(found, old)
		if new_id.is_empty():
			continue
		row["stage"] = new_id
		_bump(rewrites, _subject("stage", old, String(quest_id)), "stage", old, new_id)


static func _rewrite_roles(doc: Dictionary, table: Dictionary, rewrites: Dictionary, drops: Dictionary) -> void:
	if table.is_empty():
		return
	var roles: Variant = doc.get("roles", {})
	if not (roles is Dictionary):
		return
	var block: Dictionary = roles
	for name in ["bindings", "defs", "pending", "told"]:
		var bag: Variant = block.get(name, {})
		if bag is Dictionary:
			_remap_map(bag, table, rewrites, drops)
	var abolished: Variant = block.get("abolished", [])
	if abolished is Array:
		block["abolished"] = _remap_list(abolished, table, rewrites, drops)


static func _remap_map(bag: Dictionary, table: Dictionary, rewrites: Dictionary, drops: Dictionary) -> void:
	var names: Array = bag.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var original: Dictionary = {}
	for name in names:
		original[String(name)] = true
	var placed: Dictionary = {}
	for name in names:
		var old := String(name)
		var new_id := _mapped(table, old)
		if new_id.is_empty():
			continue
		var subject := _subject("role", old)
		if original.has(new_id) or placed.has(new_id):
			bag.erase(name)
			_bump(drops, subject, "role", old, new_id)
			continue
		bag[new_id] = bag[name]
		bag.erase(name)
		placed[new_id] = true
		_bump(rewrites, subject, "role", old, new_id)


static func _remap_list(items: Array, table: Dictionary, rewrites: Dictionary, drops: Dictionary) -> Array:
	var original: Dictionary = {}
	for item in items:
		original[str(item)] = true
	var placed: Dictionary = {}
	var out: Array = []
	for item in items:
		var old := str(item)
		var new_id := _mapped(table, old)
		if new_id.is_empty():
			out.append(item)
			continue
		var subject := _subject("role", old)
		if original.has(new_id) or placed.has(new_id):
			_bump(drops, subject, "role", old, new_id)
			continue
		out.append(new_id)
		placed[new_id] = true
		_bump(rewrites, subject, "role", old, new_id)
	return out


static func _rewrite_verbs(doc: Dictionary, table: Dictionary, rewrites: Dictionary) -> void:
	if table.is_empty():
		return
	var deeds: Variant = doc.get("deeds", {})
	if not (deeds is Dictionary):
		return
	var rows: Variant = (deeds as Dictionary).get("rows", [])
	if not (rows is Array):
		return
	for item in rows:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		var old := str(row.get("verb", ""))
		var new_id := _mapped(table, old)
		if new_id.is_empty():
			continue
		row["verb"] = new_id
		_bump(rewrites, _subject("verb", old), "verb", old, new_id)


static func _rewrite_documents(doc: Dictionary, table: Dictionary, rewrites: Dictionary, drops: Dictionary) -> void:
	if table.is_empty():
		return
	var documents: Variant = doc.get("documents", {})
	if not (documents is Dictionary):
		return
	var block: Dictionary = documents
	if block.get("read") is Array:
		block["read"] = _remap_doc_rows(block["read"], table, "reader", rewrites, drops)
	if block.get("copies") is Array:
		block["copies"] = _remap_doc_rows(block["copies"], table, "copy", rewrites, drops)


static func _remap_doc_rows(items: Array, table: Dictionary, pair_field: String, rewrites: Dictionary, drops: Dictionary) -> Array:
	var original: Dictionary = {}
	for item in items:
		if item is Dictionary:
			var prior: Dictionary = item
			original[_pair(str(prior.get(pair_field, "")), str(prior.get("doc", "")))] = true
	var placed: Dictionary = {}
	var out: Array = []
	for item in items:
		if not (item is Dictionary):
			out.append(item)
			continue
		var row: Dictionary = item
		var old := str(row.get("doc", ""))
		var new_id := _mapped(table, old)
		if new_id.is_empty():
			out.append(row)
			continue
		var dest := _pair(str(row.get(pair_field, "")), new_id)
		var subject := _subject("document", old)
		if original.has(dest) or placed.has(dest):
			_bump(drops, subject, "document", old, new_id)
			continue
		row["doc"] = new_id
		placed[dest] = true
		out.append(row)
		_bump(rewrites, subject, "document", old, new_id)
	return out


static func _pair(left: String, right: String) -> String:
	return "%s\t%s" % [left, right]


static func _rows(rewrites: Dictionary, drops: Dictionary) -> Array:
	var rows: Array = []
	for subject in rewrites.keys():
		rows.append(_row(rewrites[subject], String(subject), ""))
	for subject in drops.keys():
		rows.append(_row(drops[subject], String(subject), String(WyrdDiagnostic.W_SAVE_ALIAS)))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var id_a := String(a.get("id", ""))
		var id_b := String(b.get("id", ""))
		if id_a != id_b:
			return id_a < id_b
		return String(a.get("code", "")) < String(b.get("code", ""))
	)
	return rows


static func _row(body: Dictionary, subject: String, code: String) -> Dictionary:
	return {
		"code": code,
		"count": int(body.get("count", 0)),
		"from": String(body.get("from", "")),
		"id": subject,
		"kind": "alias",
		"to": String(body.get("to", "")),
	}


static func _diagnostics(drops: Dictionary) -> Array:
	var notes: Array = []
	var subjects: Array = drops.keys()
	subjects.sort()
	for subject in subjects:
		var body: Dictionary = drops[subject]
		notes.append({
			"code": String(WyrdDiagnostic.W_SAVE_ALIAS),
			"message": "saved %s \"%s\" was dropped because \"%s\" is also saved" % [String(body.get("kind", "")), String(body.get("from", "")), String(body.get("to", ""))],
			"severity": "warning",
		})
	return notes
