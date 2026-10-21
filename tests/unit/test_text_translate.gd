extends GutTest

const _MANIFEST := "res://example/content/gullhaven/harbor.wyrdmanifest.tres"

var _locale := ""
var _added: Array = []


func before_each() -> void:
	_locale = TranslationServer.get_locale()
	_added.clear()


func after_each() -> void:
	for item in _added:
		TranslationServer.remove_translation(item)
	TranslationServer.set_locale(_locale)


func test_plain_line_translates_the_rendered_text() -> void:
	var runtime := _boot(_LINES)
	var line := _prose(runtime, "plain")
	var text := _renderer(runtime)
	assert_eq(text.render(line, "plain"), "The tide is in.")
	_translate("fr", "The tide is in.", "La maree est haute.", "plain")
	assert_eq(text.render(line, "plain"), "La maree est haute.")
	assert_eq(text.compile_count, 0)
	assert_eq(_rows(runtime, "text_translate").size(), 0)


func test_span_lines_without_a_translation_match_today() -> void:
	var runtime := _boot_manifest()
	var text := _renderer(runtime)
	var count := 0
	for row in _span_rows(runtime):
		count += 1
		var source := WyrdLineDef.source_of(row["prose"])
		var rebuilt := _recompile(source, runtime.content_schema())
		assert_false(rebuilt["errors"], rebuilt["format"])
		var today := text.render(row["prose"], str(row["id"]))
		var again := text.render(rebuilt["node"], str(row["id"]))
		assert_eq(again, today, str(row["id"]))
	assert_eq(count, 7)
	assert_eq(text.compile_count, 0)
	assert_eq(_rows(runtime, "text_translate").size(), 0)


func test_reordered_placeholders_fill_in_translation_order() -> void:
	var runtime := _named(3)
	_translate("fr", "{player.label} owes {player.coins}.", "{player.coins} from {player.label}", "toll_line")
	assert_eq(_renderer(runtime).render(_prose(runtime, "toll_line"), "toll_line"), "3 from mara")


func test_translated_if_follows_the_fact() -> void:
	var runtime := _named(3)
	var source := "{if player.coins > 0}paid {player.label}{else}owes {player.label}{end}"
	var template := "{if player.coins > 0}oui {player.label}{else}non {player.label}{end}"
	_translate("fr", source, template, "toll_if")
	var text := _renderer(runtime)
	assert_eq(text.render(_prose(runtime, "toll_if"), "toll_if"), "oui mara")
	runtime.facts.set(&"player.coins", 0)
	assert_eq(text.render(_prose(runtime, "toll_if"), "toll_if"), "non mara")


func test_translated_variants_span_is_removed() -> void:
	var runtime := _boot(_VARIANTS)
	_translate("fr", "Open. {holder(ferry)|variants}", "Ici. {holder(ferry)|variants}", "dock_voice")
	assert_eq(_renderer(runtime).render(_prose(runtime, "dock_voice"), "dock_voice"), "Ici.")


func test_missing_value_in_a_translation_keeps_the_marker() -> void:
	var runtime := _boot(_LINES)
	runtime.facts.set(&"player.coins", 3)
	_translate("fr", "{player.label} owes {player.coins}.", "{player.label} doit {player.coins}.", "toll_line")
	assert_eq(_renderer(runtime).render(_prose(runtime, "toll_line"), "toll_line"), "{?player.label} doit 3.")


