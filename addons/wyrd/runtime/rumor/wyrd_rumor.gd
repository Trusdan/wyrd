class_name WyrdRumor
extends RefCounted

## Precise rumor hops. One scheduler unit offers one deed to one listener.
##
## @experimental
## A deed starts a rumor when it carries a reveal claim and the first registered
## policy matches its verb. Origins are the actor and that row's witnesses.
## That slice is the witness index for the deed, so this does not scan the log.
## Each origin offers the claim to sorted [method WyrdSocial.targets] of the
## policy kinds. A listener is queued once, from the earliest speaker.
## The hop rolls [method WyrdRng.for_decision] on stream [code]rumor[/code].
## The decision key is [code]deed, from, to, hop[/code]. The time bucket is the
## hour bucket of [code]now[/code]. Adoption uses the credibility score and
## threshold, and writes [code]believed/<listener>[/code] only.
## A coarse place does not start a rumor. A listener in a coarse place does not
## adopt and does not pass the claim on. Empty places count as precise.
## Jobs, the seen set, and the queued set are not saved. Load drops them.

var social: WyrdSocial
var facts: WyrdFactStore
var config_of: Callable = Callable()
var seed_of: Callable = Callable()
var now_of: Callable = Callable()
var spatial_of: Callable = Callable()
var score_of: Callable = Callable()
var threshold_of: Callable = Callable()
var trace_of: Callable = Callable()
## [code](token: String)[/code]. One rumor unit. Not saved.
var enqueue_hop: Callable = Callable()

var _policies: Array[WyrdRumorPolicy] = []
var _jobs: Dictionary = {}
var _seen: Dictionary = {}
var _queued: Dictionary = {}


func register(policy: WyrdRumorPolicy) -> void:
	if policy == null or String(policy.id).is_empty():
		push_error("WyrdRumor.register: policy needs an id")
		return
	var copy := WyrdRumorPolicy.new()
	copy.id = policy.id
	copy.kinds = policy.kinds.duplicate()
	copy.max_hops = maxi(policy.max_hops, 0)
	copy.verbs = policy.verbs.duplicate()
	var chance := policy.pass_chance
	if is_nan(chance) or is_inf(chance):
		chance = 0.0
	copy.pass_chance = clampf(chance, 0.0, 1.0)
	_policies.append(copy)


## Drops in-flight claims and hop memory. Registered policies stay.
func clear_flight() -> void:
	_jobs.clear()
	_seen.clear()
	_queued.clear()


## Starts a rumor for [param deed] when a policy matches and the place is precise.
func note_deed(deed: Dictionary, claim_key: String, claim_value: Variant) -> void:
	if claim_key.is_empty() or social == null:
		return
	var verb := StringName(str(deed.get("verb", "")))
	var policy := _policy_for(verb)
	if policy == null or policy.max_hops < 1 or policy.kinds.is_empty():
		return
	var place := StringName(str(deed.get("place", "")))
	if _place_is_coarse(place):
		return
	var deed_id := str(int(deed.get("id", 0)))
	if deed_id == "0" or _jobs.has(deed_id):
		return
	_jobs[deed_id] = {
		"chance": policy.pass_chance,
		"key": claim_key,
		"kinds": policy.kinds.duplicate(),
		"max_hops": policy.max_hops,
		"policy": String(policy.id),
		"value": claim_value,
		"verb": String(verb),
	}
	var seen := {}
	for person in _origins(deed):
		seen[String(person)] = true
	_seen[deed_id] = seen
	_queued[deed_id] = {}
	var speakers := PackedStringArray()
	for person in seen.keys():
		speakers.append(String(person))
	speakers.sort()
	for person in speakers:
		_enqueue_from(deed_id, person, 1)


## One rumor unit. A token this runtime did not write is ignored.
func hop(token: String) -> void:
	var parts := token.split("\t")
	if parts.size() != 4:
		return
	var deed_id := parts[0]
	var from_who := parts[1]
	var to_who := parts[2]
	var hop_n := int(parts[3])
	if deed_id.is_empty() or from_who.is_empty() or to_who.is_empty() or not _jobs.has(deed_id):
		return
	if not _seen.has(deed_id):
		_seen[deed_id] = {}
	var seen: Dictionary = _seen[deed_id]
	if bool(seen.get(to_who, false)):
		return
	seen[to_who] = true
	var job: Dictionary = _jobs[deed_id]
	var key := str(job.get("key", ""))
	var policy_id := str(job.get("policy", ""))
	var verb := str(job.get("verb", ""))
	if _listener_is_coarse(StringName(to_who)):
		_trace_hop(deed_id, from_who, to_who, hop_n, key, policy_id, verb, false, "coarse")
		return
	var taken := _roll(deed_id, from_who, to_who, hop_n, float(job.get("chance", 0.0)))
	_trace_hop(deed_id, from_who, to_who, hop_n, key, policy_id, verb, taken, "pass" if taken else "chance")
	if not taken:
		return
	var score := _score(to_who, from_who)
	var accepted := score >= _threshold()
	if accepted:
		accepted = facts != null and facts.set_in(StringName(key), job.get("value"), StringName("believed/%s" % to_who))
	_trace_adopt(from_who, to_who, key, policy_id, verb, score, accepted)
	if not accepted:
		return
	if hop_n < int(job.get("max_hops", 0)):
		_enqueue_from(deed_id, to_who, hop_n + 1)


