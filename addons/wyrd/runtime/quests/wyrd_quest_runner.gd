class_name WyrdQuestRunner
extends RefCounted

## Quest status, stages, waits, variants, outcomes, and the journal.
##
## @experimental
## [code]start when[/code] and [code]waits_until[/code] advance only after the
## tick queue has re-checked them. A stage that names a scene offers it; the
## host opens it, and transitions wait until that scene ends normally. An
## aborted scene stays pending. The winning slot variant replaces the stage
## body. [code]unwilling[/code] and [code]barred[/code] are evaluated live and
## again on a tick when no scene or host step is open. Ending a scene finishes
## the current body before that re-check. [code]route_closed[/code] does not
## finish the quest. The quest
## completes when every declared outcome is [code]done[/code] or [code]failed[/code]
## and the current body has no transition. Any [code]failed[/code] outcome
## fails the quest instead. [code]on_empty: wait[/code] holds a stage when a
## slot is empty and no variant matched. Journal text and its date are frozen
## at the write. The default date is [code]day N, HH:MM[/code]. An
## [code]await_host[/code] step calls [method request_host_step] and pauses
## the remaining entry steps until [method complete_host_step].

signal quest_state_changed(quest_id: String, status: StringName)
signal stage_changed(quest_id: String, stage_id: String)
signal journal_entry_added(quest_id: String, entry_id: String, text: String)
signal content_unavailable(quest_id: String, pack_id: String)
signal host_step_requested(quest_id: String, screen_id: StringName, fields: PackedStringArray)

const DORMANT: StringName = &"dormant"
const AVAILABLE: StringName = &"available"
const ACTIVE: StringName = &"active"
const COMPLETED: StringName = &"completed"
const FAILED: StringName = &"failed"
const ABANDONED: StringName = &"abandoned"
const UNAVAILABLE: StringName = &"unavailable"
const _HOP_LIMIT := 24

var runtime: WyrdRuntime
var _states: Dictionary = {}
var _declared: Dictionary = {}
var _fired: Dictionary = {}
var _formatter: Callable = Callable()
var _text: WyrdText
## Quest ids visited every tick: active, or a start that is not a pure fact compare.
var _watch: Dictionary = {}
## Pure start-condition index to quest ids. Those stay dormant until the flag is true.
var _by_cond: Dictionary = {}
var _pure_start: Dictionary = {}
var _wake: Dictionary = {}


class QuestState extends RefCounted:
	var status: StringName = &"dormant"
	var stage_id: String = ""
	var variant: String = ""
	var outcomes: Dictionary = {}
	var offered: String = ""
	var slots: PackedStringArray = PackedStringArray()
	var scene_done: bool = false
	var host_screen: String = ""
	var host_fields: PackedStringArray = PackedStringArray()
	var host_returns: Dictionary = {}
	var journal: Array = []
	var entered: bool = false
	var held_empty: bool = false
	var waiting: String = ""
	var step_at: int = 0


func bind(host: WyrdRuntime) -> void:
	runtime = host
	_text = WyrdText.new()
	_text.runtime = host


func reset() -> void:
	_states.clear()
	_declared.clear()
	_fired.clear()
	_watch.clear()
	_wake.clear()
	_by_cond.clear()
	_pure_start.clear()
	if runtime == null or runtime.content() == null:
		return
	var content := runtime.content()
	var ids: Array = content.quests.keys()
	ids.sort()
	for quest_id in ids:
		var quest: WyrdQuestDef = content.quests[quest_id]
		var state := QuestState.new()
		var key := String(quest_id)
		_states[key] = state
		_declared[key] = _collect(quest)
		_index_start(key, quest)
		if not _requires_ok(quest, content.pack_id):
			_set_status(key, state, UNAVAILABLE)
			content_unavailable.emit(key, _missing_pack(quest, content.pack_id))
		else:
			_sync_watch(key, state)


func register_date_formatter(fn: Callable) -> void:
	if not fn.is_valid():
		push_error("WyrdQuestRunner.register_date_formatter: missing callable")
		return
	_formatter = fn


