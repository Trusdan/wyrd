class_name WyrdPotGolden
extends RefCounted

## Gullhaven POT golden.
##
## @experimental
## The expected file is the `pot` command's output for the Gullhaven manifest.


const MANIFEST := "example/content/gullhaven/harbor.wyrdmanifest.tres"
const EXPECTED := "res://tests/golden/pot/gullhaven.pot"


static func write_expected() -> int:
	DirAccess.make_dir_recursive_absolute("res://tests/golden/pot")
	var file := FileAccess.open(EXPECTED, FileAccess.WRITE)
	file.store_string(render())
	return 1


static func render() -> String:
	var result: Dictionary = WyrdCli.execute(PackedStringArray(["pot", "--manifest", MANIFEST]))
	return str(result["output"])
