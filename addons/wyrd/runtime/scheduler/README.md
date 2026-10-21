# scheduler

`WyrdScheduler` runs the fixed-work queues: waits, rumor, publish, cache refresh, and generate. `WyrdTickQueue` is the waits list. One unit is one waiting-condition recheck, one rumor hop or one coarse reach rise, one frozen issue, one cache rebuild, or one generate offer.

`Wyrd.tick(game_minutes)` accepts any non-negative slice, including a fraction. Slices accumulate. A whole game tick runs only when `scheduler_tick_minutes` (default 1) have accumulated. The clock advances by those whole ticks. A call with `0` still runs one game tick and does not move the clock, so existing flush sites stay valid. Slices quantize to 1/720 of a game minute, which makes a 30 fps slice and a 144 fps slice of one game minute add up exactly.

Each game tick spends at most `scheduler_work_per_tick` units. The five share weights split that budget. `scheduler_share_generate` defaults to 0. Round-robin gives each queue one unit at a time, up to its share. Unused share moves to the earliest queue that still has work, so waits still receives the full budget while the other queues are empty. Generate has work only when a handler is set and an offer is waiting, so with the default share it runs only by spill onto an otherwise idle tick. It keeps no tokens and is not saved. `run` still reports `spent` and `carry` for the four saved queues, plus `generate_spent` and `generate_carry`. Unfinished items stay in order. The token queues, the dirty waits, and the leftover slice are saved in `flight.scheduler`. A schema 2 save loads with empty token queues and a zero slice, and leaves the dirty waits armed. A schema 3 save that omits `flight` had an empty dirty set, so that load clears it. Load does not log `wyrd scheduler`.

A debug build can log `wyrd scheduler queue=frame` when the units take longer than `scheduler_frame_warn_usec` (default 2000 microseconds, 2 ms). `0` disables it. That line is information only.

The rumor queue delivers one precise hop, or one coarse reach rise, per token. Coarse rises use the same share and the same work budget. See `runtime/rumor/README.md`.

The publish queue delivers one frozen issue per token. A visit enqueues at most `publish_catchup_max` missed issues per document (default 3). Issues past that cap are numbered in the document fact and are not published later. That cap is a count of issues, not a time budget. See `runtime/publish/README.md`.
