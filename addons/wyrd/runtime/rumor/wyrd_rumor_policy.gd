class_name WyrdRumorPolicy
extends RefCounted

## One precise-mode rumor rule. The host registers it. It is not saved.
##
## @experimental
## [member kinds] are directed relationship kinds. [member max_hops] is how many
## steps the claim may travel from an origin. An empty [member verbs] list
## matches every deed verb. [member pass_chance] is the seeded chance that a
## hop is offered. [code]1[/code] always offers it. [code]0[/code] never does.


var id: StringName = &""
var kinds: PackedStringArray = PackedStringArray()
var max_hops: int = 1
var verbs: PackedStringArray = PackedStringArray()
var pass_chance: float = 1.0