func test_placeholder_mismatch_falls_back() -> void:
	var runtime := _named(3)
	runtime.trace.enabled = true
	var template := "{player.label} owes {player.coins}."
	_translate("fr", template, "{player.label} only", "toll_line")
	_translate("fr", template, "{player.label} owes {player.coins} and {player.clearance}.", "toll_extra")
	_translate("fr", template, "{ferry.toll_coins} owes {player.coins}.", "toll_renamed")
	var text := _renderer(runtime)
	assert_eq(text.render(_prose(runtime, "toll_line"), "toll_line"), "mara owes 3.")
	assert_eq(text.render(_prose(runtime, "toll_line"), "toll_line"), "mara owes 3.")
	assert_eq(text.render(_prose(runtime, "toll_extra"), "toll_extra"), "mara owes 3.")
	assert_eq(text.render(_prose(runtime, "toll_renamed"), "toll_renamed"), "mara owes 3.")
	assert_push_warning_count(3)
	assert_eq(_rows(runtime, "text_translate"), [
		_trace_row("toll_line", false, "placeholder_mismatch"),
		_trace_row("toll_line", false, "placeholder_mismatch"),
		_trace_row("toll_extra", false, "placeholder_mismatch"),
		_trace_row("toll_renamed", false, "placeholder_mismatch"),
	])


func test_compile_error_falls_back() -> void:
	var runtime := _named(3)
	runtime.trace.enabled = true
	_translate("fr", "{player.label} owes {player.coins}.", "{if player.coins > 0}yes", "toll_line")
	assert_eq(_renderer(runtime).render(_prose(runtime, "toll_line"), "toll_line"), "mara owes 3.")
	assert_push_warning("compile_error")
	assert_eq(_rows(runtime, "text_translate"), [
		_trace_row("toll_line", false, "compile_error"),
	])


func test_success_traces_once_per_render() -> void:
	var runtime := _named(3)
	runtime.trace.enabled = true
	_translate("fr", "{player.label} owes {player.coins}.", "{player.coins} from {player.label}", "toll_line")
	var text := _renderer(runtime)
	text.render(_prose(runtime, "toll_line"), "toll_line")
	text.render(_prose(runtime, "toll_line"), "toll_line")
	text.render(_prose(runtime, "plain"), "plain")
	assert_eq(_rows(runtime, "text_translate"), [
		_trace_row("toll_line", true, "translated"),
		_trace_row("toll_line", true, "translated"),
	])


func test_cache_compiles_once_until_the_translation_or_locale_changes() -> void:
	var runtime := _named(3)
	var template := "{player.label} owes {player.coins}."
	var translation := _translate("fr", template, "{player.coins} from {player.label}", "toll_line")
	var text := _renderer(runtime)
	var line := _prose(runtime, "toll_line")
	assert_eq(text.render(line, "toll_line"), "3 from mara")
	assert_eq(text.render(line, "toll_line"), "3 from mara")
	assert_eq(text.compile_count, 1)
	translation.add_message(template, "{player.label} doit {player.coins}.", &"toll_line")
	assert_eq(text.render(line, "toll_line"), "mara doit 3.")
	assert_eq(text.compile_count, 2)
	var other := Translation.new()
	other.locale = "de"
	other.add_message(template, "{player.coins} bei {player.label}", &"toll_line")
	TranslationServer.add_translation(other)
	_added.append(other)
	TranslationServer.set_locale("de")
	assert_eq(text.render(line, "toll_line"), "3 bei mara")
	assert_eq(text.compile_count, 3)


func test_trace_filter_keeps_the_line_id_and_drops_unrelated_prefixes() -> void:
	var runtime := _named(3)
	runtime.trace.enabled = true
	runtime.trace.prefix = "toll"
	_translate("fr", "{player.label} owes {player.coins}.", "{player.coins} from {player.label}", "toll_line")
	var logger := _Log.new()
	OS.add_logger(logger)
	_renderer(runtime).render(_prose(runtime, "toll_line"), "toll_line")
	assert_eq(_rows(runtime, "text_translate").size(), 1)
	assert_true(_logged(logger, "wyrd text_translate line=toll_line locale=fr ok=true reason=translated"))
	runtime.trace.clear()
	logger.lines.clear()
	runtime.trace.prefix = "other"
	_renderer(runtime).render(_prose(runtime, "toll_line"), "toll_line")
	assert_eq(_rows(runtime, "text_translate").size(), 0)
	assert_false(_logged(logger, "text_translate"))
	runtime.trace.enabled = false
	runtime.trace.prefix = ""
	logger.lines.clear()
	_renderer(runtime).render(_prose(runtime, "toll_line"), "toll_line")
	OS.remove_logger(logger)
	assert_eq(_rows(runtime, "text_translate").size(), 0)
	assert_false(_logged(logger, "text_translate"))