func _policy_for(verb: StringName) -> WyrdRumorPolicy:
	var text := String(verb)
	for policy in _policies:
		if policy.verbs.is_empty() or policy.verbs.has(text):
			return policy
	return null


func _origins(deed: Dictionary) -> PackedStringArray:
	var bag := {}
	var actor := String(deed.get("actor", ""))
	if not actor.is_empty():
		bag[actor] = true
	var witnesses: Variant = deed.get("witnesses", PackedStringArray())
	if witnesses is PackedStringArray:
		for person in witnesses as PackedStringArray:
			var text := String(person)
			if not text.is_empty():
				bag[text] = true
	elif witnesses is Array:
		for person in witnesses:
			var text := String(person)
			if not text.is_empty():
				bag[text] = true
	var names := PackedStringArray()
	for person in bag.keys():
		names.append(String(person))
	names.sort()
	return names


func _enqueue_from(deed_id: String, source: String, hop_n: int) -> void:
	if not enqueue_hop.is_valid() or not _jobs.has(deed_id) or social == null:
		return
	if not _queued.has(deed_id):
		_queued[deed_id] = {}
	var queued: Dictionary = _queued[deed_id]
	var seen: Dictionary = _seen[deed_id] if _seen.has(deed_id) else {}
	var job: Dictionary = _jobs[deed_id]
	var kinds: PackedStringArray = job["kinds"]
	var picked := {}
	var names := PackedStringArray()
	for kind in kinds:
		var kind_name := String(kind)
		if kind_name.is_empty():
			continue
		for target in social.targets(StringName(source), StringName(kind_name)):
			var person := String(target)
			if person.is_empty() or person == source or seen.has(person) or queued.has(person) or picked.has(person):
				continue
			picked[person] = true
			names.append(person)
	names.sort()
	for person in names:
		queued[person] = true
		enqueue_hop.call(_token(deed_id, source, person, hop_n))


func _roll(deed_id: String, from_who: String, to_who: String, hop_n: int, chance: float) -> bool:
	var seed_value := 0
	if seed_of.is_valid():
		seed_value = int(seed_of.call())
	var key := StringName(_token(deed_id, from_who, to_who, hop_n))
	return WyrdRng.for_decision(seed_value, &"rumor", key, _time_bucket()).randf() < chance


func _time_bucket() -> int:
	var now := 0
	if now_of.is_valid():
		now = int(now_of.call())
	var size := 60
	if config_of.is_valid():
		var cfg: Variant = config_of.call()
		if cfg is WyrdConfig:
			size = maxi((cfg as WyrdConfig).hour_bucket_minutes, 0)
	if size <= 0:
		return now
	return int(now / float(size)) * size


func _score(listener: String, speaker: String) -> float:
	if not score_of.is_valid():
		return 0.0
	return float(score_of.call(StringName(listener), StringName(speaker)))


func _threshold() -> float:
	if not threshold_of.is_valid():
		return 0.5
	return float(threshold_of.call())


func _place_is_coarse(place: StringName) -> bool:
	if place == &"":
		return false
	var spatial := _spatial()
	if spatial == null:
		return false
	return String(spatial.precision(place)) == "coarse"


func _listener_is_coarse(who: StringName) -> bool:
	var spatial := _spatial()
	if spatial == null:
		return false
	var place := spatial.place_of(who)
	if place == &"":
		return false
	return String(spatial.precision(place)) == "coarse"


func _spatial() -> WyrdSpatialAdapter:
	if not spatial_of.is_valid():
		return null
	var found: Variant = spatial_of.call()
	if found is WyrdSpatialAdapter:
		return found as WyrdSpatialAdapter
	return null


func _trace_hop(
	deed_id: String,
	from_who: String,
	to_who: String,
	hop_n: int,
	key: String,
	policy_id: String,
	verb: String,
	taken: bool,
	reason: String
) -> void:
	if not trace_of.is_valid():
		return
	trace_of.call("rumor_hop", {
		"deed": deed_id,
		"from": from_who,
		"hop": hop_n,
		"key": key,
		"path": policy_id,
		"reason": reason,
		"speaker": from_who,
		"taken": "true" if taken else "false",
		"to": to_who,
		"verb": verb,
		"who": to_who,
	})


func _trace_adopt(
	from_who: String,
	to_who: String,
	key: String,
	policy_id: String,
	verb: String,
	score: float,
	accepted: bool
) -> void:
	if not trace_of.is_valid():
		return
	trace_of.call("rumor_adopt", {
		"accepted": "true" if accepted else "false",
		"key": key,
		"listener": to_who,
		"path": policy_id,
		"score": score,
		"speaker": from_who,
		"verb": verb,
		"who": to_who,
	})


static func _token(deed_id: String, from_who: String, to_who: String, hop_n: int) -> String:
	return "%s\t%s\t%s\t%d" % [deed_id, from_who, to_who, hop_n]
