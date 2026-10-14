extends GutTest

# Reference: pcg-c-basic pcg32-demo.c and pcg_basic.c at bc39cd76ac3d541e618606bcc6e1e5ba5e5e6aa3,
# seeded pcg32_srandom_r(&rng, 42u, 54u). Round 1 matches pcg-c
# test-high/expected/check-pcg32.out at 89b7dfbc5a50e5bf272cfac29dc435e81d2080d3.
# tools/pcg32_vectors.py prints the same vectors and is not part of CI.
const FIRST_SIX: Array[int] = [
	0xa15c02b7, 0x7b47f409, 0xba1d3330, 0x83d2f293, 0xbfa4784b, 0xcbed606e,
]
const COINS := "HHTTTHTHHHTHTTTHHHHHTTTHHHTHTHTHTTHTTTHHHHHHTTTTHHTTTTTHTTTTTTTHT"
const DICE: Array[int] = [
	3, 4, 1, 1, 2, 2, 3, 2, 4, 3, 2, 4, 3, 3, 5, 2, 3, 1, 3, 1, 5, 1, 4, 1, 5, 6, 4, 6, 6, 2, 6, 3, 3,
]
const TOP_BIT_SIX: Array[int] = [
	0x8b93c7c2, 0x6a27b98d, 0xcb1e753d, 0x1116f876, 0x3f5b1cc3, 0x744dbe0c,
]
const DECISION_FOUR: Array[int] = [737177618, 2436667011, 2434477843, 1390521447]


func test_same_seed_matches_across_instances() -> void:
	var first := WyrdRng.new(1)
	var second := WyrdRng.new(1)
	for _i in 8:
		assert_eq(first.randi(), second.randi())
	first.set_seed(1)
	second.set_seed(1)
	for _i in 4:
		assert_eq(first.randf(), second.randf())


func test_reseed_repeats_the_sequence() -> void:
	var rng := WyrdRng.new(99, 54)
	var first: Array[int] = []
	for _i in 4:
		first.append(rng.randi())
	rng.set_seed(99)
	assert_eq(rng.get_seed(), 99)
	var fresh := WyrdRng.new(99, 54)
	for expected in first:
		assert_eq(rng.randi(), expected)
		assert_eq(fresh.randi(), expected)


func test_different_seeds_diverge() -> void:
	var low := WyrdRng.new(1)
	var high := WyrdRng.new(2)
	var same := true
	for _i in 4:
		if low.randi() != high.randi():
			same = false
	assert_false(same, "two seeds produced the same four rolls")


func test_reference_first_six() -> void:
	var rng := WyrdRng.new(42, 54)
	for expected in FIRST_SIX:
		assert_eq(rng.next_u32(), expected)


func test_reference_seeded_state() -> void:
	var saved := WyrdRng.new(42, 54).to_state()
	assert_eq(int(saved["v"]), 1)
	assert_eq(str(saved["state"]), "185706b82c2e03f8")
	assert_eq(str(saved["inc"]), "000000000000006d")
	assert_eq(str(saved["seed"]), "000000000000002a")


func test_reference_coins_and_dice() -> void:
	var rng := WyrdRng.new(42, 54)
	for _i in FIRST_SIX.size():
		rng.next_u32()
	var coins := ""
	for _i in COINS.length():
		coins += "H" if rng.randi_bounded(2) == 1 else "T"
	assert_eq(coins, COINS)
	for face in DICE:
		assert_eq(rng.randi_bounded(6) + 1, face)


func test_top_bit_seed() -> void:
	var rng := WyrdRng.new(1 << 63, 54)
	assert_lt(rng.get_seed(), 0)
	for expected in TOP_BIT_SIX:
		assert_eq(rng.randi(), expected)


func test_logical_shift_guard() -> void:
	# Bit 63 is set. An arithmetic >> would return 65532, not 4.
	var hand := _state("8000000000000000", "0000000000000001", "0000000000000000")
	assert_eq(hand.next_u32(), 4)
	var seeded := WyrdRng.new(42, 54)
	seeded.next_u32()
	seeded.next_u32()
	assert_eq(str(seeded.to_state()["state"]), "8b33296d19bf5b4e")
	assert_eq(seeded.next_u32(), 0xba1d3330)


func test_bounded_stays_inside() -> void:
	var bounds: Array[int] = [1, 2, 3, 6, 7, 2147483649, 4294967296]
	var rng := WyrdRng.new(42, 54)
	for bound in bounds:
		for _i in 10000:
			var roll := rng.randi_bounded(bound)
			if roll < 0 or roll >= bound:
				fail_test("bound %d produced %d" % [bound, roll])
				return
	assert_eq(WyrdRng.new(1).randi_bounded(1), 0)


