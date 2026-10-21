class_name WyrdGenerator
extends RefCounted

## Unsaved story-pressure queue.
##
## @experimental
## [method offer] appends a host offer, or replaces tier and payload when the
## same source and key are already queued. Deed hooks use [method queue_deed].
## The queue is not saved. [member generate_handler] is the runtime's handler.

var generate_handler: Callable = Callable()
var config_of: Callable = Callable()
var trace_of: Callable = Callable()
var runtime: WyrdRuntime = null

var _offers: Array[Dictionary] = []
var _proposals: Dictionary = {}
var _pending: Array[WyrdProposal] = []
var _reserved: Dictionary = {}
var _seq: int = 0


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


func bind(host: WyrdRuntime) -> void:
	runtime = host


func clear() -> void:
	_offers.clear()
	_proposals.clear()
	_pending.clear()
	_reserved.clear()
	_seq = 0


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
		_trace(source, key, tier, str(row["origin"]), str(row["template"]), _offers.size(), true, payload)
		return
	_offers.append({
		"key": key,
		"origin": origin,
		"payload": payload,
		"source": source,
		"template": template_id,
		"tier": tier,
	})
	_trace(source, key, tier, origin, template_id, _offers.size(), false, payload)


func _trace(
	source: StringName,
	key: String,
	tier: StringName,
	origin: String,
	template_id: String,
	queued: int,
	replaced: bool,
	payload: Dictionary
) -> void:
	if not trace_of.is_valid():
		return
	trace_of.call({
		"key": key,
		"origin": origin,
		"payload": _copy_payload(payload),
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


func proposal(id: String) -> WyrdProposal:
	return _proposals.get(id) as WyrdProposal


func pending_creations() -> Array:
	var out: Array = []
	for item in _pending:
		out.append(item)
	return out


func finish_reservations() -> void:
	_pending.clear()
	_reserved.clear()


## Host pick. Not queued. Null when the input is rejected or nothing can be proposed.
func propose(context: Dictionary) -> WyrdProposal:
	if context == null:
		push_error("Wyrd.generator.propose: source and key are required")
		return null
	var source := StringName(str(context.get("source", "")))
	var key := str(context.get("key", ""))
	if source == &"" or key.is_empty():
		push_error("Wyrd.generator.propose: source and key are required")
		return null
	var tier := StringName(str(context.get("tier", "")))
	if tier != &"" and tier_rank(String(tier)) < 0:
		push_error("Wyrd.generator.propose: unknown pressure tier \"%s\"" % String(tier))
		return null
	var payload: Dictionary = context.get("payload", {}) if context.get("payload") is Dictionary else {}
	if not _payload_ok(payload):
		push_error("Wyrd.generator.propose: payload values must be string, number, or bool")
		return null
	return _decide(source, key, tier, "", _copy_payload(payload), "host", false)


## One generate-queue unit. Reserves a successful proposal for the end of the tick.
func fulfill(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	_decide(
		StringName(str(entry.get("source", ""))),
		str(entry.get("key", "")),
		StringName(str(entry.get("tier", ""))),
		str(entry.get("template", "")),
		_copy_payload(entry.get("payload", {})),
		str(entry.get("origin", "")),
		true
	)


## [code]unknown[/code], [code]accepted[/code], [code]stale[/code], or the new instance id.
func accept(proposal: WyrdProposal) -> String:
	var proposal_id := ""
	var instance := ""
	var reason := "unknown"
	var ok := false
	if proposal != null:
		proposal_id = proposal.id
	if proposal == null or proposal.id.is_empty() or not _proposals.has(proposal.id):
		reason = "unknown"
	elif proposal.used:
		reason = "accepted"
		instance = proposal.instance
	elif runtime == null or runtime.quests == null or runtime.quests.template_counter(proposal.template) != proposal.expected_counter:
		reason = "stale"
	else:
		instance = runtime.quests.create_instance(proposal.template, proposal.casts, proposal.params)
		if instance == "":
			reason = "refused"
		else:
			proposal.used = true
			proposal.instance = instance
			ok = true
			reason = "created"
	_trace_line("gen_accept", {
		"instance": instance,
		"ok": "true" if ok else "false",
		"proposal": proposal_id,
		"reason": reason,
	}, "wyrd gen_accept proposal=%s ok=%s reason=%s instance=%s" % [proposal_id, "true" if ok else "false", reason, instance])
	if reason == "unknown" or reason == "stale" or reason == "accepted":
		return reason
	return instance


func _decide(
	source: StringName,
	key: String,
	tier: StringName,
	template_filter: String,
	payload: Dictionary,
	origin: String,
	reserve: bool
) -> WyrdProposal:
	var eligible := _eligible(tier, template_filter)
	_trace_line("gen_tier", {
		"eligible": eligible.size(),
		"key": key,
		"source": String(source),
		"tier": String(tier),
	}, "wyrd gen_tier source=%s key=%s tier=%s eligible=%d" % [String(source), key, String(tier), eligible.size()])
	var seed_key := "pick:%s:%s" % [String(source), key]
	if eligible.is_empty():
		_trace_line("gen_pick", {
			"band": 0,
			"key": key,
			"reason": "no_template",
			"score": "0/0",
			"seed_key": seed_key,
			"source": String(source),
			"template": "",
		}, "wyrd gen_pick source=%s key=%s template= reason=no_template score=0/0 band=0 seed_key=%s" % [String(source), key, seed_key])
		if not reserve:
			_trace_propose(source, key, tier, payload, false, "no_template", "")
		return null
	var band := _top_band(eligible)
	var chosen: WyrdTemplateDef = _weighted(band, seed_key)
	var score := "%d/%d" % [chosen.priority, chosen.specificity]
	_trace_line("gen_pick", {
		"band": band.size(),
		"key": key,
		"score": score,
		"seed_key": seed_key,
		"source": String(source),
		"template": chosen.id,
	}, "wyrd gen_pick source=%s key=%s template=%s score=%s band=%d seed_key=%s" % [String(source), key, chosen.id, score, band.size(), seed_key])
	var expected := _counter(chosen.id) + _reserved_count(chosen.id)
	var instance := "%s#%d" % [chosen.id, expected + 1]
	var casts := {}
	var params := {}
	if runtime != null:
		runtime.begin_provisional(instance)
		runtime.push_scope(instance)
	var bound := _bind_template(chosen, instance, casts, params)
	if runtime != null:
		runtime.pop_scope()
		runtime.end_provisional()
	if not bound:
		if not reserve:
			_trace_propose(source, key, tier, payload, false, "no_candidate", "")
		return null
	var proposal := WyrdProposal.new()
	_seq += 1
	proposal.id = "p%d" % _seq
	proposal.source = String(source)
	proposal.key = key
	proposal.tier = String(tier)
	proposal.origin = origin
	proposal.template = chosen.id
	proposal.instance = instance
	proposal.casts = casts
	proposal.params = params
	proposal.payload = _copy_payload(payload)
	proposal.expected_counter = expected
	_proposals[proposal.id] = proposal
	if reserve:
		_reserved[chosen.id] = _reserved_count(chosen.id) + 1
		_pending.append(proposal)
	else:
		_trace_propose(source, key, tier, payload, true, "proposed", proposal.id)
	return proposal


func _trace_propose(
	source: StringName,
	key: String,
	tier: StringName,
	payload: Dictionary,
	ok: bool,
	reason: String,
	proposal_id: String
) -> void:
	var flag := "true" if ok else "false"
	_trace_line("gen_propose", {
		"key": key,
		"ok": flag,
		"payload": _copy_payload(payload),
		"proposal": proposal_id,
		"reason": reason,
		"source": String(source),
		"tier": String(tier),
	}, "wyrd gen_propose source=%s key=%s ok=%s reason=%s proposal=%s" % [String(source), key, flag, reason, proposal_id])


func _eligible(tier: StringName, template_filter: String) -> Array[WyrdTemplateDef]:
	var found: Array[WyrdTemplateDef] = []
	if runtime == null or runtime.content() == null:
		return found
	var ids: Array = runtime.content().templates.keys()
	ids.sort()
	for id in ids:
		var template: WyrdTemplateDef = runtime.content().templates[id]
		if template == null:
			continue
		if not template_filter.is_empty() and template.id != template_filter:
			continue
		if not tier_matches(tier, template):
			continue
		if template.weight <= 0:
			continue
		if not _when_ok(template):
			continue
		var live := 0
		if runtime.quests != null:
			live = runtime.quests.active_count(template.id)
		if live + _reserved_count(template.id) >= template.max_active:
			continue
		found.append(template)
	return found


func _when_ok(template: WyrdTemplateDef) -> bool:
	if template.when_cond == null or runtime == null:
		return true
	return runtime.eval_storylet(template.when_cond, template.id)


func _top_band(eligible: Array[WyrdTemplateDef]) -> Array[WyrdTemplateDef]:
	var best_priority := 0
	var best_specificity := 0
	var first := true
	for template in eligible:
		if first or template.priority > best_priority or (template.priority == best_priority and template.specificity > best_specificity):
			best_priority = template.priority
			best_specificity = template.specificity
			first = false
	var band: Array[WyrdTemplateDef] = []
	for template in eligible:
		if template.priority == best_priority and template.specificity == best_specificity:
			band.append(template)
	return band


func _weighted(band: Array[WyrdTemplateDef], seed_key: String) -> WyrdTemplateDef:
	var total := 0
	for template in band:
		total += maxi(template.weight, 0)
	if band.size() == 1 or total <= 0 or runtime == null:
		return band[0]
	var rng := WyrdRng.for_decision(runtime.game_seed(), &"generator", StringName(seed_key), runtime.now_minutes())
	var roll := rng.randi_bounded(total)
	var cursor := 0
	for template in band:
		cursor += maxi(template.weight, 0)
		if roll < cursor:
			return template
	return band[band.size() - 1]


func _bind_template(template: WyrdTemplateDef, instance: String, casts: Dictionary, params: Dictionary) -> bool:
	if runtime == null or runtime.roles == null:
		return false
	for slot in template.slots:
		if slot.mode != &"cast":
			continue
		var pool := runtime.roles.cast_pool(slot)
		var decision := "cast:%s.%s" % [instance, slot.name]
		_trace_candidates(decision, pool["raw"])
		var picked := runtime.roles.pick_id(pool["accepted"], &"generator", decision)
		if picked == &"":
			return false
		casts[slot.name] = String(picked)
		runtime.provisional_cast(slot.name, picked)
		_trace_line("gen_cast", {
			"entity": String(picked),
			"instance": instance,
			"kind": slot.kind,
			"slot": slot.name,
		}, "wyrd gen_cast instance=%s slot=%s kind=%s entity=%s" % [instance, slot.name, slot.kind, String(picked)])
	for param in template.params:
		var pool := runtime.roles.param_pool(param)
		var decision := "param:%s.%s" % [instance, param.name]
		_trace_candidates(decision, pool["raw"])
		var picked := runtime.roles.pick_id(pool["accepted"], &"generator", decision)
		if picked == &"":
			return false
		params[param.name] = _param_snapshot(param, picked)
		runtime.provisional_param(param.name, picked)
		_trace_line("gen_bind", {
			"entity": String(picked),
			"instance": instance,
			"kind": param.kind,
			"param": param.name,
		}, "wyrd gen_bind instance=%s param=%s kind=%s entity=%s" % [instance, param.name, param.kind, String(picked)])
	return true


func _param_snapshot(param: WyrdParamDef, entity: StringName) -> Dictionary:
	var snap := {"entity": String(entity), "kind": param.kind}
	if param.kind == "item" and runtime != null:
		var inventory := runtime.adapter(WyrdInventoryAdapter) as WyrdInventoryAdapter
		if inventory != null:
			snap["owner"] = String(inventory.owner_of(entity))
	if (param.kind == "item" or param.kind == "object") and runtime != null:
		var spatial := runtime.adapter(WyrdSpatialAdapter) as WyrdSpatialAdapter
		if spatial != null:
			snap["place"] = String(spatial.place_of(entity))
	return snap


func _trace_candidates(decision_key: String, raw: Array) -> void:
	var digest := WyrdHash.of_int(0)
	for id in raw:
		digest = WyrdHash.combine(digest, WyrdHash.of_string_name(StringName(str(id))))
	_trace_line("gen_candidates", {
		"count": raw.size(),
		"digest": WyrdRng.format_u64(digest),
		"key": decision_key,
	}, "wyrd gen_candidates key=%s count=%d digest=%s" % [decision_key, raw.size(), WyrdRng.format_u64(digest)])


func _trace_line(kind: String, fields: Dictionary, line: String) -> void:
	if runtime == null:
		return
	runtime.trace_gen_line(kind, fields, line)


func _counter(template_id: String) -> int:
	if runtime == null or runtime.quests == null:
		return 0
	return runtime.quests.template_counter(template_id)


func _reserved_count(template_id: String) -> int:
	return int(_reserved.get(template_id, 0))