func test_replay_skips_text_translate() -> void:
	var runtime := _boot(_LINES)
	runtime.trace.enabled = true
	WyrdTrace.replay(runtime, [
		{"key": "toll_line", "kind": "text_translate", "ok": true, "path": "fr", "reason": "translated"},
		{"kind": "tick", "minutes": 1},
	])
	assert_eq(runtime.now_minutes(), 1)
	assert_eq(_rows(runtime, "text_translate").size(), 0)


func test_live_paragraph_translates_by_template() -> void:
	var runtime := _docs()
	runtime.facts.set(&"player.label", &"mara")
	runtime.facts.set(&"player.coins", 3)
	_translate("fr", "{player.label} owes {player.coins}.", "{player.coins} from {player.label}", "note_body")
	var opened := runtime.documents.open(&"note", "", &"player")
	assert_eq(opened.pages[0][0]["text"], "3 from mara")


func test_frozen_copy_binds_recorded_values_by_name() -> void:
	var runtime := _docs()
	runtime.facts.set(&"player.label", &"mara")
	runtime.facts.set(&"player.coins", 3)
	assert_true(runtime.documents.create_copy(&"letter", "kept"))
	runtime.facts.set(&"player.label", &"ned")
	runtime.facts.set(&"player.coins", 9)
	_translate("fr", "{player.label} owes {player.coins}.", "{player.coins} from {player.label}", "letter_body")
	var opened := runtime.documents.open(&"letter", "kept", &"player")
	assert_eq(opened.pages[0][0]["text"], "3 from mara")


func test_frozen_shape_falls_back_to_the_record() -> void:
	var runtime := _docs()
	runtime.trace.enabled = true
	runtime.facts.set(&"player.coins", 0)
	assert_true(runtime.documents.create_copy(&"gate", "kept"))
	var template := "{if player.coins > 0}{if player.coins > 1}rich{else}ok{end}{else}poor{end}"
	var swapped := "{if player.coins > 0}poor{else}{if player.coins > 1}rich{else}ok{end}{end}"
	_translate("fr", template, swapped, "gate_body")
	var opened := runtime.documents.open(&"gate", "kept", &"player")
	var again := runtime.documents.open(&"gate", "kept", &"player")
	assert_eq(opened.pages[0][0]["text"], "poor")
	assert_eq(again.pages[0][0]["text"], "poor")
	assert_push_warning_count(1)
	assert_eq(_rows(runtime, "text_translate"), [
		_trace_row("gate_body", false, "frozen_shape"),
		_trace_row("gate_body", false, "frozen_shape"),
	])


func test_journal_stores_the_translated_text() -> void:
	var runtime := _boot(_JOURNAL)
	runtime.facts.set(&"player.label", &"mara")
	runtime.facts.set(&"player.coins", 3)
	_translate("fr", "{player.label} owes {player.coins}.", "{player.coins} from {player.label}", "j_due")
	runtime.quests.start("toll")
	var journal: Array = runtime.quests.journal("toll")
	assert_eq(str(journal[0]["text"]), "3 from mara")


func test_save_round_trip_leaves_the_cache_out() -> void:
	var runtime := _named(3)
	var before := JSON.stringify(runtime.save_state())
	_translate("fr", "{player.label} owes {player.coins}.", "ZZZCACHE {player.coins} {player.label}", "toll_line")
	var text := _renderer(runtime)
	assert_eq(text.render(_prose(runtime, "toll_line"), "toll_line"), "ZZZCACHE 3 mara")
	var saved := runtime.save_state()
	assert_eq(JSON.stringify(saved), before)
	assert_false(JSON.stringify(saved).contains("ZZZCACHE"))
	assert_eq(int(saved.get("schema_version", 0)), 3)
	var loaded := _named(0)
	assert_true(loaded.load_state(saved).ok)
	assert_eq(loaded.facts.get(&"player.coins"), 3)
	assert_eq(loaded.facts.get(&"player.label"), "mara")


