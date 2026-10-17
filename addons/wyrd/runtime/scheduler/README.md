# scheduler

`WyrdScheduler` runs the fixed-work queues: waits, rumor, publish, and cache refresh. `WyrdTickQueue` is the waits list. One unit is one waiting-condition recheck, one rumor hop, one issue fragment, or one cache rebuild.

`Wyrd.tick(game_minutes)` accepts any non-negative slice, including a fraction. Slices accumulate. A whole game tick runs only when `scheduler_tick_minutes` (default 1) have accumulated. The clock advances by those whole ticks. A call with `0` still runs one game tick and does not move the clock, so existing flush sites stay valid. Slices quantize to 1/720 of a game minute, which makes a 30 fps slice and a 144 fps slice of one game minute add up exactly.

Each game tick spends at most `scheduler_work_per_tick` units. The four share weights split that budget. Round-robin gives each queue one unit at a time, up to its share. Unused share moves to the earliest queue that still has work, so waits still receives the full budget while the other queues are empty. Unfinished items stay in order. The queues and the leftover slice are not saved. Schema stays 2.

A debug build can log `wyrd scheduler queue=frame` when the units take longer than `scheduler_frame_warn_usec` (default 2000 microseconds, 2 ms). `0` disables it. That line is information only.
