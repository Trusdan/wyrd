class_name WyrdRng
extends RefCounted

## Seeded PRNG wrapper over [RandomNumberGenerator].
##
## @experimental
## Each instance has its own seed, so tests do not share the engine RNG.
## Godot documents that generator's algorithm as an implementation detail, so a locked
## sequence in the unit tests is valid for the patch in [code]tools/pins.env[/code].
## An in-script PCG32 is deferred until a Godot upgrade would change those sequences.

var _generator: RandomNumberGenerator


func _init(seed_value: int = 0) -> void:
	_generator = RandomNumberGenerator.new()
	_generator.seed = seed_value


func get_seed() -> int:
	return _generator.seed


func set_seed(seed_value: int) -> void:
	_generator.seed = seed_value


func randi() -> int:
	return _generator.randi()


func randf() -> float:
	return _generator.randf()


func randi_range(from_value: int, to_value: int) -> int:
	return _generator.randi_range(from_value, to_value)


func randf_range(from_value: float, to_value: float) -> float:
	return _generator.randf_range(from_value, to_value)
