extends GutTest

const _Facade := preload("res://addons/wyrd/runtime/wyrd.gd")


func test_runtime_version_matches_file() -> void:
	var file := FileAccess.open("res://addons/wyrd/VERSION", FileAccess.READ)
	assert_not_null(file)
	var text := file.get_as_text().strip_edges()
	assert_eq(text, "0.1.0-s3")
	var runtime := WyrdRuntime.new()
	assert_eq(runtime.get_version(), text)
	assert_eq(WyrdRuntime.read_version(), text)


func test_facade_version_matches_runtime() -> void:
	var facade := _Facade.new() as Node
	assert_eq(facade.get_version(), WyrdRuntime.new().get_version())
	facade.free()
