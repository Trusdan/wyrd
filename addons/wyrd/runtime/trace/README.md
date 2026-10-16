# trace

`WyrdTrace` is optional. Set `enabled` before the calls you want to record. `start_new_game` clears `events` and leaves `enabled` as it was.

Inputs, which `replay` runs again: `open_scene`, `advance`, `choose`, `abort`, `tick`, `emit`, `complete_host`, `draw`.

Host answers and decisions, which `replay` skips and `diff` compares: `line`, `line_audio`, `choices`, `resolver`, `command`, `transition`, `roll`, `host_step`, `director`, `why_not`, `region`, `sequence`, `voice`. A `director` line is one query: scope, speaker, candidate count, winner, and score. A `why_not` line explains one storylet: eligible, reason, failing clause, score, cooldown, remaining, and winner. The prefix filter also matches `scope`, `speaker`, and `path`. `key` on a director or why_not line is the scope id. A `region` line is one leaf change: `wyrd region quest=%s path=%s from=%s to=%s`. `path` is the region id, or parent ids joined by `/`. An empty `from` is the first leaf. The prefix matches `quest` or `path`. A `sequence` line is one step, finish, reset, or expiry: `wyrd sequence id=%s count=%s done=%s reason=%s`. `reason` is `step`, `done`, `reset`, or `expire`. `key` on that line is the sequence id. A `voice` line is one holder-variant pick: `wyrd voice line=%s holder=%s chosen=%s`. `key` is the name-free line id. `who` is the holder, empty when the slot or role is vacant. The pick is display-time and is not saved.

Field keys are sorted, then `kind` is inserted first, so a JSON dump is stable. `diff` reports up to eight mismatches. A host that answers differently (a command that fails, a resolver that changes) produces a non-empty diff. Replay does not inject host answers. The second runtime must be booted the same way, then given the recorded inputs.