func format_date(minutes: int) -> String:
	if _formatter.is_valid():
		return str(_formatter.call(minutes))
	return WyrdText.game_date(minutes)


func note_ready(index: int) -> void:
	if not _by_cond.has(index):
		return
	for quest_id in _by_cond[index]:
		_wake[String(quest_id)] = true


func on_tick() -> void:
	var ids: Array = []
	if runtime != null and not runtime.locals_empty():
		ids = _states.keys()
		_wake.clear()
	else:
		var seen := {}
		for quest_id in _watch.keys():
			seen[quest_id] = true
			ids.append(quest_id)
		for quest_id in _wake.keys():
			if not seen.has(quest_id):
				ids.append(quest_id)
		_wake.clear()
	ids.sort()
	for quest_id in ids:
		var state := _states[quest_id] as QuestState
		var quest := _quest(String(quest_id))
		if quest == null or state == null:
			continue
		if state.status == DORMANT or state.status == AVAILABLE:
			_consider_start(String(quest_id), quest, state)
		elif state.status == ACTIVE:
			_continue(String(quest_id), quest, state, 0, true)


func clear_event_fires() -> void:
	_fired.clear()


## Runs the current stage's first matching [code]on[/code] handler for this emit.
## A stage handles one emit id once. A transition does not enter the next stage's
## handlers for the same emit.
func on_world_event(emit_id: int, event_name: StringName, payload: Dictionary) -> void:
	if runtime == null:
		return
	var locals := {}
	var payload_keys: Array = payload.keys()
	payload_keys.sort()
	for key in payload_keys:
		locals["event.%s" % String(key)] = payload[key]
	var ids: Array = _states.keys()
	ids.sort()
	for quest_id in ids:
		var state := _states[quest_id] as QuestState
		if state == null or state.status != ACTIVE:
			continue
		var quest := _quest(String(quest_id))
		if quest == null:
			continue
		var body := _body_now(quest, state)
		if body == null or body.handlers.is_empty():
			continue
		var token := "%d|%s|%s" % [emit_id, String(quest_id), state.stage_id]
		if _fired.has(token):
			continue
		runtime.bind_locals(locals)
		for handler in body.handlers:
			if handler.event_name != String(event_name):
				continue
			if handler.where_cond == null or not runtime.eval_bool(handler.where_cond):
				continue
			_fired[token] = true
			_arm_effects(String(quest_id))
			runtime.effects.run_all(handler.effects)
			_take_handler_transition(String(quest_id), quest, state, handler)
			break
		runtime.clear_locals()
	runtime.clear_locals()


func on_scene_ended(scene_id: String, status: StringName, _reason: StringName) -> void:
	if status != &"ended":
		return
	var ids: Array = _states.keys()
	ids.sort()
	for quest_id in ids:
		var state := _states[quest_id] as QuestState
		if state == null or state.status != ACTIVE:
			continue
		if state.offered == scene_id and not state.scene_done:
			state.scene_done = true
			if state.waiting.begins_with("scene:"):
				state.waiting = ""
			var quest := _quest(String(quest_id))
			if quest != null:
				_continue(String(quest_id), quest, state, 0)
			return


func note_outcome(quest_id: String, branch: StringName, value: StringName) -> void:
	var state := _states.get(quest_id) as QuestState
	if state == null or branch == &"":
		return
	state.outcomes[String(branch)] = String(value)


func status(quest_id: String) -> StringName:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		return &""
	return state.status


func stage(quest_id: String) -> String:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		return ""
	return state.stage_id


func outcome(quest_id: String, branch: String) -> String:
	var state := _states.get(quest_id) as QuestState
	if state == null or not state.outcomes.has(branch):
		return ""
	return String(state.outcomes[branch])


func waiting_reason(quest_id: String) -> String:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		return ""
	return state.waiting


func offered_scene(quest_id: String) -> String:
	var state := _states.get(quest_id) as QuestState
	if state == null or state.scene_done:
		return ""
	return state.offered