func test_range_edges() -> void:
	var rng := WyrdRng.new(7)
	var twin := WyrdRng.new(7)
	assert_eq(rng.randi_range(4, 4), 4)
	assert_eq(rng.randi(), twin.randi())
	var ordered := WyrdRng.new(7)
	var swapped := WyrdRng.new(7)
	assert_eq(swapped.randi_range(9, 3), ordered.randi_range(3, 9))
	var negative := WyrdRng.new(11)
	var roll := negative.randi_range(-8, -3)
	assert_gte(roll, -8)
	assert_lte(roll, -3)
	assert_eq(WyrdRng.new(11).randi_range(-3, -8), roll)
	var first := WyrdRng.new(7)
	var second := WyrdRng.new(7)
	assert_almost_eq(first.randf_range(-1.0, 1.0), second.randf_range(-1.0, 1.0), 0.0)


func test_randf_is_half_open() -> void:
	var rng := WyrdRng.new(1, 2)
	for _i in 10000:
		var roll := rng.randf()
		if roll < 0.0 or roll >= 1.0:
			fail_test("randf out of range: %f" % roll)
			return
	var zero := _state("8000200008000000", "0000000000000001", "0000000000000000")
	assert_eq(zero.randf(), 0.0)
	assert_eq(_state("8000200008000000", "0000000000000001", "0000000000000000").next_u32(), 0)


func test_streams_diverge_and_stream_id_is_stable() -> void:
	assert_eq(WyrdRng.stream_id(&"gullhaven"), -712608799729761524)
	assert_eq(WyrdRng.stream_id(&"gullhaven"), WyrdHash.of_string_name(&"gullhaven"))
	var left := WyrdRng.new(5, 0)
	var right := WyrdRng.new(5, 1)
	var same := true
	for _i in 4:
		if left.randi() != right.randi():
			same = false
	assert_false(same, "two streams produced the same four rolls")
	var renamed := WyrdRng.new(5)
	renamed.seed_with(5, 1)
	var direct := WyrdRng.new(5, 1)
	assert_eq(renamed.randi(), direct.randi())


func test_for_decision_is_independent() -> void:
	var first := WyrdRng.for_decision(7, &"gullhaven", &"room", 4)
	var second := WyrdRng.for_decision(7, &"gullhaven", &"room", 4)
	for expected in DECISION_FOUR:
		assert_eq(first.randi(), expected)
		assert_eq(second.randi(), expected)
	first.randi()
	var fresh := WyrdRng.for_decision(7, &"gullhaven", &"room", 4)
	assert_eq(fresh.randi(), DECISION_FOUR[0])
	assert_ne(WyrdRng.for_decision(8, &"gullhaven", &"room", 4).randi(), DECISION_FOUR[0])
	assert_ne(WyrdRng.for_decision(7, &"harbor", &"room", 4).randi(), DECISION_FOUR[0])
	assert_ne(WyrdRng.for_decision(7, &"gullhaven", &"dock", 4).randi(), DECISION_FOUR[0])
	assert_ne(WyrdRng.for_decision(7, &"gullhaven", &"room", 5).randi(), DECISION_FOUR[0])


func test_state_round_trip() -> void:
	var rng := WyrdRng.new(99, 7)
	for _i in 5:
		rng.randi()
	var saved := rng.to_state()
	var expected: Array[int] = []
	for _i in 4:
		expected.append(rng.randi())
	_expect_draws(WyrdRng.from_state(saved), expected)
	var upper: Dictionary = saved.duplicate()
	upper["inc"] = str(upper["inc"]).to_upper()
	_expect_draws(WyrdRng.from_state(upper), expected)
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	assert_true(parsed is Dictionary)
	_expect_draws(WyrdRng.from_state(parsed), expected)
	var text: Variant = str_to_var(var_to_str(saved))
	assert_true(text is Dictionary)
	_expect_draws(WyrdRng.from_state(text), expected)


func test_restore_rejects_without_applying() -> void:
	var rng := WyrdRng.new(42, 54)
	var first := rng.randi()
	var twin := WyrdRng.new(42, 54)
	assert_eq(twin.randi(), first)
	assert_false(rng.restore({"v": 2, "state": "0000000000000000", "inc": "0000000000000001", "seed": "0000000000000000"}))
	assert_push_error("version must be 1")
	assert_null(WyrdRng.from_state({"v": 9}))
	assert_push_error("version must be 1")
	assert_false(rng.restore({"v": 1, "state": "zzzzzzzzzzzzzzzz", "inc": "0000000000000001", "seed": "0000000000000000"}))
	assert_push_error("16 hex digits")
	assert_false(rng.restore({"v": 1, "state": "0000000000000000", "inc": "0000000000000002", "seed": "0000000000000000"}))
	assert_push_error("increment must be odd")
	assert_null(WyrdRng.from_state({"v": 1, "state": "0000000000000000", "inc": "0000000000000002", "seed": "not-hex-digits!!"}))
	assert_push_error("16 hex digits")
	assert_eq(rng.randi(), twin.randi())
	assert_true(rng.restore(twin.to_state()))
	assert_eq(rng.randi(), twin.randi())


func _state(state: String, inc: String, seed: String) -> WyrdRng:
	return WyrdRng.from_state({"v": 1, "state": state, "inc": inc, "seed": seed})


func _expect_draws(rng: WyrdRng, expected: Array[int]) -> void:
	assert_not_null(rng)
	for value in expected:
		assert_eq(rng.randi(), value)
