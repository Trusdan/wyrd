class_name WyrdGenerator
extends RefCounted

## Unsaved story-pressure queue.
##
## @experimental
## [method offer] appends a host offer, or replaces tier and payload when the
## same source and key are already queued. Deed hooks use [method queue_deed].
## The queue is not saved. [member generate_handler] is unset until a later
## pass picks a template.

var generate_handler: Callable = Callable()
var config_of: Callable = Callable()
var trace_of: Callable = Callable()

var _offers: Array[Dictionary] = []


func offer(source: StringName, key: String, tier: StringName = &"", payload: Dictionary = {}) -> bool:
	if source == &"" or key.is_empty():
		push_error("Wyrd.generator.offer: source and key are required")
		return false
	if tier != &"" and tier_rank(String(tier)) < 0:
		push_error("Wyrd.generator.offer: unknown pressure tier \"%s\"" % String(tier))
		return false
	if not _payload_ok(payload):
		push_error("Wyrd.generator.offer: payload values must be string, number, or bool")
		return false
	_enqueue(source, key, tier, _copy_payload(payload), "host", "")
	return true


## Queues one deed-hook offer. [param deed_id] is the deed's id text.
func queue_deed(template_id: String, deed_id: String, payload: Dictionary) -> void:
	if template_id.is_empty() or deed_id.is_empty():
		return
	_enqueue(&"deed", "%s:%s" % [template_id, deed_id], &"", _copy_payload(payload), "deed", template_id)


func pending() -> Array:
	var out: Array = []
	for entry in _offers:
		out.append(_copy_entry(entry))
	return out


func pending_count() -> int:
	return _offers.size()


func clear() -> void:
	_offers.clear()


## [code]-1[/code] when [param name] is empty or not in [member WyrdConfig.pressure_tiers].
func tier_rank(name: String) -> int:
	if name.is_empty():
		return -1
	var tiers := _tiers()
	for index in tiers.size():
		if String(tiers[index]) == name:
			return index
	return -1


## An empty offer tier matches every template. A template with no tier matches
## every offer. Unknown names do not match a tiered template.
func tier_matches(offer_tier: StringName, template: WyrdTemplateDef) -> bool:
	if offer_tier == &"":
		return true
	if template == null or _untiered(template):
		return true
	var offer_rank := tier_rank(String(offer_tier))
	if offer_rank < 0:
		return false
	var low := template.tier_low
	var high := template.tier_high if template.tier_range else template.tier_low
	var low_rank := tier_rank(low)
	var high_rank := tier_rank(high)
	if low_rank < 0 or high_rank < 0:
		return false
	return low_rank <= offer_rank and offer_rank <= high_rank


## Pops the oldest offer. Empty when the queue is empty.
func take_next() -> Dictionary:
	if _offers.is_empty():
		return {}
	var entry := _offers[0]
	_offers.remove_at(0)
	return _copy_entry(entry)


func _enqueue(
	source: StringName,
	key: String,
	tier: StringName,
	payload: Dictionary,
	origin: String,
	template_id: String
) -> void:
	for index in _offers.size():
		var row := _offers[index]
		if row["source"] != source or str(row["key"]) != key:
			continue
		row["tier"] = tier
		row["payload"] = payload
		_offers[index] = row
		_trace(source, key, tier, str(row["origin"]), str(row["template"]), _offers.size(), true)
		return
	_offers.append({
		"key": key,
		"origin": origin,
		"payload": payload,
		"source": source,
		"template": template_id,
		"tier": tier,
	})
	_trace(source, key, tier, origin, template_id, _offers.size(), false)


func _trace(
	source: StringName,
	key: String,
	tier: StringName,
	origin: String,
	template_id: String,
	queued: int,
	replaced: bool
) -> void:
	if not trace_of.is_valid():
		return
	trace_of.call({
		"key": key,
		"origin": origin,
		"queued": queued,
		"replaced": "true" if replaced else "false",
		"source": String(source),
		"template": template_id,
		"tier": String(tier),
	})


func _tiers() -> PackedStringArray:
	if not config_of.is_valid():
		return PackedStringArray()
	var config: Variant = config_of.call()
	if config is WyrdConfig:
		return (config as WyrdConfig).pressure_tiers
	return PackedStringArray()


func _untiered(template: WyrdTemplateDef) -> bool:
	return template.tier_low.is_empty() and template.tier_high.is_empty() and not template.tier_range


func _payload_ok(payload: Dictionary) -> bool:
	for key in payload.keys():
		if not (key is String):
			return false
		if not _value_ok(payload[key]):
			return false
	return true


func _value_ok(value: Variant) -> bool:
	if value is String or value is StringName or value is bool:
		return true
	var kind := typeof(value)
	return kind == TYPE_INT or kind == TYPE_FLOAT


func _copy_payload(payload: Dictionary) -> Dictionary:
	var copy := {}
	for key in payload.keys():
		copy[String(key)] = payload[key]
	return copy


func _copy_entry(entry: Dictionary) -> Dictionary:
	return {
		"key": str(entry.get("key", "")),
		"origin": str(entry.get("origin", "")),
		"payload": _copy_payload(entry.get("payload", {})),
		"source": StringName(str(entry.get("source", ""))),
		"template": str(entry.get("template", "")),
		"tier": StringName(str(entry.get("tier", ""))),
	}
