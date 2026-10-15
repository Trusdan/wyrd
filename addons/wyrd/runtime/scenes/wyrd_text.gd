class_name WyrdText
extends RefCounted

## Renders compiled prose and the default journal date.
##
## @experimental
## Interpolation runs at display time. A missing value renders as
## [code]{?<expr>}[/code], not an empty string. [code]0[/code] stays [code]0[/code].
## The whole line then goes through [method TranslationServer.translate]
## with the line id as context.
## The default date is [code]day N, HH:MM[/code] from game minutes, day 1 at
## minute 0, 1440 minutes per day. A host formatter replaces it for new text.

var runtime: WyrdRuntime


func render(node: WyrdExprNode, line_id: String) -> String:
	return _translate(_walk(node), line_id)


static func game_date(minutes: int) -> String:
	var span := maxi(minutes, 0)
	var day := int(span / 1440) + 1
	var rest := span % 1440
	return "day %d, %02d:%02d" % [day, int(rest / 60), rest % 60]


func _walk(node: WyrdExprNode) -> String:
	if node == null:
		return ""
	if node.kind == &"text":
		return node.text
	if node.kind == &"prose":
		var built := ""
		for kid in node.kids:
			built += _walk(kid)
		return built
	if node.kind == &"value" or node.kind == &"variants":
		return _insert(_eval(node.payload), node.payload)
	if node.kind == &"if":
		if _eval(node.payload) == true:
			return _walk(node.b)
		return _walk(node.c)
	return ""


func _eval(payload: Variant) -> Variant:
	if payload is WyrdCompiledCondition and runtime != null:
		return runtime.eval_value(payload)
	return null


func _insert(value: Variant, payload: Variant) -> String:
	if value == null:
		return _missing_marker(payload)
	return _show(value)


func _missing_marker(payload: Variant) -> String:
	var label := ""
	if payload is WyrdCompiledCondition:
		label = (payload as WyrdCompiledCondition).source_text.strip_edges()
	if label.is_empty():
		return "{?}"
	return "{?%s}" % label


func _show(value: Variant) -> String:
	if value == null:
		return _missing_marker(null)
	if value is bool:
		return "true" if value else "false"
	return str(value)


func _translate(message: String, line_id: String) -> String:
	if message.is_empty():
		return ""
	return String(TranslationServer.translate(message, StringName(line_id)))