func test_literal_braces_round_trip_through_the_template() -> void:
	var runtime := _boot(_BRACES)
	runtime.facts.set(&"player.coins", 3)
	var plain := _prose(runtime, "plain")
	assert_eq(WyrdLineDef.template_of(plain), WyrdLineDef.source_of(plain))
	assert_eq(WyrdLineDef.source_of(plain), "The board lists the price as {two coins}}.")
	var price := _prose(runtime, "price")
	var template := WyrdLineDef.template_of(price)
	assert_eq(template, "The price is {{two coins}} for {player.coins}.")
	_translate("fr", template, "Le prix est {{deux pieces}} pour {player.coins}.", "price")
	assert_eq(_renderer(runtime).render(price, "price"), "Le prix est {deux pieces}} pour 3.")


func test_z_locale_changes_inside_one_test() -> void:
	TranslationServer.set_locale("wyrdprobe")
	assert_eq(TranslationServer.get_locale(), "wyrdprobe")


func test_zz_locale_is_restored_for_the_next_test() -> void:
	assert_ne(TranslationServer.get_locale(), "wyrdprobe")
	assert_eq(TranslationServer.get_locale(), _locale)


func _trace_row(line_id: String, ok: bool, reason: String) -> Dictionary:
	return {
		"key": line_id,
		"kind": "text_translate",
		"ok": ok,
		"path": "fr",
		"reason": reason,
	}


func _translate(locale: String, src: String, xlated: String, line_id: String) -> Translation:
	var translation := Translation.new()
	translation.locale = locale
	translation.add_message(src, xlated, StringName(line_id))
	TranslationServer.add_translation(translation)
	TranslationServer.set_locale(locale)
	_added.append(translation)
	return translation


func _renderer(runtime: WyrdRuntime) -> WyrdText:
	var text := WyrdText.new()
	text.runtime = runtime
	return text


func _rows(runtime: WyrdRuntime, kind: String) -> Array:
	var found: Array = []
	for item in runtime.trace.events:
		if item is Dictionary and str((item as Dictionary).get("kind", "")) == kind:
			found.append(item)
	return found


func _logged(logger: _Log, needle: String) -> bool:
	for line in logger.lines:
		if line.contains(needle):
			return true
	return false


func _prose(runtime: WyrdRuntime, line_id: String) -> WyrdExprNode:
	var found: Variant = runtime._content.lines.get(line_id, null)
	if found is WyrdLineDef:
		return (found as WyrdLineDef).prose
	return null


func _named(coins: int) -> WyrdRuntime:
	var runtime := _boot(_LINES)
	runtime.facts.set(&"player.label", &"mara")
	runtime.facts.set(&"player.coins", coins)
	return runtime


func _docs() -> WyrdRuntime:
	var runtime := _boot(_DOCS)
	var world := runtime.adapter(WyrdWorldAdapter) as WyrdFakeWorld
	world.add_entity(&"player", &"person", "traveler", PackedStringArray(), true)
	return runtime


func _boot(body: String) -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var path := "user://wyrd_text_translate_%d.wyrd" % body.hash()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body.strip_edges() + "\n")
	file.close()
	var manifest := WyrdContentManifest.new()
	manifest.pack_id = &"harbor"
	manifest.language_version = 1
	manifest.files = PackedStringArray([path])
	var report := runtime.load_content(manifest)
	assert_true(report.ok, report.diagnostics.format())
	runtime.start_new_game(5)
	return runtime


func _boot_manifest() -> WyrdRuntime:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var report := runtime.load_content(load(_MANIFEST))
	assert_true(report.ok, report.diagnostics.format())
	return runtime


