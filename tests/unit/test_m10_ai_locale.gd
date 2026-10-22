extends GutTest

const _Exit := preload("res://tests/scenario/m10_gullhaven.gd")
const _IDS: Array[String] = ["a_leave", "sg02", "sg03", "sg04", "sg05", "sg_storm"]

var _locale := ""
var _added: Array[Translation] = []


func before_each() -> void:
	_locale = TranslationServer.get_locale()


func after_each() -> void:
	for item in _added:
		TranslationServer.remove_translation(item)
	_added.clear()
	TranslationServer.set_locale(_locale)


func test_missing_locale_shows_the_translated_authored_line() -> void:
	var opened := _Exit.new().boot("echo")
	var runtime: WyrdRuntime = opened["runtime"]
	var english := {}
	var translation := Translation.new()
	translation.locale = "de"
	for line_id in _IDS:
		var line_def := runtime.content().lines.get(line_id) as WyrdLineDef
		var text := str(runtime.resolve_line(line_def).get("text", ""))
		english[line_id] = text
		translation.add_message(text, "DE %s" % text, StringName(line_id))
	TranslationServer.add_translation(translation)
	_added.append(translation)
	TranslationServer.set_locale("de")
	runtime.trace.clear()
	for line_id in _IDS:
		var line_def := runtime.content().lines.get(line_id) as WyrdLineDef
		var resolved := runtime.resolve_line(line_def)
		var view := WyrdLineView.new()
		view.id = str(resolved["id"])
		view.text = str(resolved["text"])
		view.speaker = &"narrator"
		runtime.ai.present(view, view.id)
		assert_eq(view.text, "DE %s" % str(english[line_id]), line_id)
		assert_eq(String(view.text_source), "authored", line_id)
		var use := _use(runtime, line_id)
		assert_eq(str(use.get("reason", "")), "locale", line_id)
		assert_eq(str(use.get("source", "")), "authored", line_id)
	assert_eq(runtime.ai.pending_count(), 0)
	for item in runtime.trace.events:
		assert_ne(str((item as Dictionary).get("kind", "")), "ai_request")


func _use(runtime: WyrdRuntime, path: String) -> Dictionary:
	var found := {}
	for item in runtime.trace.events:
		var row: Dictionary = item
		if str(row.get("kind", "")) == "ai_use" and str(row.get("path", "")) == path:
			found = row
	return found
