extends SceneTree

const _Cli := preload("res://addons/wyrd/cli/wyrd_cli_app.gd")

## Command-line entry. Prints the version and marks each sub-command not implemented.

func _init() -> void:
	print(_Cli.render().strip_edges())
	quit(0)
