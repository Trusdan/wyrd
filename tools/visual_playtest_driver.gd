extends Node

## Drives the example playtest through its buttons and saves a screenshot after each step.
##
## tools/visual_playtest.sh runs this scene in a real window. Expectations live in
## tools/visual_playtest_expectations.json.

const _SPEC := "res://tools/visual_playtest_expectations.json"
const _SCENE := "res://example/playtest/gullhaven_playtest.tscn"

var _play: Control
var _out := ""
var _width := 0
var _height := 0
var _defaults: Dictionary = {}
var _panels := PackedStringArray()
var _failures: Array[Dictionary] = []
var _shots: Array[Dictionary] = []
var _transcript: Dictionary = {}
var _last_blob := ""
var _date_only: RegEx


func _ready() -> void:
	_run()


func _run() -> void:
	_out = _output_dir()
	if not _out.is_absolute_path():
		_out = ProjectSettings.globalize_path("res://".path_join(_out))
	DirAccess.make_dir_recursive_absolute(_out)
	_date_only = RegEx.create_from_string("^day \\d+, \\d{2}:\\d{2}$")
	var spec := _load_spec()
	if not _failures.is_empty():
		_finish()
		return
	# _ready is still inside the tree setup. Wait a frame before adding the playtest.
	await get_tree().process_frame
	_force_window()
	var packed := load(_SCENE) as PackedScene
	if packed == null:
		_fail("boot", "scene", "playtest scene did not load")
		_finish()
		return
	var ui := packed.instantiate() as Control
	if ui == null:
		_fail("boot", "scene", "playtest scene did not instantiate")
		_finish()
		return
	_play = ui
	print("visual-playtest: spawning")
	get_tree().root.add_child(_play)
	print("visual-playtest: spawned")
	await _settle()
	print("visual-playtest: settled")
	_force_window()
	await _settle()
	var boot := String(_play.call("boot_error"))
	if boot != "":
		_fail("boot", "load", boot)
		_finish()
		return
	var unknown := _unknown_toggle()
	if unknown != "":
		_fail("spec", "defaults", "toggle %s is not listed in defaults" % unknown)
		_finish()
		return
	print("visual-playtest: viewport %s" % _play.get_viewport().get_visible_rect().size)
	var scenarios := spec["scenarios"] as Array
	for item in scenarios:
		var scenario := item as Dictionary
		await _scenario(scenario)
	_finish()


func _scenario(scenario: Dictionary) -> void:
	var scenario_id := String(scenario.get("id", ""))
	if not _name_ok(scenario_id):
		_fail("spec", "scenario", "bad scenario id \"%s\"" % scenario_id)
		return
	print("visual-playtest: %s" % scenario_id)
	_transcript[scenario_id] = ""
	var reset_problem := _perform("press", "Reset")
	if reset_problem != "":
		_fail(scenario_id, "00_setup", reset_problem)
		return
	var flag_problem := _apply_flags(scenario)
	if flag_problem != "":
		_fail(scenario_id, "00_setup", flag_problem)
		await _capture(scenario_id, "00_setup")
		return
	await _capture(scenario_id, "00_setup")
	var steps: Variant = scenario.get("steps", [])
	if not (steps is Array):
		_fail(scenario_id, "steps", "steps is not a list")
		return
	var step_rows := steps as Array
	for item in step_rows:
		var step := item as Dictionary
		var step_name := String(step.get("name", ""))
		if not _name_ok(step_name):
			_fail(scenario_id, step_name, "step name must be letters, digits, underscore, or hyphen")
			return
		print("visual-playtest: %s %s" % [scenario_id, step_name])
		var action_problem := _perform(String(step.get("action", "")), String(step.get("target", "")))
		await _capture(scenario_id, step_name)
		if action_problem != "":
			_fail(scenario_id, step_name, action_problem)
			return
		var expect: Variant = step.get("expect", {})
		if not (expect is Dictionary):
			_fail(scenario_id, step_name, "expect is not an object")
			return
		_expect(scenario_id, step_name, expect as Dictionary)
	var final: Variant = scenario.get("final", {})
	if not (final is Dictionary):
		_fail(scenario_id, "final", "final is not an object")
		return
	_expect_final(scenario_id, final as Dictionary)


