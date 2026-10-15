class_name WyrdContent
extends RefCounted

## Runtime index of one compiled pack. Built at load. Not a save document.
##
## @experimental
## Quests, scenes, and lines are the compiler's plain records, keyed by id.
## [member conditions] is every gating condition, in source order, with a
## parallel [member records] / [member sites] pair. [code]chance[/code] uses
## [code]<record>:<site>[/code]. [member manifest_hash] folds the pack id and
## each unit hash with [method WyrdHash.combine], paths sorted.

var pack_id: String = ""
var language_version: int = 1
var manifest_hash: int = 0
var schema: WyrdFactSchema
var events: Dictionary = {}
var quests: Dictionary = {}
var scenes: Dictionary = {}
var lines: Dictionary = {}
var files: Array = []
var conditions: Array[WyrdCompiledCondition] = []
var records: PackedStringArray = PackedStringArray()
var sites: PackedStringArray = PackedStringArray()
var deps: WyrdDepIndex
var _by_cond: Dictionary = {}


static func from_pack(pack: WyrdLinkedPack) -> WyrdContent:
	var content := WyrdContent.new()
	if pack == null:
		content.deps = WyrdDepIndex.new()
		return content
	content.pack_id = pack.pack_id
	content.language_version = pack.language_version
	content.schema = pack.schema
	content.events = pack.events.duplicate()
	content.manifest_hash = hash_pack(pack)
	for unit in pack.units:
		content.files.append({"hash": str(unit["hash"]), "path": str(unit["path"])})
		var file: WyrdFileDef = unit["file"]
		if file == null:
			continue
		for quest in file.quests:
			content.quests[quest.id] = quest
			content._add(quest.start_when, quest.id, "start")
			for slot in quest.slots:
				content._add(slot.cast_when, "%s.%s" % [quest.id, slot.name], "cast")
			for stage in quest.stages:
				content._stage(quest.id, stage)
		for scene in file.scenes:
			content.scenes[scene.id] = scene
			for item in scene.items:
				content._item(scene.id, item)
	content.deps = WyrdDepIndex.new()
	content.deps.build(content.conditions)
	return content


static func hash_pack(pack: WyrdLinkedPack) -> int:
	if pack == null:
		return 0
	var mixed := WyrdHash.of_string_name(StringName(pack.pack_id))
	var paths := PackedStringArray()
	var hashes := PackedStringArray()
	for unit in pack.units:
		paths.append(str(unit["path"]))
		hashes.append(str(unit["hash"]))
	var order: Array[int] = []
	for i in paths.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return paths[a] < paths[b])
	for i in order:
		mixed = WyrdHash.combine(mixed, _hex_to_int(hashes[i]))
	return mixed


func condition_at(index: int) -> Dictionary:
	if index < 0 or index >= conditions.size():
		return {}
	var reads: PackedStringArray = PackedStringArray()
	for read in conditions[index].reads:
		reads.append(String(read))
	return {"reads": reads, "record": records[index], "site": sites[index]}


func _stage(quest_id: String, stage: WyrdStageDef) -> void:
	if stage == null:
		return
	var prefix := "%s.%s" % [quest_id, stage.id]
	_add(stage.waits_until, prefix, "waits")
	for row in stage.transitions:
		var when: Variant = row.get("when", null)
		if when is WyrdCompiledCondition:
			_add(when, prefix, "transition." + str(row.get("target", "")))
	for journal in stage.journals:
		if not journal.line_id.is_empty():
			lines[journal.line_id] = journal
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant == null:
			continue
		if variant.condition != null:
			_add(variant.condition, "%s.%s" % [prefix, variant.slot], "variant." + String(variant.state))
		if variant.body != null:
			_stage(quest_id, variant.body)


func _item(scene_id: String, item: WyrdSceneItem) -> void:
	if item.line_def != null:
		var line := item.line_def
		if not line.line_id.is_empty():
			lines[line.line_id] = line
		_add(line.condition, line.line_id if not line.line_id.is_empty() else scene_id, "when")
	if item.choice != null:
		var choice := item.choice
		if not choice.line_id.is_empty():
			lines[choice.line_id] = choice
		var record := choice.line_id if not choice.line_id.is_empty() else scene_id
		_add(choice.condition, record, "choice")


func index_of(cond: WyrdCompiledCondition) -> int:
	if cond == null:
		return -1
	var key := cond.get_instance_id()
	if not _by_cond.has(key):
		return -1
	return int(_by_cond[key])


func _add(cond: WyrdCompiledCondition, record: String, site: String) -> void:
	if cond == null:
		return
	_by_cond[cond.get_instance_id()] = conditions.size()
	conditions.append(cond)
	records.append(record)
	sites.append(site)


static func _hex_to_int(hex: String) -> int:
	if hex.is_empty():
		return 0
	var value := 0
	for i in hex.length():
		var code := hex.unicode_at(i)
		var nibble := -1
		if code >= 48 and code <= 57:
			nibble = code - 48
		elif code >= 97 and code <= 102:
			nibble = code - 87
		elif code >= 65 and code <= 70:
			nibble = code - 55
		if nibble < 0:
			return WyrdHash.of_string_name(StringName(hex))
		value = (value << 4) | nibble
	return value
