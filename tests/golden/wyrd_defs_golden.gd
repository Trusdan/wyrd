class_name WyrdDefsGolden
extends RefCounted

## Gullhaven ctags golden.
##
## @experimental
## The expected file is the `defs` command's output for the Gullhaven manifest.


const MANIFEST := "example/content/gullhaven/harbor.wyrdmanifest.tres"
const EXPECTED := "res://tests/golden/defs/gullhaven.tags"


static func write_expected() -> int:
	DirAccess.make_dir_recursive_absolute("res://tests/golden/defs")
	var file := FileAccess.open(EXPECTED, FileAccess.WRITE)
	file.store_string(render())
	return 1


static func render() -> String:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["defs", "--manifest", MANIFEST]))
	return str(result["output"])
