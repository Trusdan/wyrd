extends SceneTree

## Regenerates tests/golden/expected. Not a GUT test and not run from CI.


func _init() -> void:
	var count := WyrdGolden.write_expected()
	var conditions := WyrdConditionGolden.write_expected()
	var statements := WyrdStmtGolden.write_expected()
	var links := WyrdLinkGolden.write_expected()
	print("Updated %d golden files, %d condition files, %d statement files, and %d link files." % [count, conditions, statements, links])
	quit(0)
