class_name WyrdContentManifest
extends Resource

## One content pack: the files the linker compiles together.
##
## [member pack_id] is the pack name used by [code]requires: [pack.<id>][/code].
## [member files] are [code]res://[/code] or project-relative [code].wyrd[/code] paths.
## [member language_version] is the pack's [code]language[/code] header. This slice is 1.
## Saved content hashes belong to the runtime load path, not this resource.

@export var pack_id: StringName = &""
@export var files: PackedStringArray = PackedStringArray()
@export var language_version: int = 1
