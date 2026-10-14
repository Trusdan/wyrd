# scheduler

`WyrdTickQueue` is the per-tick queue. `Wyrd.tick(game_minutes)` adds those minutes to the runtime clock (and uses the time adapter's `now_minutes` when that clock is ahead), refreshes due `poll` resolvers, and re-checks dirty waiting conditions in index order.

Each tick does at most `scheduler_work_per_tick` condition re-checks. The rest stay dirty. A later quest runner can `unwatch_condition` so only live waits are checked. The queue is not saved.
