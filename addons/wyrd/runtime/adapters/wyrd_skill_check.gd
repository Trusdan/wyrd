class_name WyrdSkillCheck
extends RefCounted

## One skill check handed to the host.
##
## @experimental
## Wyrd attaches no meaning to [member skill], [member args], or [member roll].
## The host decides pass or fail and may ignore [member roll]. [member roll] is
## in [code][0, 1)[/code].

var skill: StringName = &""
var args: Dictionary = {}
var scene_id: String = ""
var choice_id: String = ""
var roll: float = 0.0
