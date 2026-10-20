extends GutTest

const _PREFIX := [
	"--headless",
	"--path",
	"${workspaceFolder}",
	"-s",
	"res://addons/wyrd/cli/wyrd_cli.gd",
	"--",
]


func test_tasks_match_the_sample_and_the_cli() -> void:
	var repo := FileAccess.get_file_as_string("res://.vscode/tasks.json")
	var sample := FileAccess.get_file_as_string("res://tools/vscode-wyrd/tasks.sample.json")
	assert_false(repo.is_empty())
	assert_eq(repo, sample)
	var parsed: Variant = JSON.parse_string(repo)
	var root: Dictionary = parsed
	var rows: Array = root["tasks"]
	assert_eq(rows.size(), 7)
	for row in rows:
		var task: Dictionary = row
		assert_eq(str(task["type"]), "process")
		assert_eq(str(task["command"]), "${config:wyrd.godotPath}")
		var args: Array = task["args"]
		assert_gt(args.size(), _PREFIX.size())
		for index in _PREFIX.size():
			assert_eq(str(args[index]), _PREFIX[index])
		var command := str(args[_PREFIX.size()])
		assert_true(WyrdCli.COMMANDS.has(command), command)
		var label := str(task["label"])
		if label == "Wyrd: check --watch (Gullhaven)":
			assert_eq(bool(task["isBackground"]), true)
			assert_eq(str(task["problemMatcher"]), "$wyrd-watch")
			assert_eq(command, "check")
			assert_eq(str(args[_PREFIX.size() + 1]), "--watch")
		elif label == "Wyrd: pot (Gullhaven)":
			assert_eq(str(task["problemMatcher"]), "$wyrd")
			assert_eq(command, "pot")
			var manifest_at := args.find("--manifest")
			assert_gt(manifest_at, 0)
			assert_eq(str(args[manifest_at + 1]), "example/content/gullhaven/harbor.wyrdmanifest.tres")
			assert_eq(str(args[manifest_at + 2]), "--out")
			assert_eq(str(args[manifest_at + 3]), "wyrd.pot")
		elif label == "Wyrd: defs (Gullhaven)":
			assert_eq(str(task["problemMatcher"]), "$wyrd")
			assert_eq(command, "defs")
			var defs_manifest_at := args.find("--manifest")
			assert_gt(defs_manifest_at, 0)
			assert_eq(str(args[defs_manifest_at + 1]), "example/content/gullhaven/harbor.wyrdmanifest.tres")
			assert_eq(str(args[defs_manifest_at + 2]), "--out")
			assert_eq(str(args[defs_manifest_at + 3]), "tags")
		elif label.begins_with("Wyrd: check"):
			assert_eq(str(task["problemMatcher"]), "$wyrd")
		else:
			var matcher: Array = task["problemMatcher"]
			assert_eq(matcher.size(), 0)


func test_godot_path_setting_defaults_to_godot() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/vscode-wyrd/package.json"))
	var root: Dictionary = parsed
	var contributes: Dictionary = root["contributes"]
	var configuration: Dictionary = contributes["configuration"]
	var properties: Dictionary = configuration["properties"]
	var setting: Dictionary = properties["wyrd.godotPath"]
	assert_eq(str(setting["type"]), "string")
	assert_eq(str(setting["default"]), "godot")
	assert_eq(str(setting["description"]), "Godot 4.7 executable used by the Wyrd tasks")
