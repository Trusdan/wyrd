# rumor

Precise-mode rumors. A host registers a `WyrdRumorPolicy`. There is no `.wyrd` syntax for one in this slice.

A deed starts a rumor only when it has a reveal claim and the first registered policy matches its verb. An empty verb list matches every verb. A policy with no kinds, or `max_hops` below 1, matches and does not spread. Later policies are not tried. `pass_chance` is clamped to 0..1. `1` always offers the hop. `0` never does. The registered copy is what runs. Policies are host registrations and are not saved.

Origins are the actor and the deed's witnesses, sorted. That witness list is the same slice the witness index stores. Spread does not scan the log. From each origin, in sorted order, one hop is queued to each sorted neighbor of the policy's relationship kinds (`WyrdSocial.targets`). A listener is queued once. The earliest speaker is the one who offers it. A later speaker does not get a second unit.

One scheduler unit is one token: `deed`, speaker, listener, hop, separated by tabs. Hop 1 is the first step away from an origin. The unit rolls `WyrdRng.for_decision` with stream `rumor`, that token as the decision key, and the hour bucket of the current minute. Adoption uses `credibility_score(listener, speaker)` and `credibility_threshold`. The default score is disposition, which reads the social cache. An accepted hop writes `believed/<listener>` only. It does not write `known:` or `world:`. A rejected hop, or a hop the roll skips, does not write and does not continue. The next hop is queued only after a write, and only while the hop number is below `max_hops`.

`WyrdSpatialAdapter.precision(place)` answers `precise` or `coarse`. The default is `precise` and does not `push_error`. An empty place counts as precise. A deed in a coarse place does not start. A listener standing in a coarse place consumes the unit, does not adopt, and does not pass the claim on. Aggregate reach and coarse ticks are a later slice.

The claim table, the seen set, and the queued set are not saved. Schema stays 2. Load drops them, drops the rumor tokens with the other scheduler queues, and does not log a rumor line or continue the spread. Beliefs already written stay in the fact store. Deed compaction does not cancel an in-flight claim and does not start a new one.

With tracing on, a hop logs `wyrd rumor hop deed=%s policy=%s from=%s to=%s hop=%d key=%s taken=%s reason=%s`. `reason` is `pass`, `chance`, or `coarse`. An offered hop then logs `wyrd rumor adopt listener=%s speaker=%s policy=%s key=%s score=%s accepted=%s`. `who` is the listener. `speaker` is the person who offered it. `path` is the policy id. Replay skips both lines. Load does not log them.
