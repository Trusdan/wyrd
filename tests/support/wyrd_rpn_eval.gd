class_name WyrdRpnEval
extends RefCounted

## Test-only stack evaluator for [WyrdCompiledCondition].
##
## @experimental
## Not the runtime evaluator. [param funcs] maps a function name to a [Callable]
## that receives the argument array. Missing facts compare as false.

var _stack: Array = []


func eval(compiled: WyrdCompiledCondition, facts: Dictionary, funcs: Dictionary = {}) -> Variant:
	_stack.clear()
	var code := compiled.code
	var ip := 0
	while ip < code.size():
		var op := code[ip]
		ip += 1
		match op:
			WyrdOpcodes.PUSH_CONST:
				_stack.append(compiled.consts[code[ip]])
				ip += 1
			WyrdOpcodes.PUSH_TRUE:
				_stack.append(true)
			WyrdOpcodes.PUSH_FALSE:
				_stack.append(false)
			WyrdOpcodes.PUSH_NIL:
				_stack.append(null)
			WyrdOpcodes.LOAD_FACT:
				_stack.append(_load(facts, compiled.consts[code[ip]]))
				ip += 1
			WyrdOpcodes.LOAD_KEY:
				_stack.append(_load_key(facts, code[ip]))
				ip += 1
			WyrdOpcodes.NEG:
				_stack.append(_neg(_pop()))
			WyrdOpcodes.ADD, WyrdOpcodes.SUB, WyrdOpcodes.MUL, WyrdOpcodes.DIV:
				var rhs: Variant = _pop()
				var lhs: Variant = _pop()
				_stack.append(_arith(op, lhs, rhs))
			WyrdOpcodes.EQ, WyrdOpcodes.NE, WyrdOpcodes.LT, WyrdOpcodes.LE, WyrdOpcodes.GT, WyrdOpcodes.GE:
				var right: Variant = _pop()
				var left: Variant = _pop()
				_stack.append(_cmp(op, left, right))
			WyrdOpcodes.NOT:
				_stack.append(_pop() != true)
			WyrdOpcodes.IN_SET:
				_stack.append(_in_set(code[ip]))
				ip += 1
			WyrdOpcodes.IN_RANGE:
				var hi: Variant = _pop()
				var lo: Variant = _pop()
				var needle: Variant = _pop()
				_stack.append(_in_range(needle, lo, hi))
			WyrdOpcodes.CALL:
				var fname: StringName = compiled.consts[code[ip]]
				var argc := code[ip + 1]
				ip += 2
				_stack.append(_call(fname, argc, funcs))
			WyrdOpcodes.JUMP:
				ip = code[ip]
			WyrdOpcodes.JUMP_IF_FALSE:
				var failed := code[ip]
				ip += 1
				if _pop() != true:
					ip = failed
			WyrdOpcodes.JUMP_IF_TRUE:
				var taken := code[ip]
				ip += 1
				if _pop() == true:
					ip = taken
			_:
				return null
	if _stack.is_empty():
		return null
	return _stack[_stack.size() - 1]


func _load(facts: Dictionary, key: Variant) -> Variant:
	var text := String(key)
	if facts.has(text):
		return facts[text]
	if facts.has(key):
		return facts[key]
	return null


func _load_key(facts: Dictionary, count: int) -> Variant:
	var parts := PackedStringArray()
	parts.resize(count)
	for i in range(count - 1, -1, -1):
		parts[i] = str(_pop())
	return _load(facts, ".".join(parts))


func _in_set(count: int) -> bool:
	var items: Array = []
	items.resize(count)
	for i in range(count - 1, -1, -1):
		items[i] = _pop()
	var needle: Variant = _pop()
	for item in items:
		if _same(needle, item):
			return true
	return false


func _in_range(needle: Variant, lo: Variant, hi: Variant) -> bool:
	if needle == null or lo == null or hi == null:
		return false
	if needle is float or lo is float or hi is float:
		return float(needle) >= float(lo) and float(needle) <= float(hi)
	return needle >= lo and needle <= hi


func _call(fname: StringName, argc: int, funcs: Dictionary) -> Variant:
	var args: Array = []
	args.resize(argc)
	for i in range(argc - 1, -1, -1):
		args[i] = _pop()
	if funcs.has(fname):
		return funcs[fname].call(args)
	if funcs.has(String(fname)):
		return funcs[String(fname)].call(args)
	if String(fname) == "chance" and argc > 0 and args[0] != null:
		return float(args[0]) >= 1.0
	return false


func _arith(op: int, lhs: Variant, rhs: Variant) -> Variant:
	if lhs == null or rhs == null:
		return null
	var ints := lhs is int and rhs is int
	if op == WyrdOpcodes.DIV and ints and int(rhs) == 0:
		return 0
	if op == WyrdOpcodes.DIV and not ints and float(rhs) == 0.0:
		return 0.0
	match op:
		WyrdOpcodes.ADD:
			return lhs + rhs if ints else float(lhs) + float(rhs)
		WyrdOpcodes.SUB:
			return lhs - rhs if ints else float(lhs) - float(rhs)
		WyrdOpcodes.MUL:
			return lhs * rhs if ints else float(lhs) * float(rhs)
		_:
			return int(lhs / rhs) if ints else float(lhs) / float(rhs)


func _cmp(op: int, left: Variant, right: Variant) -> bool:
	if left == null or right == null:
		return false
	if op == WyrdOpcodes.EQ:
		return _same(left, right)
	if op == WyrdOpcodes.NE:
		return not _same(left, right)
	var a: Variant = left
	var b: Variant = right
	if (left is int or left is float) and (right is int or right is float):
		if left is float or right is float:
			a = float(left)
			b = float(right)
	match op:
		WyrdOpcodes.LT:
			return a < b
		WyrdOpcodes.LE:
			return a <= b
		WyrdOpcodes.GT:
			return a > b
		_:
			return a >= b


func _same(left: Variant, right: Variant) -> bool:
	if left == null or right == null:
		return false
	if (left is int or left is float) and (right is int or right is float):
		if left is float or right is float:
			return is_equal_approx(float(left), float(right))
		return left == right
	if left is bool or right is bool:
		return left == right
	return str(left) == str(right)


func _neg(value: Variant) -> Variant:
	if value == null:
		return null
	return -value


func _pop() -> Variant:
	if _stack.is_empty():
		return null
	return _stack.pop_back()
