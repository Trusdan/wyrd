extends SceneTree

## Regenerates tests/golden/expected. Not a GUT test and not run from CI.


func _init() -> void:
	var count := WyrdGolden.write_expected()
	var conditions := WyrdConditionGolden.write_expected()
	print("Updated %d golden files and %d condition files." % [count, conditions])
	quit(0)
