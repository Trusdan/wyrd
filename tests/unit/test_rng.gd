extends GutTest

# Locked RandomNumberGenerator sequence for seed 1 on Godot 4.7.2.
# Update this in the same PR that changes the pin in tools/pins.env.
const SEED_1_RANDI: Array[int] = [1811587497, 683407368, 2033395789, 2375931748, 2873319489]


func test_same_seed_matches_across_instances() -> void:
	var first := WyrdRng.new(1)
	var second := WyrdRng.new(1)
	for _i in 8:
		assert_eq(first.randi(), second.randi())
	first.set_seed(1)
	second.set_seed(1)
	for _i in 4:
		assert_eq(first.randf(), second.randf())


func test_seed_1_matches_locked_sequence() -> void:
	var rng := WyrdRng.new(1)
	for expected in SEED_1_RANDI:
		assert_eq(rng.randi(), expected)


func test_reseed_repeats_the_sequence() -> void:
	var rng := WyrdRng.new(99)
	var first: Array[int] = []
	for _i in 4:
		first.append(rng.randi())
	rng.set_seed(99)
	for expected in first:
		assert_eq(rng.randi(), expected)


func test_different_seeds_diverge() -> void:
	var low := WyrdRng.new(1)
	var high := WyrdRng.new(2)
	var same := true
	for _i in 4:
		if low.randi() != high.randi():
			same = false
	assert_false(same, "two seeds produced the same four rolls")


func test_range_helpers_repeat() -> void:
	var first := WyrdRng.new(7)
	var second := WyrdRng.new(7)
	assert_eq(first.randi_range(3, 9), second.randi_range(3, 9))
	assert_almost_eq(first.randf_range(-1.0, 1.0), second.randf_range(-1.0, 1.0), 0.0)
