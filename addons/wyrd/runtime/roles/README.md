# roles

`WyrdRoles` keeps one binding per role: `holder`, `since`, `status` (`default`, `successor`, `empty`, `pending`), and `history`. `pending` is only the `host_decides` wait. It is not a slot state.

A role definition comes from a `role <id>` block or from `define()`. Both store `scope`, `eligibility`, `default_holder`, `visibility`, `succession`, and `vacancy`. See `docs/statements-draft.md`.

`eligible(role, entity)` runs the eligibility condition with `candidate` bound to that entity. No condition means every entity passes. When a condition is present, the trace bus gets one `eligible` line (`role`, `entity`, `ok`) and, if tracing is on, the console prints `wyrd eligible role=<id> entity=<id> ok=<bool>`. The line does not grow with the facts the condition reads.

`assign` sets the holder. A `default_holder` is assigned when the binding is empty, including on a new game. `assign` refuses an abolished role, and it refuses the departed holder while a `host_decides` request is open.

`vacate` tries one strategy. `relation(kind|kind)` walks outgoing kinds on the departed holder and takes the first living eligible entity with a different id. `faction_assigns(faction)` reads `WyrdWorldAdapter.members(faction)`, keeps living eligible members other than the departed holder, and orders them by `set_faction_rank` (higher int wins). Equal ranks use `WyrdRng.for_decision` on the game seed, the role, the faction, the departed holder, and the current minute. `host_decides` clears the holder, stores a pending request, emits `succession_requested`, and calls `set_host_decides` when that callback is set. The role stays pending until `assign`. `election` and `none` do not pick. A successor is never the departed holder. The successor emits `role_holder_changed` and records `role_changed` with the role id as a tag. No successor emits `role_vacant`.

`vacancy: abolish` runs only after a strategy finds nobody. `host_decides` has not failed yet, so it does not abolish. Abolish clears the holder for good, records `role_abolished` (actor is the departed holder, target is the role id), and later `assign` calls fail until `define` or a new game. `start_new_game` pushes `WyrdRoles: host_decides has no callback` when a role uses that strategy and neither the callback nor `succession_requested` is connected.

Each succession step writes one `succession` trace line (`role`, `strategy`, `from`, `to`, `reason`) when tracing is on. `WyrdTrace.prefix` keeps the line when the role starts with that text. Reasons are `picked`, `none`, `pending`, `assigned`, and `abolished`. Pending requests and abolished role ids are saved on the roles blob. Schema version stays 1.

Slot modes:

- `live` is the current holder.
- `locked_at` freezes in `enter_stage` for that stage and stays frozen. If that frozen holder is vacated or is not alive, the slot state is `locked_gone` even when the role has a successor. `holder()` stays the frozen person.
- `cast` freezes in `begin_quest` to whoever holds the role then. Casting proper is M4.

Slot-state precedence is `locked_gone` / `empty`, then `barred`, `hostile`, `unwilling`, `successor`, and `default`. The first state that applies and has a declared variant on the current stage wins. `hostile` is `disposition(holder, player)` below `hostile_threshold` (20, or the role override). `unwilling` evaluates its condition with `$h` bound to the holder. `barred` evaluates its condition against the player. A quest resolution writes one `slot_state` trace line (`quest`, `role`, `slot`, `state`, `reason`). Set `WyrdTrace.prefix` to keep lines whose quest, role, or slot starts with that text. The same state and reason are not logged again until they change.

A secret role's holder is in `known/<agent>` under `role.<id>.holder` only after `tell`. A public holder is visible to `known` without a write. `holder()` still returns the mechanical holder.
