# roles

`WyrdRoles` keeps one binding per role: `holder`, `since`, `status` (`default`, `successor`, `empty`), and `history`.

`assign` sets the default holder. `vacate` tries `relation(kind|kind)` in order, using outgoing kinds on the current holder, skipping anyone the world adapter says is not alive, and choosing the lowest id. `none` leaves the role empty. A successor emits `role_holder_changed` and records verb `role_changed`. No successor emits `role_vacant`.

Slot modes:

- `live` is the current holder.
- `locked_at` freezes in `enter_stage` for that stage and stays frozen.
- `cast` freezes in `begin_quest` to whoever holds the role then. Casting proper is M4.

Slot state is `empty`, then `hostile` when `disposition(holder, player)` is below `hostile_threshold` (20, or the role override), then `successor`, otherwise `default`.

A secret role's holder is in `known/<agent>` under `role.<id>.holder` only after `tell`. A public holder is visible to `known` without a write. `holder()` still returns the mechanical holder.