func variant_of(quest_id: String) -> String:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		return ""
	return state.variant


func journal(quest_id: String) -> Array:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		return []
	return state.journal.duplicate()


func host_returns(quest_id: String) -> Dictionary:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		return {}
	return state.host_returns.duplicate(true)


func offer_for(scene_id: String) -> Dictionary:
	var ids: Array = _states.keys()
	ids.sort()
	for quest_id in ids:
		var state := _states[quest_id] as QuestState
		if state != null and state.status == ACTIVE and state.offered == scene_id and not state.scene_done:
			return {"quest": String(quest_id), "slots": state.slots.duplicate()}
	return {"quest": "", "slots": PackedStringArray()}


func export_state() -> Dictionary:
	var out := {}
	var ids: Array = _states.keys()
	ids.sort()
	for quest_id in ids:
		var state := _states[quest_id] as QuestState
		if state == null:
			continue
		var fields: Array = []
		for field in state.host_fields:
			fields.append(String(field))
		var slots: Array = []
		for slot_name in state.slots:
			slots.append(String(slot_name))
		out[String(quest_id)] = {
			"entered": state.entered,
			"held_empty": state.held_empty,
			"host_fields": fields,
			"host_returns": state.host_returns.duplicate(true),
			"host_screen": state.host_screen,
			"journal": state.journal.duplicate(true),
			"offered": state.offered,
			"outcomes": state.outcomes.duplicate(true),
			"scene_done": state.scene_done,
			"slots": slots,
			"stage": state.stage_id,
			"status": String(state.status),
			"step_at": state.step_at,
			"variant": state.variant,
			"waiting": state.waiting,
		}
	return out


func import_state(data: Dictionary) -> void:
	_fired.clear()
	for quest_id in data.keys():
		var state := _states.get(String(quest_id)) as QuestState
		var row: Variant = data[quest_id]
		if state == null or not (row is Dictionary):
			continue
		var item: Dictionary = row
		state.status = StringName(str(item.get("status", "dormant")))
		state.stage_id = String(item.get("stage", ""))
		state.variant = String(item.get("variant", ""))
		state.outcomes = (item.get("outcomes", {}) as Dictionary).duplicate(true)
		state.offered = String(item.get("offered", ""))
		state.scene_done = bool(item.get("scene_done", false))
		state.host_screen = String(item.get("host_screen", ""))
		state.host_returns = (item.get("host_returns", {}) as Dictionary).duplicate(true)
		var journal: Array = []
		for entry in item.get("journal", []):
			if entry is Dictionary:
				var copy: Dictionary = (entry as Dictionary).duplicate(true)
				copy["minutes"] = int(copy.get("minutes", 0))
				journal.append(copy)
		state.journal = journal
		state.entered = bool(item.get("entered", false))
		state.held_empty = bool(item.get("held_empty", false))
		state.waiting = String(item.get("waiting", ""))
		state.step_at = int(item.get("step_at", 0))
		var slots := PackedStringArray()
		for slot_name in item.get("slots", []):
			slots.append(String(slot_name))
		state.slots = slots
		var fields := PackedStringArray()
		for field in item.get("host_fields", []):
			fields.append(String(field))
		state.host_fields = fields
	_retrack()


func abandon(quest_id: String) -> void:
	var state := _states.get(quest_id) as QuestState
	if state == null:
		push_error("WyrdQuestRunner.abandon: unknown quest \"%s\"" % quest_id)
		return
	if state.status != ACTIVE and state.status != AVAILABLE:
		push_error("WyrdQuestRunner.abandon: \"%s\" is %s" % [quest_id, String(state.status)])
		return
	if runtime != null and runtime.dialogue != null and runtime.dialogue.is_open():
		runtime.dialogue.abort(&"abandoned")
	state.waiting = ""
	state.entered = false
	state.held_empty = false
	_set_status(quest_id, state, ABANDONED)