func _finish() -> void:
	_write_gallery()
	_write_report()
	if _failures.is_empty():
		print("visual-playtest: ok")
		get_tree().quit(0)
	else:
		print("visual-playtest: failed (%d)" % _failures.size())
		get_tree().quit(1)


func _output_dir() -> String:
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		if args[index] == "--out" and index + 1 < args.size():
			return args[index + 1]
		index += 1
	return "visual-playtest-out"


func _load_spec() -> Dictionary:
	var text := FileAccess.get_file_as_string(_SPEC)
	if text.is_empty():
		_fail("spec", "load", "could not read %s" % _SPEC)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_fail("spec", "load", "expectations are not a JSON object")
		return {}
	var spec := parsed as Dictionary
	_width = int(spec.get("width", 0))
	_height = int(spec.get("height", 0))
	if _width < 100 or _height < 100:
		_fail("spec", "window", "width and height are missing")
		return {}
	var panels: Variant = spec.get("panels", [])
	if not (panels is Array) or (panels as Array).is_empty():
		_fail("spec", "panels", "panels must be a non-empty list")
		return {}
	var panel_rows := panels as Array
	for entry in panel_rows:
		_panels.append(String(entry))
	var defaults: Variant = spec.get("defaults", {})
	if not (defaults is Dictionary) or (defaults as Dictionary).is_empty():
		_fail("spec", "defaults", "defaults must list every toggle")
		return {}
	_defaults = defaults as Dictionary
	var scenarios: Variant = spec.get("scenarios", [])
	if not (scenarios is Array) or (scenarios as Array).is_empty():
		_fail("spec", "scenarios", "scenarios must be a non-empty list")
		return {}
	return spec


func _force_window() -> void:
	var window := get_tree().root
	window.borderless = true
	window.mode = Window.MODE_WINDOWED
	window.size = Vector2i(_width, _height)
	window.position = Vector2i(0, 0)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _unknown_toggle() -> String:
	for node in _play.find_children("Toggle_*", "CheckButton", true, false):
		var toggle := node as CheckButton
		if toggle == null:
			continue
		var key := String(toggle.name).trim_prefix("Toggle_")
		if not _defaults.has(key):
			return key
	return ""


func _apply_flags(scenario: Dictionary) -> String:
	var flags: Dictionary = {}
	for key in _defaults.keys():
		flags[String(key)] = bool(_defaults[key])
	var over: Variant = {}
	if scenario.has("flags"):
		over = scenario["flags"]
	if not (over is Dictionary):
		return "flags is not an object"
	for key in (over as Dictionary).keys():
		var name := String(key)
		if not _defaults.has(name):
			return "unknown flag %s" % name
		flags[name] = bool((over as Dictionary)[key])
	for key in flags.keys():
		var name := String(key)
		var toggle := _play.find_child("Toggle_%s" % name, true, false) as CheckButton
		if toggle == null:
			return "missing toggle %s" % name
		toggle.toggled.emit(bool(flags[name]))
		if toggle.button_pressed != bool(flags[name]):
			return "toggle %s did not stick" % name
	return ""


func _perform(action: String, target: String) -> String:
	if action == "press":
		var button := _button_with_text(target)
		if button == null:
			return "button not found: %s" % target
		if button.disabled:
			return "button disabled: %s" % target
		button.pressed.emit()
		return ""
	if action == "choice":
		var choice := _choice(target)
		if choice == null:
			return "choice not found: %s" % target
		if choice.disabled:
			return "choice disabled: %s" % choice.text
		choice.pressed.emit()
		return ""
	return "unknown action %s" % action


func _button_with_text(title: String) -> Button:
	for node in _play.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or button is CheckButton:
			continue
		if button.text == title:
			return button
	return null


func _choice(label: String) -> Button:
	var choices := _play.find_child("Choices", true, false) as VBoxContainer
	if choices == null:
		return null
	var disabled: Button = null
	var prefix := "%s (" % label
	for child in choices.get_children():
		var button := child as Button
		if button == null:
			continue
		if button.text == label:
			return button
		if button.text.begins_with(prefix):
			disabled = button
	return disabled


func _capture(scenario_id: String, step: String) -> void:
	await _settle()
	var blob := _visible_blob()
	_last_blob = blob
	var past := String(_transcript.get(scenario_id, ""))
	_transcript[scenario_id] = past + blob + "\n"
	var text_problem := _text_problem(blob)
	if text_problem != "":
		_fail(scenario_id, step, text_problem)
	var layout_problem := _layout_problem()
	if layout_problem != "":
		_fail(scenario_id, step, layout_problem)
	_save_shot(scenario_id, step)


