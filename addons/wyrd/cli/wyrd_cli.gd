extends SceneTree

const _Cli := preload("res://addons/wyrd/cli/wyrd_cli_app.gd")

## Command-line entry. With no arguments, prints the version and command list.
## [code]check[/code] compiles [code].wyrd[/code] files and prints diagnostics.

func _init() -> void:
	var result: Dictionary = _Cli.execute(OS.get_cmdline_user_args())
	var output := str(result["output"])
	if not output.is_empty():
		print(output.strip_edges())
	quit(int(result["exit_code"]))