func request_host_step(quest_id: String, screen_id: StringName, fields: PackedStringArray = PackedStringArray()) -> void:
	var state := _states.get(quest_id) as QuestState
	if state == null or state.status != ACTIVE:
		push_error("WyrdQuestRunner.request_host_step: \"%s\" is not active" % quest_id)
		return
	if screen_id == &"":
		push_error("WyrdQuestRunner.request_host_step: missing screen")
		return
	state.host_screen = String(screen_id)
	state.host_fields = fields.duplicate()
	state.waiting = "host:%s" % state.host_screen
	if runtime != null:
		var names: Array = []
		for field in state.host_fields:
			names.append(String(field))
		runtime.trace_add("host_step", {"fields": names, "quest": quest_id, "screen": state.host_screen})
	host_step_requested.emit(quest_id, screen_id, state.host_fields)


func complete_host_step(quest_id: String, values: Dictionary) -> void:
	var state := _states.get(quest_id) as QuestState
	if state == null or state.host_screen.is_empty():
		push_error("WyrdQuestRunner.complete_host_step: \"%s\" is not waiting on the host" % quest_id)
		return
	if runtime != null:
		runtime.trace_add("complete_host", {"quest": quest_id, "values": values.duplicate(true)})
	state.host_returns = values.duplicate(true)
	state.host_screen = ""
	if state.waiting.begins_with("host:"):
		state.waiting = ""
	var quest := _quest(quest_id)
	if quest != null:
		_continue(quest_id, quest, state, 0)


func _consider_start(quest_id: String, quest: WyrdQuestDef, state: QuestState) -> void:
	if not _cond_ready(quest.start_when):
		return
	if state.status == DORMANT:
		_set_status(quest_id, state, AVAILABLE)
	_activate(quest_id, quest, state)


func _activate(quest_id: String, quest: WyrdQuestDef, state: QuestState) -> void:
	if quest.stages.is_empty():
		_set_status(quest_id, state, ACTIVE)
		return
	runtime.roles.begin_quest(quest_id)
	_set_status(quest_id, state, ACTIVE)
	state.stage_id = quest.stages[0].id
	state.entered = false
	_enter(quest_id, quest, state, 0)


func _continue(quest_id: String, quest: WyrdQuestDef, state: QuestState, hops: int, recheck: bool = false) -> void:
	if hops > _HOP_LIMIT:
		push_error("WyrdQuestRunner: stage hop limit on \"%s\"" % quest_id)
		return
	if state.status != ACTIVE:
		return
	if state.held_empty:
		var held := _stage_by_id(quest, state.stage_id)
		if held != null and _pick(quest, held)["hold"]:
			state.waiting = "on_empty"
			return
		state.held_empty = false
		state.entered = false
	if not state.entered:
		_enter(quest_id, quest, state, hops)
		return
	if state.host_screen != "":
		state.waiting = "host:%s" % state.host_screen
		return
	if state.offered != "" and not state.scene_done:
		state.waiting = "scene:%s" % state.offered
		return
	if recheck and _adopt_pick(quest_id, quest, state, hops):
		return
	var body := _body_now(quest, state)
	if body == null:
		return
	if state.step_at < _entry_steps(body).size():
		_after_steps(quest_id, quest, state, body, hops, _run_steps(quest_id, state, body))
		return
	if _wait_blocks(state, body):
		return
	state.waiting = ""
	if _take_transition(quest_id, quest, state, body, hops):
		return
	_maybe_finish(quest_id, state, body)


func _enter(quest_id: String, quest: WyrdQuestDef, state: QuestState, hops: int) -> void:
	if hops > _HOP_LIMIT:
		push_error("WyrdQuestRunner: stage hop limit on \"%s\"" % quest_id)
		return
	var stage := _stage_by_id(quest, state.stage_id)
	if stage == null:
		push_error("WyrdQuestRunner: unknown stage \"%s\"" % state.stage_id)
		return
	runtime.roles.enter_stage(quest_id, state.stage_id)
	var pick := _pick(quest, stage)
	state.variant = String(pick["key"])
	state.entered = true
	state.step_at = 0
	state.offered = ""
	state.slots = PackedStringArray()
	state.scene_done = false
	state.held_empty = false
	stage_changed.emit(quest_id, state.stage_id)
	if pick["hold"]:
		state.held_empty = true
		state.waiting = "on_empty"
		return
	var body := pick["body"] as WyrdStageDef
	_after_steps(quest_id, quest, state, body, hops, _run_steps(quest_id, state, body))


