class_name WyrdLinkedPack
extends RefCounted

## Plain data for one linked content pack.
##
## @experimental
## [member units] keeps sorted file records: [code]path[/code], [code]text[/code],
## [code]hash[/code], and [code]file[/code] ([WyrdFileDef]). No callables.

var pack_id: String = ""
var language_version: int = 1
var schema: WyrdFactSchema
var units: Array = []
var topics: PackedStringArray = PackedStringArray()
var xref: WyrdFactXref
