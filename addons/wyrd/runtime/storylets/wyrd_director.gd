class_name WyrdDirector
extends RefCounted

## Picks one storylet for a scope and speaker.
##
## @experimental
## [code]speaker: any[/code] is a wildcard. A specific query speaker matches
## that speaker and [code]any[/code]. An empty query speaker, or [code]any[/code],
## matches every storylet in the scope. [code]Any[/code] is not the wildcard.
## Exact speaker is a filter, not a rank key.
##
## Filters are scope, speaker, [code]when[/code], then cooldown. Cooldown is
## hard: a storylet is eligible when it has never been selected, its cooldown
## is 0, or the minutes since [code]last_minute[/code] are at least
## [member WyrdStoryletDef.cooldown_minutes]. If every match is cooling, the
## query has no winner.
##
## A bark also consults [member WyrdStoryletDef.speaker_cooldown_minutes].
## The clock key is the query speaker when that name is concrete, otherwise
## the storylet speaker when that name is concrete. [code]any[/code] and an
## empty name are not concrete and do not start a clock. Topic, event, and
## beat queries ignore it. A win with a positive cooldown stores that
## duration for the key. A candidate is cooling while [code]now - last[/code]
## is still below the stored duration.
##
## Ranking, highest first: priority, specificity, weight, then fewer times
## seen, then the older [code]last_minute[/code]. Never selected sorts as
## older than any selection. Generics stay in this pool at specificity 0.
## A higher priority beats a more specific storylet.
##
## Remaining ties are sorted by id. [method WyrdRng.for_decision] on
## [constant STREAM] breaks them. The decision key is the scope text and the
## query speaker. The time bucket is the current game minute. A bark query
## ignores [code]scope_id[/code] for both the match and that key. A unique
## winner does not roll.
##
## A win records the selection, then draws the body. [method WyrdStoryletDeck.draw]
## alone does not record one. Candidates in the trace are the count after the
## filters.

const STREAM: StringName = &"storylet_director"
const WILDCARD := "any"

var _runtime: WyrdRuntime


func bind(runtime: WyrdRuntime) -> void:
	_runtime = runtime


func query(scope_kind: String, scope_id: String = "", speaker: String = "") -> Dictionary:
	var kind := StringName(scope_kind)
	var scope_text := _scope_text(kind, scope_id)
	if _runtime == null or _runtime.content() == null or _runtime.storylets == null:
		push_error("Wyrd.director.query: load content before a storylet query")
		return _finish(scope_text, speaker, [], null, {}, 0)
	if not _known_scope(kind):
		push_error("Wyrd.director.query: unknown scope \"%s\"" % scope_kind)
		return _finish(scope_text, speaker, [], null, {}, 0)
	var matched := _eligible(kind, scope_id, speaker)
	var winner: WyrdStoryletDef = _pick(matched, scope_text, speaker)
	var drawn := {}
	var seen_before := 0
	if winner != null:
		seen_before = _runtime.storylets.seen_of(winner.id)
		var minute := _runtime.now_minutes()
		_runtime.storylets.note_selected(winner.id, minute)
		_note_speaker(winner, speaker, minute)
		drawn = _runtime.storylets.draw(winner.id)
		if kind == &"bark":
			_runtime.present_bark(winner, drawn)
	return _finish(scope_text, speaker, matched, winner, drawn, seen_before)


func _finish(
	scope_text: String,
	speaker: String,
	matched: Array,
	winner: WyrdStoryletDef,
	drawn: Dictionary,
	seen_before: int
) -> Dictionary:
	var score := "-"
	var priority := 0
	var specificity := 0
	var weight := 0
	var winner_id := ""
	var body := ""
	var line_id := ""
	var scene := ""
	if winner != null:
		priority = winner.priority
		specificity = winner.specificity
		weight = winner.weight
		winner_id = winner.id
		body = String(winner.body_kind)
		score = "%d/%d/%d/%d" % [priority, specificity, weight, seen_before]
		line_id = str(drawn.get("line_id", ""))
		scene = str(drawn.get("scene", winner.scene_id))
	var row := {
		"body": body,
		"candidates": matched.size(),
		"id": winner_id,
		"line_id": line_id,
		"priority": priority,
		"scene": scene,
		"score": score,
		"seen": seen_before,
		"specificity": specificity,
		"weight": weight,
	}
	if _runtime != null:
		_runtime.trace_director({
			"candidates": matched.size(),
			"key": _scope_id_of(scope_text),
			"scope": scope_text,
			"score": score,
			"speaker": speaker,
			"winner": winner_id,
		})
	return row


