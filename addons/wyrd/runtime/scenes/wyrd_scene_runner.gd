class_name WyrdSceneRunner
extends RefCounted

## Walks one open scene. The facade exposes this as [code]Wyrd.dialogue[/code].
##
## @experimental
## Line text is always emitted. [code]line_audio(line_id, locale)[/code] may
## return null and never hides text or advances a line. [method advance] is
## the only way past a line. [method choose] runs the choice effects, then
## diverts. [code]-> scene[/code] calls a sub-scene and returns. [method abort]
## runs [code]on_abort[/code] from the inside out. [method can_save] is false
## while a scene is open. A bound holder who dies, or whose slot holder
## changes, aborts with [code]holder_died[/code] or [code]holder_left[/code].
## A choice effect, or a scene-line effect, that changes this scene's own holder
## does not abort it. Its remaining lines keep the speakers bound when the scene opened.
## Every other open scene still aborts.
## [method open] lists unlocked topics with an eligible storylet.
## [method ask_topic] runs that storylet. A line or set emits [signal topic_answered].

signal line_ready(line: WyrdLineView)
signal choices_ready(choices: Array[WyrdChoiceView])
signal scene_ended(scene_id: String, status: StringName, reason: StringName)
signal topic_answered(npc: StringName, topic: StringName, line: WyrdLineView)

var runtime: WyrdRuntime
var locale: String = ""
var _text: WyrdText
var _stack: Array = []
var _root_id: String = ""
var _wait: StringName = &""
var _line: WyrdLineView
var _choices: Array[WyrdChoiceView] = []
var _pending: Array[WyrdChoiceDef] = []
var _line_audio: Callable = Callable()
var _disabled: Dictionary = {}
var _aborting: bool = false
var _in_step: bool = false


class Frame extends RefCounted:
	var scene_id: String = ""
	var quest_id: String = ""
	var index: int = 0
	var slots: PackedStringArray = PackedStringArray()
	var holders: Dictionary = {}


func bind(host: WyrdRuntime) -> void:
	runtime = host
	_text = WyrdText.new()
	_text.runtime = host


func register_line_audio(fn: Callable) -> void:
	if not fn.is_valid():
		push_error("WyrdSceneRunner.register_line_audio: missing callable")
		return
	_line_audio = fn


func is_open() -> bool:
	return not _stack.is_empty()


## Quest id of the open scene, or empty when the scene was not offered by a quest.
func open_quest_id() -> String:
	var frame := _top()
	if frame == null:
		return ""
	return frame.quest_id


func can_save() -> bool:
	return not is_open()


## Sorted unlocked topics that have an eligible storylet for [param npc] now.
## Does not record a selection, run effects, or open a scene.
func open(npc: String) -> PackedStringArray:
	if runtime != null:
		runtime.trace_add("open_topic", {"npc": npc})
	if not _npc_known(npc):
		push_error("WyrdSceneRunner.open: unknown npc \"%s\"" % npc)
		return PackedStringArray()
	var listed := _topics_for(npc)
	if runtime != null:
		runtime.trace_topic_open(npc, listed.size())
	return listed


## Asks [param topic] of [param npc]. Refusals, in order, are an unknown npc,
## an open scene, a locked topic, then no eligible storylet.
func ask_topic(npc: String, topic: String) -> Dictionary:
	if runtime != null:
		runtime.trace_add("ask_topic", {"npc": npc, "topic": topic})
	if not _npc_known(npc):
		push_error("WyrdSceneRunner.ask_topic: unknown npc \"%s\"" % npc)
		return _ask_row({}, "")
	if is_open():
		push_warning("WyrdSceneRunner.ask_topic: a scene is open")
		_trace_ask(npc, topic, "", false, "scene_open")
		return _ask_row({}, "scene_open")
	if runtime == null or runtime.topics == null or not runtime.topics.is_unlocked(StringName(topic)):
		push_warning("WyrdSceneRunner.ask_topic: \"%s\" is locked" % topic)
		_trace_ask(npc, topic, "", false, "locked")
		return _ask_row({}, "locked")
	var row: Dictionary = runtime.director.query_for_entity("topic", topic, npc)
	if str(row.get("id", "")).is_empty():
		_trace_ask(npc, topic, "", false, "no_storylet")
		return _ask_row(row, "no_storylet")
	var storylet_id := str(row.get("id", ""))
	_trace_ask(npc, topic, storylet_id, true, "answered")
	var story: WyrdStoryletDef = runtime.content().storylets.get(storylet_id) as WyrdStoryletDef
	var drawn := {"line_id": str(row.get("line_id", "")), "scene": str(row.get("scene", ""))}
	if str(row.get("body", "")) == "scene":
		open_scene(str(row.get("scene", "")))
	elif story != null:
		var view := runtime.present_topic_line(story, drawn, npc)
		topic_answered.emit(StringName(npc), StringName(topic), view)
	return _ask_row(row, "answered")


