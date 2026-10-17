# publish

`WyrdPublish` builds periodic document issues on the scheduler's `publish` queue.

A `document` block names a group, a period, and a delay. Units are `minute` or `minutes` (1 game minute), `hour` or `hours` (60), and `day` or `days` (1440). The first issue is due at `delay` game minutes after a new game. The next is due one period later. `tick(0)` before that delay publishes nothing.

`deeds_known_to(group, since, filter)` returns deed rows that any current member of the group witnessed at `t >= since`. Membership is `WyrdWorldAdapter.members`. The witness index is the knower list from the deed log. `saw` is `known`. `heard` and `inferred` are `believed`. An empty filter keeps every verb. Any other filter is the verb. Rows are unique by deed id and sorted by that id. A rumor listener who is not on the deed is not a knower. Their `believed/` value does not add a deed.

One publish unit is one frozen issue. The token is `issue`, the document id, the issue number, and the due minute. The handler ignores any other token. The issue number starts at 1. The copy id is `<id>#<n>`. The deed window is `[due - period, due)`. The copy is built when the unit runs, not when it is queued.

The issue claim is chosen in this order. The first fragment whose `when` is true supplies its `slant` symbol. Otherwise the `believed/<member>` value of the lowest sorted current member wins, including a value a rumor mutation wrote. Otherwise `known/<member>` of the lowest sorted member. Otherwise the world fact. The deed row is not rewritten. There is no roll. The same deeds, membership, and facts produce the same line.

After a jump, one visit enqueues at most `WyrdConfig.publish_catchup_max` missed issues per document, oldest first. The default is 3. `0` or a negative value enqueues none. Issues past the cap in that visit are skipped, not retried on a later tick, until load clears the in-memory mark. The cap is not a time budget. The queue still spends `scheduler_share_publish` work units.

The frozen line is appended to the document's `fact` symbol. That write is an ordinary world fact, so schema 2 keeps it. The line starts with the copy id. On the next visit the highest `#n` in that text is the last issue, and a due minute already in the text is not published again. The in-memory counter, the skip mark, and queued tokens are not saved. Load drops them. A later visit can publish a due minute that was skipped or still queued, and it will not reuse a copy id that is already in the fact. Schema 3 is the later home for the counter and the scheduler carry.

With tracing on, a built issue logs `wyrd publish document=<id> issue=<id>#<n> deeds=<count>`. `path` is the document id, `key` is the copy id, and `who` is the group. Replay skips the line. Load does not log it.