func _expect(scenario_id: String, step: String, expect: Dictionary) -> void:
	if expect.is_empty():
		return
	var labels := _dialogue_labels()
	var speaker := ""
	var line := ""
	if labels.size() >= 2:
		speaker = labels[0].text
		line = labels[1].text
	else:
		_fail(scenario_id, step, "dialogue labels are missing")
	if expect.has("speaker") and speaker != String(expect["speaker"]):
		_fail(scenario_id, step, "speaker is \"%s\", expected \"%s\"" % [speaker, String(expect["speaker"])])
	if expect.has("line") and line != String(expect["line"]):
		_fail(scenario_id, step, "line is \"%s\", expected \"%s\"" % [line, String(expect["line"])])
	if expect.has("audio"):
		var audio_value: Variant = _play.call("line_has_audio")
		var got := false
		if audio_value is bool:
			got = audio_value
		var want := bool(expect["audio"])
		if got != want:
			_fail(scenario_id, step, "voice audio is %s, expected %s" % [got, want])
	if expect.has("continue_enabled"):
		var cont := _button_with_text("Continue")
		var enabled := cont != null and not cont.disabled
		if enabled != bool(expect["continue_enabled"]):
			_fail(scenario_id, step, "Continue enabled is %s" % enabled)
	if expect.has("status_contains"):
		var status := _status_text()
		var needle := String(expect["status_contains"])
		if not status.contains(needle):
			_fail(scenario_id, step, "status is \"%s\", expected it to contain \"%s\"" % [status, needle])
	_list_has(scenario_id, step, _last_blob, expect, "contains", true)
	_list_has(scenario_id, step, _last_blob, expect, "lacks", false)


func _expect_final(scenario_id: String, final: Dictionary) -> void:
	_list_has(scenario_id, "final", _last_blob, final, "contains", true)
	_list_has(scenario_id, "final", _last_blob, final, "lacks", false)
	var past := String(_transcript.get(scenario_id, ""))
	_list_has(scenario_id, "final", past, final, "seen", true)
	_list_has(scenario_id, "final", past, final, "unseen", false)


func _list_has(scenario_id: String, step: String, haystack: String, source: Dictionary, key: String, want: bool) -> void:
	if not source.has(key):
		return
	var value: Variant = source[key]
	if not (value is Array):
		_fail(scenario_id, step, "%s is not a list" % key)
		return
	var entries := value as Array
	for entry in entries:
		var needle := String(entry)
		var found := haystack.contains(needle)
		if found == want:
			continue
		if want:
			_fail(scenario_id, step, "missing \"%s\"" % needle)
		else:
			_fail(scenario_id, step, "unexpected \"%s\"" % needle)


func _text_problem(blob: String) -> String:
	var marker := _marker_problem(blob)
	if marker != "":
		return marker
	for node in _play.find_children("*", "Label", true, false):
		var label := node as Label
		if label == null or not label.is_visible_in_tree():
			continue
		var label_problem := _marker_problem(label.text)
		if label_problem != "":
			return label_problem
	for node in _play.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or not button.is_visible_in_tree():
			continue
		var button_problem := _marker_problem(button.text)
		if button_problem != "":
			return button_problem
	var cont := _button_with_text("Continue")
	var labels := _dialogue_labels()
	if cont != null and not cont.disabled and labels.size() >= 2 and labels[1].text.strip_edges().is_empty():
		return "dialogue body is blank while Continue is enabled"
	var journal := _play.find_child("JournalList", true, false) as ItemList
	if journal == null:
		return "journal list is missing"
	var index := 0
	while index < journal.item_count:
		var row := journal.get_item_text(index).strip_edges()
		var journal_problem := _marker_problem(row)
		if journal_problem != "":
			return journal_problem
		if _date_only.search(row) != null:
			return "journal entry has no text: %s" % row
		index += 1
	var facts := _play.find_child("FactList", true, false) as ItemList
	if facts == null:
		return "fact list is missing"
	var fact_index := 0
	while fact_index < facts.item_count:
		var fact_row := facts.get_item_text(fact_index)
		var fact_problem := _panel_row_problem(fact_row)
		if fact_problem != "":
			return fact_problem
		fact_index += 1
	return ""