func _after_steps(quest_id: String, quest: WyrdQuestDef, state: QuestState, body: WyrdStageDef, hops: int, divert: String) -> void:
	if divert != "":
		_goto(quest_id, quest, state, divert, hops + 1)
		return
	if state.host_screen != "":
		state.waiting = "host:%s" % state.host_screen
		return
	if state.offered != "":
		state.waiting = "scene:%s" % state.offered
		return
	if _wait_blocks(state, body):
		return
	state.waiting = ""
	if _take_transition(quest_id, quest, state, body, hops):
		return
	_maybe_finish(quest_id, state, body)


func _entry_steps(body: WyrdStageDef) -> Array:
	var steps: Array = []
	if body == null:
		return steps
	for journal_line in body.journals:
		steps.append({"at": journal_line.line, "journal": journal_line, "kind": &"journal"})
	for effect in body.effects:
		steps.append({"at": effect.line, "effect": effect, "kind": &"effect"})
	for scene in body.scenes:
		steps.append({"at": int(scene.get("line", 0)), "kind": &"scene", "scene": scene})
	for host in body.hosts:
		steps.append({
			"at": int(host.get("line", 0)),
			"fields": host.get("fields", PackedStringArray()),
			"kind": &"host",
			"screen": String(host.get("screen", "")),
		})
	steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"]) < int(b["at"]))
	return steps


func _run_steps(quest_id: String, state: QuestState, body: WyrdStageDef) -> String:
	var steps := _entry_steps(body)
	var offered := state.offered != ""
	while state.step_at < steps.size():
		var step: Dictionary = steps[state.step_at]
		state.step_at += 1
		var kind: StringName = step["kind"]
		if kind == &"journal":
			_write_journal(quest_id, state, step["journal"])
		elif kind == &"effect":
			_arm_effects(quest_id)
			var divert := runtime.effects.run_one(step["effect"])
			if divert != "":
				return divert
		elif kind == &"scene" and not offered:
			_offer(state, step["scene"])
			offered = true
		elif kind == &"host":
			var fields := PackedStringArray()
			var raw: Variant = step.get("fields", PackedStringArray())
			if raw is PackedStringArray:
				fields = raw
			request_host_step(quest_id, StringName(str(step.get("screen", ""))), fields)
			return ""
	return ""


func _offer(state: QuestState, scene: Dictionary) -> void:
	state.offered = String(scene.get("id", ""))
	state.scene_done = false
	var slots := PackedStringArray()
	for row in scene.get("with", []):
		slots.append(String(row.get("name", "")))
	state.slots = slots


func _write_journal(quest_id: String, state: QuestState, line: WyrdLineDef) -> void:
	var minutes := runtime.now_minutes()
	var entry := {
		"date": format_date(minutes),
		"id": line.line_id,
		"minutes": minutes,
		"text": _text.render(line.prose, line.line_id),
	}
	state.journal.append(entry)
	journal_entry_added.emit(quest_id, line.line_id, String(entry["text"]))


func _take_handler_transition(quest_id: String, quest: WyrdQuestDef, state: QuestState, handler: WyrdOnEventDef) -> bool:
	for row in handler.transitions:
		var when: Variant = row.get("when", null)
		if when is WyrdCompiledCondition and not runtime.eval_bool(when):
			continue
		_goto(quest_id, quest, state, String(row.get("target", "")), 1)
		return true
	return false