## Explains one storylet for a query. Does not record a selection.
func why_not(storylet_id: String, scope_kind: String, scope_id: String = "", speaker: String = "") -> Dictionary:
	var kind := StringName(scope_kind)
	var scope_text := _scope_text(kind, scope_id)
	if _runtime == null or _runtime.content() == null or _runtime.storylets == null:
		push_error("Wyrd.director.why_not: load content before a storylet query")
		return _finish_why(storylet_id, scope_text, speaker, false, "missing", "", "-", 0, 0, "")
	var found: Variant = _runtime.content().storylets.get(storylet_id, null)
	if not (found is WyrdStoryletDef):
		push_error("Wyrd.director.why_not: unknown storylet \"%s\"" % storylet_id)
		return _finish_why(storylet_id, scope_text, speaker, false, "missing", "", "-", 0, 0, "")
	var story: WyrdStoryletDef = found
	var score := "%d/%d/%d/%d" % [story.priority, story.specificity, story.weight, _runtime.storylets.seen_of(story.id)]
	var remaining := _remaining(story)
	if not _known_scope(kind):
		push_error("Wyrd.director.why_not: unknown scope \"%s\"" % scope_kind)
		return _finish_why(storylet_id, scope_text, speaker, false, "scope", "", score, story.cooldown_minutes, remaining, "")
	if not _scope_matches(story, kind, scope_id):
		return _finish_why(storylet_id, scope_text, speaker, false, "scope", "", score, story.cooldown_minutes, remaining, "")
	if not _speaker_matches(story.speaker, speaker):
		return _finish_why(storylet_id, scope_text, speaker, false, "speaker", "", score, story.cooldown_minutes, remaining, "")
	var clause := _failing_clause(story)
	if not clause.is_empty():
		return _finish_why(storylet_id, scope_text, speaker, false, "when", clause, score, story.cooldown_minutes, remaining, "")
	if _cooling(story):
		return _finish_why(storylet_id, scope_text, speaker, false, "cooldown", "", score, story.cooldown_minutes, remaining, "")
	if _speaker_cooling(story, speaker):
		var key := _speaker_key(story, speaker)
		var stored := _runtime.storylets.speaker_cooldown_of(key)
		var left := _runtime.storylets.speaker_remaining(key, _runtime.now_minutes())
		return _finish_why(storylet_id, scope_text, speaker, false, "cooldown", "", score, stored, left, "")
	var matched := _eligible(kind, scope_id, speaker)
	var winner: WyrdStoryletDef = _pick(matched, scope_text, speaker)
	var winner_id := "" if winner == null else winner.id
	if winner_id == story.id:
		return _finish_why(storylet_id, scope_text, speaker, true, "ok", "", score, story.cooldown_minutes, remaining, winner_id)
	return _finish_why(storylet_id, scope_text, speaker, false, "outranked", "", score, story.cooldown_minutes, remaining, winner_id)


static func format_why_not(row: Dictionary) -> String:
	var clause := str(row.get("clause", ""))
	if clause.is_empty():
		clause = "-"
	var spoken := str(row.get("speaker", ""))
	if spoken.is_empty():
		spoken = "-"
	var winner := str(row.get("winner", ""))
	if winner.is_empty():
		winner = "-"
	var eligible := "true" if bool(row.get("eligible", false)) else "false"
	return "wyrd why_not storylet=%s scope=%s speaker=%s eligible=%s reason=%s clause=\"%s\" score=%s cooldown=%s remaining=%s winner=%s" % [
		str(row.get("storylet", "")),
		str(row.get("scope", "")),
		spoken,
		eligible,
		str(row.get("reason", "")),
		clause,
		str(row.get("score", "-")),
		str(row.get("cooldown", 0)),
		str(row.get("remaining", 0)),
		winner,
	]


func _finish_why(
	storylet_id: String,
	scope_text: String,
	speaker: String,
	eligible: bool,
	reason: String,
	clause: String,
	score: String,
	cooldown: int,
	remaining: int,
	winner: String
) -> Dictionary:
	var row := {
		"clause": clause,
		"cooldown": cooldown,
		"eligible": eligible,
		"key": _scope_id_of(scope_text),
		"reason": reason,
		"remaining": remaining,
		"scope": scope_text,
		"score": score,
		"speaker": speaker,
		"storylet": storylet_id,
		"winner": winner,
	}
	if _runtime != null:
		_runtime.trace_why_not(row)
	return row


func _eligible(kind: StringName, scope_id: String, speaker: String) -> Array:
	var matched: Array = []
	if _runtime == null or _runtime.content() == null:
		return matched
	var ids: Array = _runtime.content().storylets.keys()
	ids.sort()
	for id in ids:
		var found: Variant = _runtime.content().storylets[id]
		if not (found is WyrdStoryletDef):
			continue
		var story: WyrdStoryletDef = found
		if not _scope_matches(story, kind, scope_id):
			continue
		if not _speaker_matches(story.speaker, speaker):
			continue
		if not _when_passes(story):
			continue
		if _cooling(story):
			continue
		if _speaker_cooling(story, speaker):
			continue
		matched.append(story)
	return matched