func _npc_known(npc: String) -> bool:
	if npc.is_empty() or runtime == null:
		return false
	var world := runtime.adapter(WyrdWorldAdapter) as WyrdWorldAdapter
	if world == null:
		return false
	return world.exists(StringName(npc))


func _topics_for(npc: String) -> PackedStringArray:
	var listed := PackedStringArray()
	if runtime == null or runtime.topics == null or runtime.director == null:
		return listed
	for topic in runtime.topics.unlocked():
		if runtime.director.eligible_for_entity(&"topic", topic, npc).is_empty():
			continue
		listed.append(topic)
	return listed


func _trace_ask(npc: String, topic: String, storylet_id: String, ok: bool, reason: String) -> void:
	if runtime == null:
		return
	runtime.trace_topic_ask(npc, topic, storylet_id, ok, reason)


func _ask_row(row: Dictionary, reason: String) -> Dictionary:
	var out := {
		"body": str(row.get("body", "")),
		"candidates": int(row.get("candidates", 0)),
		"id": str(row.get("id", "")),
		"line_id": str(row.get("line_id", "")),
		"priority": int(row.get("priority", 0)),
		"reason": reason,
		"scene": str(row.get("scene", "")),
		"score": str(row.get("score", "-")),
		"seen": int(row.get("seen", 0)),
		"specificity": int(row.get("specificity", 0)),
		"weight": int(row.get("weight", 0)),
	}
	return out


func line() -> WyrdLineView:
	return _line


func render_prose(prose: WyrdExprNode, line_id: String) -> String:
	if _text == null:
		return ""
	return _text.render(prose, line_id)


func audio_for(line_id: String) -> Variant:
	return _audio(line_id)


func choices() -> Array[WyrdChoiceView]:
	return _choices.duplicate()


func open_scene(scene_id: String) -> void:
	if is_open():
		push_error("WyrdSceneRunner.open_scene: a scene is already open")
		return
	if _scene(scene_id) == null:
		push_error("WyrdSceneRunner.open_scene: unknown scene \"%s\"" % scene_id)
		return
	if runtime != null:
		runtime.trace_add("open_scene", {"id": scene_id})
	var quest_id := ""
	var slots := PackedStringArray()
	if runtime != null and runtime.quests != null:
		var offer: Dictionary = runtime.quests.offer_for(scene_id)
		quest_id = String(offer["quest"])
		slots = offer["slots"]
	_root_id = scene_id
	_push(scene_id, quest_id, slots)
	_pump()


func advance() -> void:
	if _wait != &"line":
		push_error("WyrdSceneRunner.advance: no line is waiting")
		return
	if runtime != null:
		runtime.trace_add("advance", {})
	_line = null
	_wait = &""
	var frame := _top()
	if frame != null:
		frame.index += 1
	_pump()


func choose(index: int) -> void:
	if _wait != &"choice":
		push_error("WyrdSceneRunner.choose: no choices are waiting")
		return
	if index < 0 or index >= _pending.size():
		push_error("WyrdSceneRunner.choose: index %d is out of range" % index)
		return
	if not _choices[index].enabled:
		push_error("WyrdSceneRunner.choose: choice %d is disabled" % index)
		return
	if runtime != null:
		runtime.trace_add("choose", {"index": index})
	var choice := _pending[index]
	var frame := _top()
	_choices.clear()
	_pending.clear()
	_wait = &""
	if frame == null:
		return
	runtime.effects.quest_id = frame.quest_id
	runtime.effects.scene_id = frame.scene_id
	runtime.effects.choice_id = choice.line_id
	var divert := runtime.effects.run_all(choice.effects)
	_go(frame, divert if divert != "" else choice.target)
	_pump()


