class_name WyrdCondition
extends RefCounted

## Compiles one condition or value expression to plain data.
##
## @experimental
## [constant CONTEXT_STORYLET] allows [code]chance[/code]. [constant CONTEXT_WAIT]
## rejects it, and rejects resolved facts invalidated [code]per_query[/code] or not at all
## ([code]E_WAIT_RESOLVER_MODE[/code]). [param event_fields] types [code]event.<field>[/code].
## [param minutes_per_day] defaults to 1440 until a calendar resource exists.
## [param expected] is used when [param require_bool] is false, so a value
## expression can be checked against a fact or argument type. Existing callers
## keep the bool default.

const CONTEXT_STORYLET: StringName = &"storylet_or_choice"
const CONTEXT_WAIT: StringName = &"wait_trigger_or_eligibility"
const MINUTES_PER_DAY := 1440

var ast: WyrdExprNode = null


func compile(
	text: String,
	schema: WyrdFactSchema,
	diagnostics: WyrdDiagnostics,
	source_path: String,
	line: int,
	col: int,
	context: StringName = CONTEXT_STORYLET,
	minutes_per_day: int = MINUTES_PER_DAY,
	signatures: WyrdSignatures = null,
	require_bool: bool = true,
	expected: StringName = &"",
	event_fields: Dictionary = {}
) -> WyrdCompiledCondition:
	if signatures == null:
		signatures = WyrdSignatures.new()
	var tokens := WyrdExprLexer.new().tokenize(text, source_path, line, col, diagnostics)
	ast = WyrdExprParser.new().parse(tokens, diagnostics, source_path)
	var checker := WyrdTypeChecker.new()
	checker.schema = schema
	checker.signatures = signatures
	checker.diagnostics = diagnostics
	checker.path = source_path
	checker.context = context
	checker.minutes_per_day = minutes_per_day
	checker.event_fields = event_fields
	var want := expected
	if require_bool:
		want = WyrdSignatures.T_BOOL
	checker.check(ast, want)
	var compiled := WyrdEmitter.new().emit(ast)
	compiled.reads = checker.reads
	compiled.specificity = specificity(ast)
	compiled.uses_chance = checker.uses_chance
	compiled.source_span = {
		"col": ast.col,
		"end_col": ast.end_col,
		"end_line": ast.end_line,
		"line": ast.line,
	}
	return compiled


static func specificity(node: WyrdExprNode) -> int:
	if node == null or node.kind == &"error":
		return 0
	if node.kind == &"binary" and node.text == "and":
		return specificity(node.a) + specificity(node.b)
	if node.kind == &"binary" and node.text == "or":
		return 1
	if node.kind == &"unary" and node.text == "not":
		return 1
	return 1
