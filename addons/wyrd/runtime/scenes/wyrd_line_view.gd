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
## Role ids this speaker holds. A scene line lists quest slots passed into
## that scene. A bark lists world role bindings. Sorted.
## The host formats a name-plus-role label from these ids.
var roles: PackedStringArray = PackedStringArray()
var text: String = ""
## [code]authored[/code] or [code]ai[/code]. When it is [code]ai[/code], only
## [member text] differs from the authored line.
var text_source: StringName = &"authored"
var tags: PackedStringArray = PackedStringArray()
var audio: Variant = null
