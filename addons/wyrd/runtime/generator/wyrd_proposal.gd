class_name WyrdProposal
extends RefCounted

## One unsaved pick, cast, and bind result.
##
## [member id] is [code]p<seq>[/code]. The sequence resets on a new game and on
## load. [member casts] maps a cast slot to the picked entity. [member params]
## maps a param to [code]{entity, kind}[/code], plus [code]owner[/code] for an
## item and [code]place[/code] for an item or object when a spatial adapter is
## registered. The payload is not readable by content.

var id: String = ""
var source: String = ""
var key: String = ""
var tier: String = ""
var origin: String = ""
var template: String = ""
var instance: String = ""
var casts: Dictionary = {}
var params: Dictionary = {}
var payload: Dictionary = {}
## Counter value [method WyrdGenerator.accept] requires. Not saved.
var expected_counter: int = 0
## True after a successful accept. A second accept returns [code]accepted[/code].
var used: bool = false
