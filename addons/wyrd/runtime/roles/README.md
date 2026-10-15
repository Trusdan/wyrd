# roles

`WyrdRoles` keeps one binding per role: `holder`, `since`, `status` (`default`, `successor`, `empty`), and `history`.

A role definition comes from a `role <id>` block or from `define()`. Both store `scope`, `eligibility`, `default_holder`, `visibility`, `succession`, and `vacancy`. See `docs/statements-draft.md`.

`eligible(role, entity)` runs the eligibility condition with `candidate` bound to that entity. No condition means every entity passes. When a condition is present, the trace bus gets one `eligible` line (`role`, `entity`, `ok`) and, if tracing is on, the console prints `wyrd eligible role=<id> entity=<id> ok=<bool>`. The line does not grow with the facts the condition reads.

`assign` sets the holder. A `default_holder` is assigned when the binding is empty, including on a new game. `vacate` tries `relation(kind|kind)` in order, using outgoing kinds on the current holder, skipping anyone who is not alive or who fails eligibility, and choosing the lowest id. `none` leaves the role empty. `faction_assigns`, `election`, and `host_decides` are stored and do not pick a holder yet. `vacancy: abolish` is stored and does not abolish the role yet. A successor emits `role_holder_changed` and records verb `role_changed`. No successor emits `role_vacant`.

Slot modes:

- `live` is the current holder.
- `locked_at` freezes in `enter_stage` for that stage and stays frozen. If that frozen holder is vacated or is not alive, the slot state is `locked_gone` even when the role has a successor. `holder()` stays the frozen person.
- `cast` freezes in `begin_quest` to whoever holds the role then. Casting proper is M4.

Slot-state precedence is `locked_gone` / `empty`, then `barred`, `hostile`, `unwilling`, `successor`, and `default`. The first state that applies and has a declared variant on the current stage wins. `hostile` is `disposition(holder, player)` below `hostile_threshold` (20, or the role override). `unwilling` evaluates its condition with `$h` bound to the holder. `barred` evaluates its condition against the player. A quest resolution writes one `slot_state` trace line (`quest`, `role`, `slot`, `state`, `reason`). Set `WyrdTrace.prefix` to keep lines whose quest, role, or slot starts with that text. The same state and reason are not logged again until they change.

A secret role's holder is in `known/<agent>` under `role.<id>.holder` only after `tell`. A public holder is visible to `known` without a write. `holder()` still returns the mechanical holder.
