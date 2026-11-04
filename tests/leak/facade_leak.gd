extends SceneTree

## Creates a facade, frees it, and quits.
## Godot reports leftover instances and resources after this script returns.
## tools/leak_check.sh fails the process when that report is present.


const _Facade := preload("res://addons/wyrd/runtime/wyrd.gd")


func _init() -> void:
	_drop_facade()
	_drop_loaded()
	quit()


func _drop_facade() -> void:
	var node: Node = _Facade.new()
	node.free()


func _drop_loaded() -> void:
	var node: Node = _Facade.new()
	var manifest := load("res://tests/scenario/pack/sample.wyrdmanifest.tres") as WyrdContentManifest
	node.load_content(manifest)
	node.free()
