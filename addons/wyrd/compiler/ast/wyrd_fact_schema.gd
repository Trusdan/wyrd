class_name WyrdFactSchema
extends RefCounted

## Plain fact schema for one file.
##
## @experimental
## A key is declared once. A stored key and a resolved key that unify are
## [code]E_FACTS_DUPLICATE[/code], including a concrete key under a [code]{id}[/code] pattern.

var entries: Array[WyrdFact] = []


func add(fact: WyrdFact, diagnostics: WyrdDiagnostics, source_path: String) -> void:
	for prior in entries:
		if _conflicts(prior, fact):
			diagnostics.add(
				WyrdDiagnostic.E_FACTS_DUPLICATE,
				_message(prior, fact),
				source_path,
				fact.line,
				fact.col
			)
			break
	entries.append(fact)


func _conflicts(prior: WyrdFact, fact: WyrdFact) -> bool:
	if prior.segments.size() != fact.segments.size() or prior.segments.is_empty():
		return false
	for i in prior.segments.size():
		var left := prior.segments[i]
		var right := fact.segments[i]
		if left.begins_with("{") or right.begins_with("{"):
			continue
		if left != right:
			return false
	return true


func _message(prior: WyrdFact, fact: WyrdFact) -> String:
	if prior.key == fact.key:
		if prior.origin != fact.origin:
			return "fact key \"%s\" is both stored and resolved" % fact.key
		return "duplicate fact key \"%s\"" % fact.key
	if prior.origin != fact.origin:
		return "fact keys \"%s\" and \"%s\" are both stored and resolved" % [prior.key, fact.key]
	return "fact keys \"%s\" and \"%s\" overlap" % [prior.key, fact.key]