func _span_rows(runtime: WyrdRuntime) -> Array:
	var found: Array = []
	var content: WyrdContent = runtime._content
	for quest_id in content.quests.keys():
		var quest: WyrdQuestDef = content.quests[quest_id]
		for stage in quest.stages:
			_span_stage(stage, found)
	for scene_id in content.scenes.keys():
		var scene: WyrdSceneDef = content.scenes[scene_id]
		for item in scene.items:
			if item.line_def != null:
				_span_line(item.line_def, found)
			if item.choice != null and WyrdLineDef.has_spans(item.choice.label):
				found.append({"id": item.choice.line_id, "prose": item.choice.label})
	for story_id in content.storylets.keys():
		var story: WyrdStoryletDef = content.storylets[story_id]
		for line_def in story.lines:
			_span_line(line_def, found)
	for doc_id in content.documents.keys():
		var document: WyrdDocumentDef = content.documents[doc_id]
		for page in document.pages:
			for paragraph in page["paragraphs"]:
				var prose: WyrdExprNode = paragraph["prose"]
				if WyrdLineDef.has_spans(prose):
					found.append({"id": str(paragraph["line_id"]), "prose": prose})
	return found


func _span_stage(stage: WyrdStageDef, found: Array) -> void:
	if stage == null:
		return
	for journal in stage.journals:
		_span_line(journal, found)
	for entry in stage.variants:
		var variant := entry as WyrdVariantDef
		if variant != null:
			_span_stage(variant.body, found)
	for item in stage.regions:
		var region := item as WyrdRegionDef
		if region == null:
			continue
		for child in region.stages:
			_span_stage(child, found)


func _span_line(line: WyrdLineDef, found: Array) -> void:
	if line == null:
		return
	if WyrdLineDef.has_spans(line.prose):
		found.append({"id": line.line_id, "prose": line.prose})
	for item in line.variants:
		_span_line(item as WyrdLineDef, found)


func _recompile(source: String, schema: WyrdFactSchema) -> Dictionary:
	var diagnostics := WyrdDiagnostics.new()
	var tokens := WyrdLexer.new().tokenize_prose(source, diagnostics)
	var node := WyrdInterp.new().compile_line(
		tokens,
		schema,
		diagnostics,
		"",
		WyrdCondition.CONTEXT_STORYLET,
		WyrdCondition.MINUTES_PER_DAY,
		WyrdSignatures.new()
	)
	return {"errors": diagnostics.has_errors(), "format": diagnostics.format(), "node": node}


const _LINES := """
language 1

facts
  player.label : symbol stored
  player.coins : int stored
  player.clearance : symbol stored
  ferry.toll_coins : int stored

scene room
  ferryman: The tide is in. #line:plain
  ferryman: {player.label} owes {player.coins}. #line:toll_line
  ferryman: {player.label} owes {player.coins}. #line:toll_extra
  ferryman: {player.label} owes {player.coins}. #line:toll_renamed
  ferryman: {if player.coins > 0}paid {player.label}{else}owes {player.label}{end} #line:toll_if
"""


const _VARIANTS := """
language 1

scene room
  ferryman: Open. {holder(ferry)|variants} #line:dock_voice
    variant ferry_master: The ferry master is here. #line:dock_voice_master
"""


const _JOURNAL := """
language 1

facts
  player.label : symbol stored
  player.coins : int stored

quest toll "Toll"
  start when false
  stage due
    journal: {player.label} owes {player.coins}. #line:j_due
    waits_until false
"""


const _DOCS := """
language 1

facts
  player.label : symbol stored
  player.coins : int stored

document note "Note" #line:note_title
  text: live
  page
    {player.label} owes {player.coins}. #line:note_body

document letter "Letter" #line:letter_title
  text: frozen
  page
    {player.label} owes {player.coins}. #line:letter_body

document gate "Gate" #line:gate_title
  text: frozen
  page
    {if player.coins > 0}{if player.coins > 1}rich{else}ok{end}{else}poor{end} #line:gate_body
"""


const _BRACES := """
language 1

facts
  player.coins : int stored

scene room
  ferryman: The board lists the price as {{two coins}}. #line:plain
  ferryman: The price is {{two coins}} for {player.coins}. #line:price
"""


class _Log extends Logger:
	var lines := PackedStringArray()

	func _log_message(message: String, _error: bool) -> void:
		lines.append(message)
