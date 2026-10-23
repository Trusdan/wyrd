extends Node

const _Runtime := preload("res://addons/wyrd/runtime/wyrd_runtime.gd")

## Facade over one [WyrdRuntime].
##
## @experimental
## The editor plugin does not register this script as an autoload.
## When it does, the autoload name is Wyrd, so this script has no class_name.
## [member facts], [member events], [member deeds], [member social], [member rumors], [member publish],
## [member roles], [member quests], [member dialogue], [member storylets],
## [member sequences], [member director], [member generator], [member ai], [member debug], and [member coverage] are the runtime's sub-objects. [member ai] is the AI hook and stays idle with the null provider. [member dialogue] is
## the scene runner. [member storylets] draws a line set. [member director]
## ranks one. [member topics] is the unlocked topic set. [member documents] opens a readable document.
## [signal bark_ready] repeats the runtime signal for a bark win.
## [signal topic_unlocked] and [signal topic_locked] repeat the topic store.
## [signal document_read] repeats a document open.
## [signal load_report_ready] repeats the runtime signal once per [method load_state].

signal bark_ready(line: WyrdLineView)
signal topic_unlocked(topic: StringName)
signal topic_locked(topic: StringName)
signal document_read(doc_id: StringName, copy_id: String, reader: StringName, first_time: bool)
signal load_report_ready(report: WyrdLoadReport)

var facts: WyrdFactStore
var events: WyrdEvents
var deeds: WyrdDeedLog
var social: WyrdSocial
var rumors: WyrdRumor
var publish: WyrdPublish
var roles: WyrdRoles
var topics: WyrdTopics
var documents: WyrdDocuments
var quests: WyrdQuestRunner
var dialogue: WyrdSceneRunner
var storylets: WyrdStoryletDeck
var sequences: WyrdSequences
var director: WyrdDirector
var generator: WyrdGenerator
var ai: WyrdAI
var trace: WyrdTrace
var debug: WyrdDebug
var coverage: WyrdCoverage

var _runtime: WyrdRuntime


func _init() -> void:
	_runtime = _Runtime.new()
	facts = _runtime.facts
	events = _runtime.events
	deeds = _runtime.deeds
	social = _runtime.social
	rumors = _runtime.rumors
	publish = _runtime.publish
	roles = _runtime.roles
	topics = _runtime.topics
	documents = _runtime.documents
	quests = _runtime.quests
	dialogue = _runtime.dialogue
	storylets = _runtime.storylets
	sequences = _runtime.sequences
	director = _runtime.director
	generator = _runtime.generator
	ai = _runtime.ai
	trace = _runtime.trace
	debug = _runtime.debug
	coverage = _runtime.coverage
	_runtime.bark_ready.connect(_relay_bark)
	_runtime.load_report_ready.connect(_relay_load_report)
	if topics != null:
		topics.topic_unlocked.connect(_relay_topic_unlocked)
		topics.topic_locked.connect(_relay_topic_locked)
	if documents != null:
		documents.document_read.connect(_relay_document_read)


func _relay_bark(line: WyrdLineView) -> void:
	bark_ready.emit(line)


func _relay_load_report(report: WyrdLoadReport) -> void:
	load_report_ready.emit(report)


func _relay_topic_unlocked(topic: StringName) -> void:
	topic_unlocked.emit(topic)


func _relay_topic_locked(topic: StringName) -> void:
	topic_locked.emit(topic)


func _relay_document_read(doc_id: StringName, copy_id: String, reader: StringName, first_time: bool) -> void:
	document_read.emit(doc_id, copy_id, reader, first_time)


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


func register_rumor_policy(policy: WyrdRumorPolicy) -> void:
	_runtime.register_rumor_policy(policy)


func deeds_known_to(group: StringName, since: int, filter: StringName = &"") -> Array:
	return _runtime.deeds_known_to(group, since, filter)


func invalidate_groups() -> void:
	_runtime.invalidate_groups()


## Drops cached cast lists. An empty [param ids] means anything may have changed.
func invalidate_world(ids: PackedStringArray = PackedStringArray()) -> void:
	_runtime.invalidate_world(ids)


func start_new_game(seed_value: int) -> void:
	_runtime.start_new_game(seed_value)


func load_content(manifest: WyrdContentManifest) -> WyrdLoadReport:
	return _runtime.load_content(manifest)


func tick(game_minutes: float) -> void:
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
