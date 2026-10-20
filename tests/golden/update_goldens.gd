extends SceneTree

## Regenerates tests/golden/expected. Not a GUT test and not run from CI.


func _init() -> void:
	var count := WyrdGolden.write_expected()
	var conditions := WyrdConditionGolden.write_expected()
	var statements := WyrdStmtGolden.write_expected()
	var links := WyrdLinkGolden.write_expected()
	var roles := WyrdRoleGolden.write_expected()
	var pots := WyrdPotGolden.write_expected()
	print("Updated %d golden files, %d condition files, %d statement files, %d link files, %d role files, and %d pot files." % [count, conditions, statements, links, roles, pots])
	quit(0)