func _marker_problem(text: String) -> String:
	var marker := text.find("{?")
	if marker >= 0:
		return "missing value \"%s\"" % _snippet(text, marker)
	var empty := text.find("{}")
	if empty >= 0:
		return "empty interpolation \"%s\"" % _snippet(text, empty)
	return ""


func _panel_row_problem(row: String) -> String:
	var marker := _marker_problem(row)
	if marker != "":
		return marker
	var split_at := row.rfind(" = ")
	if split_at >= 0:
		var value := row.substr(split_at + 3).strip_edges()
		if value.is_empty():
			return "blank panel value \"%s\"" % row.strip_edges()
		return ""
	if row.begins_with("quest ") or row.begins_with("stage ") or row.begins_with("status "):
		var rest := row.substr(row.find(" ") + 1).strip_edges()
		if rest.is_empty():
			return "blank panel value \"%s\"" % row.strip_edges()
		return ""
	if row.begins_with("slot "):
		var parts := row.split(" — ")
		for part in parts:
			if part.strip_edges().is_empty():
				return "blank panel value \"%s\"" % row.strip_edges()
	return ""


func _layout_problem() -> String:
	var viewport := _play.get_viewport().get_visible_rect()
	var view_size := Vector2i(viewport.size)
	if absi(view_size.x - _width) > 1 or absi(view_size.y - _height) > 1:
		return "viewport is %s" % viewport.size
	var size_delta := (_play.size - Vector2(_width, _height)).abs()
	if size_delta.x > 1.0 or size_delta.y > 1.0:
		return "playtest size is %s" % _play.size
	if not viewport.grow(1.0).encloses(_play.get_global_rect()):
		return "playtest root %s outside %s" % [_play.get_global_rect(), viewport]
	for node_name in _panels:
		var panel := _play.find_child(node_name, true, false) as Control
		if panel == null:
			return "missing panel %s" % node_name
		var rect := panel.get_global_rect()
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			return "%s has no size %s" % [node_name, rect]
		if not viewport.grow(1.0).encloses(rect):
			return "%s %s outside %s" % [node_name, rect, viewport]
	for node in _play.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or not button.is_visible_in_tree():
			continue
		var button_rect := button.get_global_rect()
		if button_rect.size.x <= 1.0 or button_rect.size.y <= 1.0:
			continue
		if not viewport.grow(1.0).encloses(button_rect):
			return "button \"%s\" %s outside %s" % [button.text, button_rect, viewport]
	return ""


func _save_shot(scenario_id: String, step: String) -> void:
	var file_name := "%s_%s.png" % [scenario_id, step]
	for shot in _shots:
		if String(shot["file"]) == file_name:
			_fail(scenario_id, step, "duplicate screenshot %s" % file_name)
			return
	var image := _play.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_fail(scenario_id, step, "screenshot is empty")
		return
	var bright := _brightest(image)
	if bright < 15:
		_fail(scenario_id, step, "screenshot is blank")
	if absi(image.get_width() - _width) > 1 or absi(image.get_height() - _height) > 1:
		_fail(scenario_id, step, "screenshot is %dx%d" % [image.get_width(), image.get_height()])
	var path := _out.path_join(file_name)
	var err := image.save_png(path)
	if err != OK:
		_fail(scenario_id, step, "could not save %s" % file_name)
		return
	var labels := _dialogue_labels()
	var speaker := ""
	var line := ""
	if labels.size() >= 2:
		speaker = labels[0].text
		line = labels[1].text
	_shots.append({
		"file": file_name,
		"scenario": scenario_id,
		"step": step,
		"speaker": speaker,
		"line": line,
		"status": _status_text(),
	})


func _brightest(image: Image) -> int:
	var brightest := 0
	var y := 0
	while y < image.get_height():
		var x := 0
		while x < image.get_width():
			var color := image.get_pixel(x, y)
			var level := int(maxf(color.r, maxf(color.g, color.b)) * 255.0)
			if level > brightest:
				brightest = level
			if brightest > 40:
				return brightest
			x += 48
		y += 48
	return brightest


func _visible_blob() -> String:
	var parts := PackedStringArray()
	parts.append(_status_text())
	var labels := _dialogue_labels()
	for label in labels:
		parts.append(label.text)
	for node in _play.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null:
			parts.append(button.text)
	for list_name in ["JournalList", "FactList"]:
		var list := _play.find_child(list_name, true, false) as ItemList
		if list == null:
			continue
		var index := 0
		while index < list.item_count:
			parts.append(list.get_item_text(index))
			index += 1
	return "\n".join(parts)


