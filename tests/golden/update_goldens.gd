extends SceneTree

## Regenerates tests/golden/expected. Not a GUT test and not run from CI.


func _init() -> void:
	var count := WyrdGolden.write_expected()
	var conditions := WyrdConditionGolden.write_expected()
	var statements := WyrdStmtGolden.write_expected()
	print("Updated %d golden files, %d condition files, and %d statement files." % [count, conditions, statements])
	quit(0)
