extends GutTest

# Independent FNV-1a 64 vectors (signed bit pattern). A change to the domain byte,
# the endianness, or the prime must fail here, including on a later Godot build.

func test_string_name_vectors() -> void:
	assert_eq(WyrdHash.of_string_name(&"gullhaven"), -712608799729761524)
	assert_eq(WyrdHash.of_string_name(&"ferry_master"), -6385992166552910685)
	assert_eq(WyrdHash.of_string_name(&""), -5808592057526012372)


func test_int_vectors() -> void:
	assert_eq(WyrdHash.of_int(0), 925820630484784613)
	assert_eq(WyrdHash.of_int(42), 2449347354575781711)
	assert_eq(WyrdHash.of_int(-1), -5794812345381499299)


func test_repeat_calls_match() -> void:
	assert_eq(WyrdHash.of_string_name(&"gullhaven"), WyrdHash.of_string_name(&"gullhaven"))
	assert_eq(WyrdHash.of_int(42), WyrdHash.of_int(42))


func test_domains_do_not_collapse() -> void:
	assert_ne(WyrdHash.of_int(42), WyrdHash.of_string_name(&"42"))
	assert_ne(WyrdHash.of_string_name(&"gullhaven"), WyrdHash.of_string_name(&"ferry_master"))


func test_combine_locked_values() -> void:
	assert_eq(WyrdHash.combine(0, 0), -5026298552858385863)
	assert_eq(WyrdHash.combine(1, 2), -1666581824604252188)
	assert_eq(WyrdHash.combine(WyrdHash.of_int(0), WyrdHash.of_int(42)), -8077627191156648152)
	assert_eq(WyrdHash.combine(-1, 42), 633195289179834590)
	assert_ne(WyrdHash.combine(1, 2), WyrdHash.combine(2, 1))
