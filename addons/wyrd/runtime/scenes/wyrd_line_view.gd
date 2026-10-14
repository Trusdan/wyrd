class_name WyrdLineView
extends RefCounted

## One line ready for the host to show.
##
## @experimental
## [member text] is always set. [member audio] comes from [code]line_audio[/code]
## and may be null. Audio never replaces the text and never advances the line.

var id: String = ""
var speaker: StringName = &""
var display_name: String = ""
var text: String = ""
var tags: PackedStringArray = PackedStringArray()
var audio: Variant = null