func _take_transition(quest_id: String, quest: WyrdQuestDef, state: QuestState, body: WyrdStageDef, hops: int) -> bool:
	for row in body.transitions:
		var when: Variant = row.get("when", null)
		if when is WyrdCompiledCondition and not runtime.eval_bool(when):
			continue
		_goto(quest_id, quest, state, String(row.get("target", "")), hops + 1)
		return true
	return false


func _goto(quest_id: String, quest: WyrdQuestDef, state: QuestState, target: String, hops: int) -> void:
	if _stage_by_id(quest, target) == null:
		push_error("WyrdQuestRunner: unknown stage \"%s\"" % target)
		return
	var previous := state.stage_id
	if runtime != null:
		runtime.trace_add("transition", {"from": previous, "quest": quest_id, "to": target})
	state.stage_id = target
	state.entered = false
	state.held_empty = false
	state.variant = ""
	state.offered = ""
	state.scene_done = false
	state.waiting = ""
	_enter(quest_id, quest, state, hops)


func _maybe_finish(quest_id: String, state: QuestState, body: WyrdStageDef) -> void:
	if body == null or state.status != ACTIVE:
		return
	if state.offered != "" and not state.scene_done:
		return
	if state.host_screen != "" or state.held_empty:
		return
	if body.waits_until != null and not _cond_ready(body.waits_until):
		return
	if body.transitions.size() > 0:
		return
	var names: PackedStringArray = _declared.get(quest_id, PackedStringArray())
	var failed := false
	for branch in names:
		if not state.outcomes.has(String(branch)):
			return
		var value := String(state.outcomes[String(branch)])
		if value == "route_closed":
			return
		if value == "failed":
			failed = true
	state.waiting = ""
	_set_status(quest_id, state, FAILED if failed else COMPLETED)


func _wait_blocks(state: QuestState, body: WyrdStageDef) -> bool:
	if body == null or body.waits_until == null:
		return false
	if _cond_ready(body.waits_until):
		return false
	state.waiting = "waits_until: %s" % body.waits_text
	return true


func _adopt_pick(quest_id: String, quest: WyrdQuestDef, state: QuestState, hops: int) -> bool:
	var stage := _stage_by_id(quest, state.stage_id)
	if stage == null:
		return false
	var pick := _pick(quest, stage)
	var key := String(pick["key"])
	var hold := bool(pick["hold"])
	if key == state.variant and hold == state.held_empty:
		return false
	state.variant = key
	state.step_at = 0
	state.offered = ""
	state.slots = PackedStringArray()
	state.scene_done = false
	state.held_empty = hold
	state.waiting = ""
	if hold:
		state.waiting = "on_empty"
		return true
	var body := pick["body"] as WyrdStageDef
	_after_steps(quest_id, quest, state, body, hops, _run_steps(quest_id, state, body))
	return true


func _pick(quest: WyrdQuestDef, stage: WyrdStageDef) -> Dictionary:
	var chosen: WyrdVariantDef = null
	var chosen_at := -1
	for slot in quest.slots:
		var found: Dictionary = runtime.roles.resolve_slot(quest.id, StringName(slot.name), true)
		var variant: Variant = found.get("variant", null)
		if variant == null or not (variant is WyrdVariantDef):
			continue
		var at := _variant_index(stage, variant)
		if at < 0:
			continue
		if chosen == null or at < chosen_at:
			chosen = variant
			chosen_at = at
	if chosen != null:
		return {
			"body": chosen.body,
			"hold": false,
			"key": "%s.%s" % [chosen.slot, String(chosen.state)],
		}
	if quest.on_empty == "wait" and _any_empty(quest):
		return {"body": null, "hold": true, "key": ""}
	return {"body": stage, "hold": false, "key": ""}


func _variant_index(stage: WyrdStageDef, variant: WyrdVariantDef) -> int:
	for i in stage.variants.size():
		if stage.variants[i] == variant:
			return i
	return -1


