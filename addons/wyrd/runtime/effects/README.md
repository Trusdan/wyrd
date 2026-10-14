# effects

`WyrdEffects` runs the six slice effects: `set`, `inc`, `record deed`, `unlock topic`, `do`, and `outcome`.

`set` and `inc` write stored facts. Provenance keeps `scene`, `choice`, and `time` (game minutes). `inc` of a missing fact starts at 0. A type mismatch is `push_error` and the fact stays.

`record deed` calls the deed log. Set literals in arguments are read from the argument's source text, because the expression emitter does not push a set value.

`unlock topic` emits `topic_unlocked`. `outcome` emits `outcome_changed`. A failed `do` returns the `on_fail` target and later effects in that list do not run. A missing action adapter fails the command.
