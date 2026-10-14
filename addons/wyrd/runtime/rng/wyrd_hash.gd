class_name WyrdHash
extends RefCounted

## Stable FNV-1a 64-bit hash for [StringName] values and ints.
##
## @experimental
## Godot's [method @GlobalScope.hash] is not used. The engine does not promise that [code]hash()[/code]
## stays the same across versions or platforms, and a [StringName] hash can follow the intern table
## rather than the characters. Save keys, per-decision seeds, and determinism tests need a hash
## that is only a function of the bytes.
##
## The result is the unsigned 64-bit FNV-1a value stored in a signed 64-bit int (the GDScript
## [int] is signed, and arithmetic wraps modulo 2^64, which is the FNV step).
##
## Domain bytes keep the two kinds of input apart:
## [code]0x01[/code] then the UTF-8 bytes of a [StringName], or [code]0x02[/code] then the int as
## eight little-endian two's-complement bytes.

const FNV_OFFSET: int = -3750763034362895579
const FNV_PRIME: int = 1099511628211
const _DOMAIN_STRING: int = 0x01
const _DOMAIN_INT: int = 0x02


static func of_string_name(value: StringName) -> int:
	var hash := _mix(FNV_OFFSET, _DOMAIN_STRING)
	var body := String(value).to_utf8_buffer()
	for i in body.size():
		hash = _mix(hash, body[i])
	return hash


static func of_int(value: int) -> int:
	var hash := _mix(FNV_OFFSET, _DOMAIN_INT)
	var bits := value
	for _i in 8:
		hash = _mix(hash, bits & 0xFF)
		bits >>= 8
	return hash


static func _mix(hash: int, byte: int) -> int:
	return (hash ^ (byte & 0xFF)) * FNV_PRIME