func abort(reason: StringName) -> void:
	if not is_open():
		push_error("WyrdSceneRunner.abort: no scene is open")
		return
	if runtime != null:
		runtime.trace_add("abort", {"reason": String(reason)})
	if _aborting:
		return
	_aborting = true
	var frames: Array = _stack.duplicate()
	for i in range(frames.size() - 1, -1, -1):
		var frame := frames[i] as Frame
		var scene := _scene(frame.scene_id)
		if scene == null:
			continue
		runtime.effects.quest_id = frame.quest_id
		runtime.effects.scene_id = frame.scene_id
		runtime.effects.choice_id = ""
		runtime.effects.run_all(scene.on_abort)
	_aborting = false
	_finish(&"aborted", reason)


func on_tick() -> void:
	if not is_open() or _aborting or runtime == null:
		return
	var world := runtime.adapter(WyrdWorldAdapter) as WyrdWorldAdapter
	if world == null:
		return
	for entry in _stack:
		var frame := entry as Frame
		for slot_name in frame.slots:
			var who: StringName = frame.holders.get(slot_name, &"")
			if who == &"":
				continue
			if not world.is_alive(who):
				abort(&"holder_died")
				return


func note_role(role_id: StringName, _old_holder: StringName, _new_holder: StringName) -> void:
	if not is_open() or _aborting or runtime == null:
		return
	var skip := -1
	if runtime.effects != null and not _stack.is_empty():
		var top := _top()
		var own := runtime.effects.choice_id != "" or _in_step
		if own and top != null and top.scene_id == runtime.effects.scene_id:
			skip = _stack.size() - 1
	for i in _stack.size():
		if i == skip:
			continue
		var frame := _stack[i] as Frame
		if frame == null or frame.quest_id.is_empty():
			continue
		for slot_name in frame.slots:
			var slot := _slot(frame.quest_id, String(slot_name))
			if slot == null or slot.role != String(role_id):
				continue
			var now := runtime.roles.slot_holder(frame.quest_id, StringName(slot_name))
			var was: StringName = frame.holders.get(slot_name, &"")
			if now != was:
				abort(&"holder_left")
				return


func force_close() -> void:
	_stack.clear()
	_root_id = ""
	_wait = &""
	_line = null
	_choices.clear()
	_pending.clear()
	_disabled.clear()
	_aborting = false
	_in_step = false


func _pump() -> void:
	var guard := 0
	while is_open() and _wait == &"":
		guard += 1
		if guard > 1000:
			push_error("WyrdSceneRunner: step limit")
			abort(&"step_limit")
			return
		var frame := _top()
		var scene := _scene(frame.scene_id)
		if scene == null or frame.index >= scene.items.size():
			_pop()
			continue
		var item := scene.items[frame.index]
		if item.kind == &"line":
			if item.line_def == null or not _line_ok(item.line_def):
				frame.index += 1
				continue
			_show_line(frame, item.line_def)
			return
		if item.kind == &"choice":
			var group := _gather(scene, frame.index)
			var views := _present(frame, group)
			if views.is_empty():
				frame.index += group.size()
				continue
			_choices = views
			_wait = &"choice"
			if runtime != null:
				var rows: Array = []
				for view in views:
					rows.append({
						"enabled": view.enabled,
						"index": view.index,
						"reason": view.reason,
						"text": view.text,
					})
				runtime.trace_add("choices", {"rows": rows})
			choices_ready.emit(views)
			return
		if item.kind == &"label":
			frame.index += 1
			continue
		if item.kind == &"divert":
			_divert(frame, scene, item)
			continue
		if item.kind == &"effect":
			var divert := _run_scene_effect(frame, item)
			if not is_open():
				return
			if divert != "":
				_go(frame, divert)
				continue
			frame.index += 1
			continue
		frame.index += 1


func _run_scene_effect(frame: Frame, item: WyrdSceneItem) -> String:
	if item.effect == null or runtime == null or runtime.effects == null:
		return ""
	var saved_scene := runtime.effects.scene_id
	var saved_choice := runtime.effects.choice_id
	var saved_quest := runtime.effects.quest_id
	runtime.effects.scene_id = frame.scene_id
	runtime.effects.choice_id = ""
	runtime.effects.quest_id = frame.quest_id
	_in_step = true
	runtime.trace_effect_run("scene", frame.scene_id, String(item.effect.kind))
	var divert := runtime.effects.run_one(item.effect)
	_in_step = false
	runtime.effects.scene_id = saved_scene
	runtime.effects.choice_id = saved_choice
	runtime.effects.quest_id = saved_quest
	if not is_open():
		return ""
	return divert


