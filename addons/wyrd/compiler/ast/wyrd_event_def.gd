class_name WyrdEventDef
extends RefCounted

## One declared world event.
##
## @experimental
## [member fields] entries are [code]name[/code] and [code]type[/code]
## ([code]bool[/code], [code]int[/code], [code]float[/code], [code]symbol[/code]).
## An empty field list is an invalidate-only event: the payload must be empty.

var name: String = ""
var fields: Array[Dictionary] = []
var line: int = 1
var col: int = 1


func field_type(field_name: String) -> StringName:
	for row in fields:
		if str(row.get("name", "")) == field_name:
			return StringName(str(row.get("type", "")))
	return &""
