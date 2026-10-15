class_name WyrdElectionAdapter
extends RefCounted

## Host-run election. Wyrd does not pick the successor.
##
## @experimental
## [method start_election] runs after [signal WyrdRoles.election_needed].
## The host finishes the contest with [method WyrdRoles.assign].

func start_election(role: StringName, departed: StringName) -> void:
	push_error("not implemented: WyrdElectionAdapter.start_election(%s, %s)" % [role, departed])