func _any_empty(quest: WyrdQuestDef) -> bool:
	for slot in quest.slots:
		var state: StringName = runtime.roles.resolve_slot(quest.id, StringName(slot.name), false)["state"]
		if state == &"empty" or state == &"contested":
			return true
	return false


func _body_now(quest: WyrdQuestDef, state: QuestState) -> WyrdStageDef:
	var stage := _stage_by_id(quest, state.stage_id)
	if stage == null or state.variant.is_empty():
		return stage
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null and "%s.%s" % [variant.slot, String(variant.state)] == state.variant:
			return variant.body
	return stage


func _cond_ready(cond: WyrdCompiledCondition) -> bool:
	if cond == null:
		return true
	var content := runtime.content()
	if content == null:
		return false
	var index := content.index_of(cond)
	if runtime.condition_dirty(index):
		return false
	if cond.uses_spatial:
		return runtime.condition_flag(index) != 0
	return runtime.eval_bool(cond)


func _collect(quest: WyrdQuestDef) -> PackedStringArray:
	var found := {}
	for stage in quest.stages:
		_collect_stage(stage, found)
	var names := PackedStringArray()
	for branch in found.keys():
		names.append(String(branch))
	names.sort()
	return names


func _collect_stage(stage: WyrdStageDef, found: Dictionary) -> void:
	if stage == null:
		return
	for effect in stage.effects:
		if effect.kind == &"outcome" and not effect.branch.is_empty():
			found[effect.branch] = true
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null:
			_collect_stage(variant.body, found)


func _requires_ok(quest: WyrdQuestDef, pack_id: String) -> bool:
	for item in quest.requires:
		if _pack_name(String(item)) != pack_id:
			return false
	return true


func _missing_pack(quest: WyrdQuestDef, pack_id: String) -> String:
	for item in quest.requires:
		var name := _pack_name(String(item))
		if name != pack_id:
			return name
	return ""


func _pack_name(token: String) -> String:
	if token.begins_with("pack."):
		return token.substr(5)
	return token


func _arm_effects(quest_id: String) -> void:
	runtime.effects.quest_id = quest_id
	runtime.effects.scene_id = ""
	runtime.effects.choice_id = ""


func _set_status(quest_id: String, state: QuestState, next: StringName) -> void:
	if state.status == next:
		return
	state.status = next
	_sync_watch(quest_id, state)
	quest_state_changed.emit(quest_id, next)


func _index_start(quest_id: String, quest: WyrdQuestDef) -> void:
	if quest == null or quest.start_when == null or runtime == null or runtime.content() == null:
		return
	var index := runtime.content().index_of(quest.start_when)
	if index < 0 or not runtime.content().is_pure(index):
		return
	_pure_start[quest_id] = index
	var bucket: Array = _by_cond.get(index, [])
	bucket.append(quest_id)
	_by_cond[index] = bucket


func _sync_watch(quest_id: String, state: QuestState) -> void:
	var follow := state.status == ACTIVE
	if not follow and (state.status == DORMANT or state.status == AVAILABLE) and not _pure_start.has(quest_id):
		follow = true
	if follow:
		_watch[quest_id] = true
	else:
		_watch.erase(quest_id)


func _retrack() -> void:
	_watch.clear()
	for quest_id in _states.keys():
		var state := _states[quest_id] as QuestState
		if state != null:
			_sync_watch(String(quest_id), state)
	_catch_up()


func _catch_up() -> void:
	if runtime == null:
		return
	for index in _by_cond.keys():
		var at := int(index)
		if runtime.condition_dirty(at) or runtime.condition_flag(at) != 1:
			continue
		for quest_id in _by_cond[index]:
			_wake[String(quest_id)] = true


func _quest(quest_id: String) -> WyrdQuestDef:
	if runtime == null or runtime.content() == null:
		return null
	return runtime.content().quests.get(quest_id) as WyrdQuestDef


func _stage_by_id(quest: WyrdQuestDef, stage_id: String) -> WyrdStageDef:
	if quest == null:
		return null
	for stage in quest.stages:
		if stage.id == stage_id:
			return stage
	return null