func _failing_clause(story: WyrdStoryletDef) -> String:
	if story.condition == null:
		return ""
	if story.clauses.is_empty():
		if _runtime.eval_storylet(story.condition, story.id):
			return ""
		return story.when_text
	for index in story.clauses.size():
		if _runtime.eval_storylet(story.clauses[index], story.id):
			continue
		if index < story.clause_text.size():
			return story.clause_text[index]
		return story.when_text
	return ""


func _remaining(story: WyrdStoryletDef) -> int:
	if story.cooldown_minutes <= 0 or _runtime == null or _runtime.storylets == null:
		return 0
	var last := _runtime.storylets.last_minute_of(story.id)
	if last < 0:
		return 0
	var elapsed := _runtime.now_minutes() - last
	if elapsed >= story.cooldown_minutes:
		return 0
	return story.cooldown_minutes - elapsed


func _pick(matched: Array, scope_text: String, speaker: String) -> WyrdStoryletDef:
	if matched.is_empty():
		return null
	var best: Array = [matched[0]]
	for index in range(1, matched.size()):
		var story: WyrdStoryletDef = matched[index]
		var cmp := _compare(story, best[0])
		if cmp > 0:
			best = [story]
		elif cmp == 0:
			best.append(story)
	if best.size() == 1:
		return best[0]
	var by_id := {}
	var names: Array = []
	for story in best:
		by_id[story.id] = story
		names.append(story.id)
	names.sort()
	var key := StringName("%s\t%s" % [scope_text, speaker])
	var rng := WyrdRng.for_decision(_runtime.game_seed(), STREAM, key, _runtime.now_minutes())
	return by_id[names[rng.randi_bounded(names.size())]]


## Above zero when [param a] should win over [param b].
func _compare(a: WyrdStoryletDef, b: WyrdStoryletDef) -> int:
	if a.priority != b.priority:
		return 1 if a.priority > b.priority else -1
	if a.specificity != b.specificity:
		return 1 if a.specificity > b.specificity else -1
	if a.weight != b.weight:
		return 1 if a.weight > b.weight else -1
	var seen_a := _runtime.storylets.seen_of(a.id)
	var seen_b := _runtime.storylets.seen_of(b.id)
	if seen_a != seen_b:
		return 1 if seen_a < seen_b else -1
	var last_a := _runtime.storylets.last_minute_of(a.id)
	var last_b := _runtime.storylets.last_minute_of(b.id)
	if last_a != last_b:
		return 1 if last_a < last_b else -1
	return 0


func _scope_matches(story: WyrdStoryletDef, kind: StringName, scope_id: String) -> bool:
	if story.scope_kind != kind:
		return false
	if kind == &"bark":
		return true
	return story.scope_id == scope_id


func _speaker_matches(story_speaker: String, query_speaker: String) -> bool:
	if query_speaker.is_empty() or query_speaker == WILDCARD:
		return true
	if story_speaker == WILDCARD:
		return true
	return story_speaker == query_speaker


func _when_passes(story: WyrdStoryletDef) -> bool:
	if story.condition == null:
		return true
	return _runtime.eval_storylet(story.condition, story.id)


func _cooling(story: WyrdStoryletDef) -> bool:
	if story.cooldown_minutes <= 0:
		return false
	var last := _runtime.storylets.last_minute_of(story.id)
	if last < 0:
		return false
	return _runtime.now_minutes() - last < story.cooldown_minutes


func _note_speaker(story: WyrdStoryletDef, query_speaker: String, minute: int) -> void:
	if story.scope_kind != &"bark" or story.speaker_cooldown_minutes <= 0:
		return
	var key := _speaker_key(story, query_speaker)
	if key.is_empty():
		return
	_runtime.storylets.note_bark_speaker(key, story.speaker_cooldown_minutes, minute)


func _speaker_cooling(story: WyrdStoryletDef, query_speaker: String) -> bool:
	if story.scope_kind != &"bark":
		return false
	var key := _speaker_key(story, query_speaker)
	if key.is_empty() or _runtime == null or _runtime.storylets == null:
		return false
	return _runtime.storylets.speaker_cooling(key, _runtime.now_minutes())


func _speaker_key(story: WyrdStoryletDef, query_speaker: String) -> String:
	if _concrete(query_speaker):
		return query_speaker
	if _concrete(story.speaker):
		return story.speaker
	return ""


func _concrete(name: String) -> bool:
	return not name.is_empty() and name != WILDCARD


func _known_scope(kind: StringName) -> bool:
	return kind == &"topic" or kind == &"bark" or kind == &"event" or kind == &"beat"


func _scope_text(kind: StringName, scope_id: String) -> String:
	if kind == &"bark":
		return "bark"
	return "%s %s" % [String(kind), scope_id]


func _scope_id_of(scope_text: String) -> String:
	if scope_text == "bark":
		return ""
	var split := scope_text.find(" ")
	if split < 0:
		return ""
	return scope_text.substr(split + 1)
