class_name WyrdAIRequest
extends RefCounted

## One AI request. The answer comes back later through [method reply].
##
## The owner is a [Callable] set by [WyrdAI]. The request does not keep the runtime.

const KINDS: Array[StringName] = [
	&"bark_paraphrase",
	&"gossip",
	&"journal_summary",
	&"epilogue_stitch",
	&"tts_prep",
]

var id: int = 0
var kind: StringName = &""
var packet: Dictionary = {}
var constraints: Dictionary = {}
var locale: StringName = &""
## Line id. Empty when the request is not tied to a line.
var path: StringName = &""
## Cache key for this request. A provider may use it, for example as a seed.
## Empty until [method WyrdAI.request] sends the request.
var key: String = ""
## Empty for a host request. [code]scene:<root scene id>[/code] for a scene
## prefetch. [code]topic:<npc>[/code] for a topic prefetch.
## [code]bark:<storylet id>[/code] for a bark prefetch.
## [code]summary:<quest id>[/code] for a journal summary. Not part of the cache key.
var owner: String = ""
## Game minutes when the request was sent. [code]-1[/code] until then.
## Not part of the cache key. Bark and summary expiry read it.
var sent_minute: int = -1
var _deliver: Callable = Callable()


func set_deliver(deliver: Callable) -> void:
	_deliver = deliver


## Forwards to the owning [method WyrdAI.deliver]. A provider never needs the autoload.
func reply(result: WyrdAIResult) -> bool:
	if not _deliver.is_valid():
		return false
	return bool(_deliver.call(id, result))