func _dialogue_labels() -> Array[Label]:
	var found: Array[Label] = []
	var dialogue := _play.find_child("Dialogue", true, false) as VBoxContainer
	if dialogue == null:
		return found
	for child in dialogue.get_children():
		var label := child as Label
		if label != null:
			found.append(label)
	return found


func _status_text() -> String:
	var status := _play.find_child("StatusLine", true, false) as Label
	if status == null:
		return ""
	return status.text


func _snippet(text: String, at: int) -> String:
	var from := maxi(at - 24, 0)
	var to := mini(at + 24, text.length())
	return text.substr(from, to - from).replace("\n", " ")


func _name_ok(value: String) -> bool:
	if value.is_empty():
		return false
	var index := 0
	while index < value.length():
		var ch := value.unicode_at(index)
		var ok := (ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or ch == 45 or ch == 95
		if not ok:
			return false
		index += 1
	return true


func _fail(scenario_id: String, step: String, message: String) -> void:
	_failures.append({"scenario": scenario_id, "step": step, "message": message})
	print("visual-playtest FAIL: %s %s: %s" % [scenario_id, step, message])


func _write_gallery() -> void:
	var html := "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>Visual playtest</title>\n<style>\nbody{font-family:sans-serif;margin:24px;background:#16181d;color:#e8e6e3;}\nimg{max-width:100%;border:1px solid #333;}\n.fail{color:#ffb4a8;}\nh2{margin-top:2rem;}\n</style>\n</head>\n<body>\n<h1>Visual playtest</h1>\n"
	var md := "# Visual playtest\n\n"
	if _failures.is_empty():
		html += "<p>Result: ok</p>\n"
		md += "Result: ok\n"
	else:
		html += "<p class=\"fail\">Result: failed</p>\n<ul class=\"fail\">\n"
		md += "Result: failed\n\n"
		for row in _failures:
			var failure := "%s %s: %s" % [String(row["scenario"]), String(row["step"]), String(row["message"])]
			html += "<li>%s</li>\n" % _esc(failure)
			md += "- %s\n" % failure
		html += "</ul>\n"
	var current := ""
	for shot in _shots:
		var scenario_id := String(shot["scenario"])
		var step := String(shot["step"])
		var file_name := String(shot["file"])
		var speaker := String(shot["speaker"])
		var line := String(shot["line"])
		var status := String(shot["status"])
		if scenario_id != current:
			current = scenario_id
			html += "<h2>%s</h2>\n" % _esc(scenario_id)
			md += "\n## %s\n" % scenario_id
		html += "<h3>%s</h3>\n<p>%s</p>\n<p>%s</p>\n<p>%s</p>\n<img src=\"%s\" alt=\"%s %s\">\n" % [
			_esc(step),
			_esc(status),
			_esc(speaker),
			_esc(line),
			_esc(file_name),
			_esc(scenario_id),
			_esc(step),
		]
		md += "\n### %s\n\n%s\n\n%s: %s\n\n![%s %s](%s)\n" % [step, status, speaker, line, scenario_id, step, file_name]
	html += "</body>\n</html>\n"
	_write_text(_out.path_join("index.html"), html)
	_write_text(_out.path_join("index.md"), md)


func _write_report() -> void:
	var files: Array = []
	for shot in _shots:
		files.append(String(shot["file"]))
	var rows: Array = []
	for row in _failures:
		rows.append({
			"scenario": String(row["scenario"]),
			"step": String(row["step"]),
			"message": String(row["message"]),
		})
	var report := {"ok": rows.is_empty(), "failures": rows, "screenshots": files}
	var body := JSON.stringify(report, "  ")
	if body.is_empty():
		body = "{\"ok\":false,\"failures\":[{\"scenario\":\"report\",\"step\":\"write\",\"message\":\"could not encode the report\"}]}"
		_fail("report", "write", "could not encode the report")
	_write_text(_out.path_join("report.json"), body + "\n")


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("visual-playtest FAIL: report write: could not write %s" % path)
		_failures.append({"scenario": "report", "step": "write", "message": "could not write %s" % path})
		return
	file.store_string(text)


func _esc(text: String) -> String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
