class_name WyrdTimeAdapter
extends RefCounted

## Host clock, in whole minutes from the game epoch.
##
## @experimental
## The calendar itself will live on the future config resource, not on this adapter.
## The default body is not implemented.

func now_minutes() -> int:
	push_error("not implemented: WyrdTimeAdapter.now_minutes()")
	return 0
