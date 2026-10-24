class_name WyrdDocumentView
extends RefCounted

## One opened readable document.
##
## [member pages] leaves out a page that has no visible paragraph. Each page is
## an array of [code]{id, text}[/code]. [member title] and each paragraph are
## translated with the line id, the same way dialogue is.

var id: StringName = &""
var copy_id: String = ""
var reader: StringName = &""
var title: String = ""
var frozen: bool = false
var first_time: bool = false
var tags: PackedStringArray = PackedStringArray()
var meta: Dictionary = {}
var pages: Array = []
