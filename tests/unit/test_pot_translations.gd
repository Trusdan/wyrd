extends GutTest


func test_two_translations_for_one_locale_both_resolve() -> void:
	var previous := TranslationServer.get_locale()
	var wyrd := Translation.new()
	wyrd.locale = "wyrdtest"
	wyrd.add_message("The tide is in.", "La maree est haute.", &"ferry_hello")
	var game := Translation.new()
	game.locale = "wyrdtest"
	game.add_message("Save", "Enregistrer")
	TranslationServer.add_translation(wyrd)
	TranslationServer.add_translation(game)
	TranslationServer.set_locale("wyrdtest")
	var with_context := String(TranslationServer.translate("The tide is in.", &"ferry_hello"))
	var plain := String(TranslationServer.translate("Save"))
	var node := WyrdExprNode.new()
	node.kind = &"text"
	node.text = "The tide is in."
	var rendered := WyrdText.new().render(node, "ferry_hello")
	TranslationServer.remove_translation(wyrd)
	TranslationServer.remove_translation(game)
	TranslationServer.set_locale(previous)
	assert_eq(with_context, "La maree est haute.")
	assert_eq(plain, "Enregistrer")
	assert_eq(rendered, "La maree est haute.")
	assert_eq(TranslationServer.get_locale(), previous)
