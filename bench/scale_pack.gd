class_name WyrdScalePack
extends RefCounted

## Seeded Gullhaven scale pack.
##
## @experimental
## [method write] fills a directory and returns the SHA-256 of its files.
## The same seed and profile always produce the same bytes. Nothing here is
## committed: callers pass a temp directory. The hash covers every file in
## sorted path order. Each entry is the UTF-8 path, a zero byte, the file
## length as 8 big-endian bytes, then the file bytes.

const _HEADER_NOTE := "// [EXAMPLE CONTENT] Gullhaven scale pack. An invented fishing village, not a host game."


static func write(dir: String, profile_name: String) -> String:
	var counts := WyrdPerfScale.profile(profile_name)
	if counts.is_empty():
		push_error("scale pack: unknown profile %s" % profile_name)
		return ""
	var story_dir := storylets_root(dir)
	remove_dir(dir)
	remove_dir(story_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.make_dir_recursive_absolute(story_dir)
	_store(dir.path_join("facts.wyrd"), _facts(counts))
	_store(dir.path_join("roles.wyrd"), _roles(counts))
	_store(dir.path_join("quests.wyrd"), _quests(counts))
	_store(dir.path_join("deeds.tsv"), _deeds(counts))
	_store(dir.path_join("pack.txt"), _pack_text(profile_name, counts))
	_store(story_dir.path_join("scale.wyrd"), _storylets(counts))
	return hash_release(dir)


## Sibling of the quest pack. [code]compile.strict[/code] does not walk it.
static func storylets_root(pack_dir: String) -> String:
	return "%s_storylets" % pack_dir


static func hash_release(pack_dir: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	_hash_tree(ctx, pack_dir, "")
	_hash_tree(ctx, storylets_root(pack_dir), "storylets/")
	return ctx.finish().hex_encode()


## Topic-0, [constant WyrdPerfScale.QUERY_SPEAKER] winner. Slot 1 of that topic.
static func queried_winner(topics: int) -> String:
	return _storylet_id(topics)


static func hash_dir(dir: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	_hash_tree(ctx, dir, "")
	return ctx.finish().hex_encode()


static func _hash_tree(ctx: HashingContext, dir: String, prefix: String) -> void:
	var names := _file_names(dir)
	names.sort()
	for name in names:
		ctx.update((prefix + String(name)).to_utf8_buffer())
		ctx.update(PackedByteArray([0]))
		var body := FileAccess.get_file_as_bytes(dir.path_join(String(name)))
		ctx.update(_u64(body.size()))
		ctx.update(body)


static func read_pack(dir: String) -> Dictionary:
	var text := _read(dir.path_join("pack.txt"))
	var out := {}
	for line in text.split("\n"):
		var row := line.strip_edges()
		if row.is_empty() or row.begins_with("#"):
			continue
		var parts := row.split("=", false, 1)
		if parts.size() == 2:
			out[parts[0]] = parts[1]
	return out


static func load_deeds(dir: String) -> Dictionary:
	var rows: Array = []
	var next_id := 1
	for line in _read(dir.path_join("deeds.tsv")).split("\n"):
		var row := line.strip_edges()
		if row.is_empty() or row.begins_with("#"):
			continue
		var parts := row.split("\t")
		if parts.size() < 11:
			continue
		var tags: Array = []
		if not parts[9].is_empty():
			for tag in parts[9].split(","):
				tags.append(tag)
		var witnesses: Array = []
		var perception: Array = []
		if not parts[10].is_empty():
			for item in parts[10].split(","):
				var pair := item.split("=")
				witnesses.append(pair[0])
				perception.append(pair[1] if pair.size() > 1 else "saw")
		var id := int(parts[0])
		next_id = maxi(next_id, id + 1)
		rows.append({
			"actor": parts[1],
			"id": id,
			"magnitude": float(parts[6]),
			"memorable": parts[8] == "1",
			"perception": perception,
			"place": parts[4],
			"t": int(parts[5]),
			"tags": tags,
			"target": parts[3],
			"verb": parts[2],
			"visibility": parts[7],
			"witnesses": witnesses,
		})
	return {"next": next_id, "rows": rows}


static func remove_dir(path: String) -> void:
	if path.is_empty() or not DirAccess.dir_exists_absolute(path):
		return
	var listing := DirAccess.open(path)
	if listing == null:
		return
	listing.list_dir_begin()
	var name := listing.get_next()
	while name != "":
		if name != "." and name != "..":
			var child := path.path_join(name)
			if listing.current_is_dir():
				remove_dir(child)
			else:
				listing.remove(name)
		name = listing.get_next()
	listing.list_dir_end()
	DirAccess.remove_absolute(path)


static func _facts(counts: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(_banner())
	lines.append("facts")
	var total := int(counts["facts"])
	for index in total:
		lines.append(
			"  %s : int stored doc: \"Scale fact %05d.\"" % [_fact(index), index]
		)
	lines.append("")
	return "\n".join(lines)


static func _roles(counts: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(_banner())
	var total := int(counts["npcs"])
	for index in total:
		var id := _npc(index)
		lines.append("role %s" % id)
		lines.append("  default_holder: %s" % id)
		lines.append("  succession: none")
		lines.append("  vacancy: hold")
		lines.append("")
	return "\n".join(lines)


static func _quests(counts: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(_banner())
	var quests := int(counts["quests"])
	var facts := int(counts["facts"])
	for quest_index in quests:
		var span := _span(facts, quests, quest_index)
		lines.append("quest %s \"Scale quest %04d\"" % [_quest(quest_index), quest_index])
		lines.append("  start when %s == 1" % _fact(span.x))
		for offset in span.y:
			var sid := "s%02d" % offset
			lines.append("  stage %s" % sid)
			lines.append("    waits_until %s == 1" % _fact(span.x + offset))
			lines.append("    ~ set %s = 0" % _fact(span.x + offset))
			if offset + 1 < span.y:
				lines.append("    -> s%02d" % (offset + 1))
		lines.append("")
	return "\n".join(lines)


static func _deeds(counts: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("# id actor verb target place minute magnitude visibility memorable tags witnesses")
	var total := int(counts["deeds"])
	var npcs := int(counts["npcs"])
	var mergeable := (total * 4) / 5
	var rng := WyrdRng.new(WyrdPerfScale.SEED, WyrdRng.stream_id(&"scale_deeds"))
	for index in total:
		var verb_i := rng.randi_bounded(WyrdPerfScale.VERBS.size())
		var tag_roll := rng.randi_bounded(2)
		var id := index + 1
		var actor := ""
		var verb := ""
		var target := "player"
		var minute := 0
		var tags := "toll"
		var witness := ""
		if index < mergeable:
			var bucket := index % WyrdPerfScale.MERGE_BUCKETS
			actor = _npc(bucket % npcs)
			verb = WyrdPerfScale.VERBS[bucket % WyrdPerfScale.VERBS.size()]
			minute = bucket
			witness = "%s=saw" % _npc((bucket + 1) % npcs)
		else:
			actor = _npc(index % npcs)
			verb = WyrdPerfScale.VERBS[verb_i]
			target = _npc((index + 3) % npcs)
			minute = 1000 + index
			tags = "toll" if tag_roll == 0 else ""
			witness = "%s=heard" % _npc((index + 1) % npcs)
		lines.append(
			"%d\t%s\t%s\t%s\tgullhaven\t%d\t1\tpublic\t0\t%s\t%s"
			% [id, actor, verb, target, minute, tags, witness]
		)
	lines.append("")
	return "\n".join(lines)


static func _pack_text(profile_name: String, counts: Dictionary) -> String:
	var lines := PackedStringArray([
		"deeds=%d" % int(counts["deeds"]),
		"facts=%d" % int(counts["facts"]),
		"npcs=%d" % int(counts["npcs"]),
		"profile=%s" % profile_name,
		"quests=%d" % int(counts["quests"]),
		"seed=%d" % WyrdPerfScale.SEED,
		"speakers=%d" % int(counts["speakers"]),
		"storylets=%d" % int(counts["storylets"]),
		"topics=%d" % int(counts["topics"]),
	])
	return "\n".join(lines) + "\n"


static func _banner() -> String:
	return "%s\n// seed: %d\nlanguage 1\n" % [_HEADER_NOTE, WyrdPerfScale.SEED]


static func _span(fact_count: int, quest_count: int, quest_index: int) -> Vector2i:
	var base := fact_count / quest_count
	var extra := fact_count % quest_count
	var start := quest_index * base + mini(quest_index, extra)
	var count := base + (1 if quest_index < extra else 0)
	return Vector2i(start, count)


static func _fact(index: int) -> String:
	return "harbor.scale_%05d" % index


static func _npc(index: int) -> String:
	return "dock_hand_%03d" % index


static func _quest(index: int) -> String:
	return "scale_q%04d" % index


## One [code]any[/code] line per topic, then named speakers.
## The first named pass is the specific winner. Later passes share a speaker
## and differ by [code]harbor.line_on == slot[/code], which the tie lint excludes.
static func _storylets(counts: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(_banner())
	lines.append("facts")
	lines.append("  harbor.line_on : int stored doc: \"Scale line switch.\"")
	lines.append("quest scale_line \"Scale Line\"")
	lines.append("  start when false")
	lines.append("  stage note")
	lines.append("    ~ set harbor.line_on = 0")
	lines.append("")
	var total := int(counts["storylets"])
	var topics := int(counts["topics"])
	var speakers := int(counts["speakers"])
	for index in total:
		var topic := index % topics
		var slot := int(index / float(topics))
		var speaker := "any"
		var priority := 1
		var weight := 1
		var when := ""
		if slot > 0:
			var speaker_index := (slot - 1) % speakers
			var variant := int((slot - 1) / float(speakers))
			speaker = _npc(speaker_index)
			if variant == 0:
				priority = 2
				weight = 2
			else:
				priority = 0
				when = "harbor.line_on == %d" % slot
		lines.append("storylet %s" % _storylet_id(index))
		lines.append("  scope: topic %s" % _topic(topic))
		lines.append("  speaker: %s" % speaker)
		lines.append("  priority: %d" % priority)
		lines.append("  weight: %d" % weight)
		if not when.is_empty():
			lines.append("  when: %s" % when)
		lines.append("  - The harbor keeps this scale line. #line:%s" % _line_id(index))
		lines.append("")
	return "\n".join(lines)


static func _storylet_id(index: int) -> String:
	return "harbor.line_%05d" % index


static func _line_id(index: int) -> String:
	return "hl%05d" % index


static func _topic(index: int) -> String:
	return "rumor.scale_%02d" % index


static func _file_names(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var listing := DirAccess.open(dir)
	if listing == null:
		return out
	listing.list_dir_begin()
	var name := listing.get_next()
	while name != "":
		if name != "." and name != ".." and not listing.current_is_dir():
			out.append(name)
		name = listing.get_next()
	listing.list_dir_end()
	return out


static func _store(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("scale pack could not write %s" % path)
		return
	file.store_string(text)
	file.close()


static func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


static func _u64(value: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(8)
	var bits := value
	for shift in 8:
		out[7 - shift] = bits & 0xFF
		bits >>= 8
	return out
