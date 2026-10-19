class_name WyrdChoiceView
extends RefCounted

## One choice the host should show.
##
## @experimental
## A choice whose condition is false is omitted. [member enabled] is false when
## [code]show_disabled_when[/code] is true, and [member reason] is the quoted reason.
## [member check] is the skill id, empty when the choice has no check.
## [member check_args] is evaluated when the choice is presented. A hidden or
## disabled choice never calls the skill adapter. [member index] is the position
## in this presented list. [method WyrdSceneRunner.choose] uses that index.

var index: int = 0
var id: String = ""
var text: String = ""
var enabled: bool = true
var reason: String = ""
var tags: PackedStringArray = PackedStringArray()
var check: StringName = &""
var check_args: Dictionary = {}
