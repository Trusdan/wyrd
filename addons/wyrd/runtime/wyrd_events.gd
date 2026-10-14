class_name WyrdEvents
extends RefCounted

## Host entry for [code]Wyrd.events.emit[/code].
##
## @experimental
## The payload is accepted and not interpreted. Host world-event schemas are
## not part of this slice. [code]emit[/code] invalidates [code]on_event[/code]
## resolver caches through the runtime.

var on_emit: Callable = Callable()


func emit(event_name: StringName, payload: Dictionary = {}) -> void:
	if on_emit.is_valid():
		on_emit.call(event_name, payload)