func _show_line(frame: Frame, line_def: WyrdLineDef) -> void:
	var view := WyrdLineView.new()
	var shown_id := line_def.line_id
	var shown_text := ""
	var shown_tags := line_def.tags
	if runtime != null:
		var shown := runtime.apply_variant_secrecy(line_def, runtime.resolve_line(line_def))
		shown_id = str(shown["id"])
		shown_text = str(shown["text"])
		shown_tags = shown["tags"] as PackedStringArray
	else:
		shown_text = _text.render(line_def.prose, line_def.line_id)
	view.id = shown_id
	if runtime != null and runtime.coverage != null:
		runtime.coverage.hit("line", shown_id)
	var who := _who(line_def.speaker, frame.quest_id)
	view.speaker = who["id"]
	view.display_name = String(who["name"])
	view.roles = _roles_held(who["id"], frame)
	view.text = shown_text
	view.tags = shown_tags.duplicate()
	view.audio = _audio(shown_id)
	if runtime != null:
		runtime.trace_add("line_audio", {"id": view.id, "present": view.audio != null})
		runtime.trace_add("line", {"id": view.id, "text": view.text})
	_line = view
	_wait = &"line"
	line_ready.emit(view)


func _present(frame: Frame, group: Array[WyrdSceneItem]) -> Array[WyrdChoiceView]:
	var views: Array[WyrdChoiceView] = []
	_pending = []
	for item in group:
		var choice := item.choice
		if choice == null or not _choice_ok(choice):
			continue
		var disabled := _is_disabled(choice)
		var view := WyrdChoiceView.new()
		view.index = views.size()
		view.id = choice.line_id
		view.text = _text.render(choice.label, choice.line_id)
		view.enabled = not disabled
		view.reason = choice.disabled_reason if disabled else ""
		view.tags = choice.tags.duplicate()
		if runtime != null and runtime.coverage != null:
			runtime.coverage.hit("line", view.id)
		views.append(view)
		_pending.append(choice)
	return views


func _divert(frame: Frame, scene: WyrdSceneDef, item: WyrdSceneItem) -> void:
	if item.divert_kind == &"end":
		frame.index = scene.items.size()
		return
	if item.divert_kind == &"label":
		_go(frame, item.target)
		return
	if item.divert_kind == &"scene":
		frame.index += 1
		if _scene(item.target) == null:
			push_error("WyrdSceneRunner: unknown scene \"%s\"" % item.target)
			return
		_push(item.target, frame.quest_id, frame.slots)
		return
	frame.index += 1


func _go(frame: Frame, target: String) -> void:
	if target == "end":
		var scene := _scene(frame.scene_id)
		frame.index = scene.items.size() if scene != null else 0
		return
	var scene := _scene(frame.scene_id)
	if scene == null:
		return
	for i in scene.items.size():
		var item := scene.items[i]
		if item.kind == &"label" and item.label == target:
			frame.index = i
			return
	push_error("WyrdSceneRunner: unknown label \"%s\"" % target)
	frame.index += 1


func _gather(scene: WyrdSceneDef, at: int) -> Array[WyrdSceneItem]:
	var group: Array[WyrdSceneItem] = []
	var index := at
	while index < scene.items.size() and scene.items[index].kind == &"choice":
		group.append(scene.items[index])
		index += 1
	return group


func _push(scene_id: String, quest_id: String, slots: PackedStringArray) -> void:
	var frame := Frame.new()
	frame.scene_id = scene_id
	frame.quest_id = quest_id
	frame.slots = _bound(scene_id, quest_id, slots)
	for slot_name in frame.slots:
		if quest_id.is_empty():
			frame.holders[slot_name] = &""
		else:
			frame.holders[slot_name] = runtime.roles.slot_holder(quest_id, StringName(slot_name))
	_stack.append(frame)


func _bound(scene_id: String, quest_id: String, slots: PackedStringArray) -> PackedStringArray:
	var names := slots.duplicate()
	var quest := _quest(quest_id)
	var scene := _scene(scene_id)
	if quest == null or scene == null:
		return names
	var known := {}
	for slot in quest.slots:
		known[slot.name] = true
	for item in scene.items:
		if item.line_def == null:
			continue
		var speaker := item.line_def.speaker
		if known.has(speaker) and not names.has(speaker):
			names.append(speaker)
	return names


func _pop() -> void:
	if _stack.is_empty():
		return
	_stack.pop_back()
	if _stack.is_empty():
		_finish(&"ended", &"")


