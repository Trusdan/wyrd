# trace

`WyrdTrace` is optional. Set `enabled` before the calls you want to record. `start_new_game` clears `events` and leaves `enabled` as it was.

Inputs, which `replay` runs again: `open_scene`, `advance`, `choose`, `abort`, `tick`, `emit`, `complete_host`, `draw`.

Host answers and decisions, which `replay` skips and `diff` compares: `line`, `line_audio`, `choices`, `resolver`, `command`, `transition`, `roll`, `host_step`, `director`, `why_not`. A `director` line is one query: scope, speaker, candidate count, winner, and score. A `why_not` line explains one storylet: eligible, reason, failing clause, score, cooldown, remaining, and winner. The prefix filter also matches `scope` and `speaker`. `key` on those lines is the scope id.

Field keys are sorted, then `kind` is inserted first, so a JSON dump is stable. `diff` reports up to eight mismatches. A host that answers differently (a command that fails, a resolver that changes) produces a non-empty diff. Replay does not inject host answers. The second runtime must be booted the same way, then given the recorded inputs.
