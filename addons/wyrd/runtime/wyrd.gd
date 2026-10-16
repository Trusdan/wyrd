extends Node

const _Runtime := preload("res://addons/wyrd/runtime/wyrd_runtime.gd")

## Facade over one [WyrdRuntime].
##
## @experimental
## The editor plugin does not register this script as an autoload.
## When it does, the autoload name is Wyrd, so this script has no class_name.
## [member facts], [member events], [member deeds], [member social],
## [member roles], [member quests], [member dialogue], and [member storylets]
## are the runtime's sub-objects. [member dialogue] is the scene runner.
## [member storylets] draws a line set. It does not rank storylets.

var facts: WyrdFactStore
var events: WyrdEvents
var deeds: WyrdDeedLog
var social: WyrdSocial
var roles: WyrdRoles
var quests: WyrdQuestRunner
var dialogue: WyrdSceneRunner
var storylets: WyrdStoryletDeck
var trace: WyrdTrace

var _runtime: WyrdRuntime


func _init() -> void:
	_runtime = _Runtime.new()
	facts = _runtime.facts
	events = _runtime.events
	deeds = _runtime.deeds
	social = _runtime.social
	roles = _runtime.roles
	quests = _runtime.quests
	dialogue = _runtime.dialogue
	storylets = _runtime.storylets
	trace = _runtime.trace


func get_version() -> String:
	return _runtime.get_version()


func configure(config: WyrdConfig) -> void:
	_runtime.configure(config)


func register_adapter(base: Script, adapter: RefCounted) -> void:
	_runtime.register_adapter(base, adapter)


func register_function(name: StringName, fn: Callable, arg_types: Array, return_type: StringName) -> bool:
	return _runtime.register_function(name, fn, arg_types, return_type)


func register_group_precedence(fn: Callable) -> void:
	_runtime.register_group_precedence(fn)


func register_credibility(fn: Callable) -> void:
	_runtime.register_credibility(fn)


func invalidate_groups() -> void:
	_runtime.invalidate_groups()


func start_new_game(seed_value: int) -> void:
	_runtime.start_new_game(seed_value)


func load_content(manifest: WyrdContentManifest) -> WyrdLoadReport:
	return _runtime.load_content(manifest)


func tick(game_minutes: int) -> void:
	_runtime.tick(game_minutes)


func now_minutes() -> int:
	return _runtime.now_minutes()


func can_save() -> bool:
	return _runtime.can_save()


func save_state() -> Dictionary:
	return _runtime.save_state()


func load_state(data: Dictionary) -> WyrdLoadReport:
	return _runtime.load_state(data)


func rng_stream(name: StringName) -> WyrdRng:
	return _runtime.rng_stream(name)


func draw_u32(name: StringName) -> int:
	return _runtime.draw_u32(name)


func content() -> WyrdContent:
	return _runtime.content()


func condition_count() -> int:
	return _runtime.condition_count()


func condition_flags() -> PackedByteArray:
	return _runtime.condition_flags()


func eval_condition(index: int) -> bool:
	return _runtime.eval_condition(index)


func last_rechecks() -> int:
	return _runtime.last_rechecks()


func trace_log() -> Array[Dictionary]:
	return _runtime.trace_log()