func _finish(status: StringName, reason: StringName) -> void:
	var root := _root_id
	_stack.clear()
	_wait = &""
	_line = null
	_choices.clear()
	_pending.clear()
	_root_id = ""
	scene_ended.emit(root, status, reason)


func _line_ok(line_def: WyrdLineDef) -> bool:
	if not _secrecy_ok(line_def.secrecy, line_def.line_id, line_def.speaker):
		return false
	if line_def.condition == null:
		return true
	return runtime.eval_bool(line_def.condition)


func _choice_ok(choice: WyrdChoiceDef) -> bool:
	if not _secrecy_ok(choice.secrecy, choice.line_id, ""):
		return false
	if choice.condition == null:
		return true
	return runtime.eval_bool(choice.condition)


func _secrecy_ok(name: String, line_id: String, speaker: String) -> bool:
	if runtime == null or runtime.secrecy_allows(name):
		return true
	runtime.trace_secrecy("", line_id, name, runtime.secrecy_unlocked_name(), "", speaker)
	return false


func _is_disabled(choice: WyrdChoiceDef) -> bool:
	if choice.disabled_when.is_empty() or runtime == null or runtime.content() == null:
		return false
	var key := choice.disabled_when
	if not _disabled.has(key):
		var diagnostics := WyrdDiagnostics.new()
		var compiled := WyrdCondition.new().compile(
			key,
			runtime.content().schema,
			diagnostics,
			"",
			choice.line,
			choice.col
		)
		if diagnostics.has_errors():
			push_error("WyrdSceneRunner: disabled_when failed to compile")
			_disabled[key] = null
		else:
			_disabled[key] = compiled
	var cached: Variant = _disabled[key]
	if cached == null or not (cached is WyrdCompiledCondition):
		return false
	return runtime.eval_bool(cached)


func _who(token: String, quest_id: String) -> Dictionary:
	if token.is_empty() or token == "narrator":
		return {"id": &"narrator", "name": "narrator"}
	var quest := _quest(quest_id)
	if quest != null:
		for slot in quest.slots:
			if slot.name != token:
				continue
			var holder := _bound_holder(token, quest_id)
			var name := _display(holder)
			if name.is_empty():
				name = String(holder)
			return {"id": holder, "name": name}
	var shown := _display(StringName(token))
	if shown.is_empty():
		shown = token
	return {"id": StringName(token), "name": shown}


func _roles_held(entity: StringName, frame: Frame) -> PackedStringArray:
	var found := PackedStringArray()
	if entity == &"" or entity == &"narrator" or frame == null or runtime == null:
		return found
	var quest := _quest(frame.quest_id)
	if quest == null:
		return found
	var seen := {}
	for slot in quest.slots:
		if not frame.slots.has(slot.name) or slot.role.is_empty():
			continue
		if _bound_holder(slot.name, frame.quest_id) != entity:
			continue
		if seen.has(slot.role):
			continue
		seen[slot.role] = true
		found.append(slot.role)
	found.sort()
	return found


func _bound_holder(token: String, quest_id: String) -> StringName:
	var frame := _top()
	if frame != null and frame.quest_id == quest_id and frame.holders.has(token):
		return StringName(frame.holders[token])
	return runtime.roles.slot_holder(quest_id, StringName(token))


func _display(id: StringName) -> String:
	if id == &"" or runtime == null:
		return ""
	var world := runtime.adapter(WyrdWorldAdapter) as WyrdWorldAdapter
	if world == null:
		return ""
	return world.display_name(id)


func _audio(line_id: String) -> Variant:
	if not _line_audio.is_valid():
		return null
	return _line_audio.call(line_id, _locale())


func _locale() -> String:
	if not locale.is_empty():
		return locale
	return TranslationServer.get_locale()


func _top() -> Frame:
	if _stack.is_empty():
		return null
	return _stack[_stack.size() - 1] as Frame


func _scene(scene_id: String) -> WyrdSceneDef:
	if runtime == null or runtime.content() == null:
		return null
	return runtime.content().scenes.get(scene_id) as WyrdSceneDef


func _quest(quest_id: String) -> WyrdQuestDef:
	if quest_id.is_empty() or runtime == null or runtime.content() == null:
		return null
	return runtime.content().quests.get(quest_id) as WyrdQuestDef


func _slot(quest_id: String, slot_name: String) -> WyrdSlotDef:
	var quest := _quest(quest_id)
	if quest == null:
		return null
	for slot in quest.slots:
		if slot.name == slot_name:
			return slot
	return null
