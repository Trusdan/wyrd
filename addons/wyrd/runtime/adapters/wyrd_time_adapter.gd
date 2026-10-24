class_name WyrdTimeAdapter
extends RefCounted

## Host clock, in whole minutes from the game epoch.
##
## The calendar itself will live on the future config resource, not on this adapter.
## The default body is not implemented.

func now_minutes() -> int:
	push_error("not implemented: WyrdTimeAdapter.now_minutes()")
	return 0


## Current season symbol. Content resolvers call this as [code]time.season[/code].
func season() -> StringName:
	push_error("not implemented: WyrdTimeAdapter.season()")
	return &""
