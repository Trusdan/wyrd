class_name WyrdRuntime
extends RefCounted

## One narrative runtime. Tests and the future playtest console each keep their own instance.
##
## @experimental
## S0 exposes the version only. Facts, scenes, and save data are later milestones.

const VERSION_PATH: String = "res://addons/wyrd/VERSION"


func get_version() -> String:
	return WyrdRuntime.read_version()


static func read_version() -> String:
	var file := FileAccess.open(VERSION_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing version file at %s." % VERSION_PATH)
		return ""
	return file.get_as_text().strip_edges()
