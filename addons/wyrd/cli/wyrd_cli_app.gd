class_name WyrdCli
extends RefCounted

const _Runtime := preload("res://addons/wyrd/runtime/wyrd_runtime.gd")

## Text produced by the command-line entry.
##
## @experimental
## Each sub-command is reported as not implemented. The future [code]test[/code] command runs
## content scenarios. Engine unit tests stay on GUT.

const COMMANDS: PackedStringArray = ["check", "test", "tag-lines", "export-json"]


static func version_line() -> String:
	return "wyrd %s" % _Runtime.read_version()


static func command_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for command in COMMANDS:
		lines.append("%s: not implemented" % command)
	return lines


static func render() -> String:
	var lines := PackedStringArray()
	lines.append(version_line())
	lines.append_array(command_lines())
	return "\n".join(lines) + "\n"
