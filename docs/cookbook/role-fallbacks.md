# Role fallbacks

A quest should keep going when the person in a role is missing, hostile, replaced, or gone.

## Content

A role names its holder, where it applies, and who follows. Gullhaven's ferry master is held by one person, scoped to a place, and succeeded by an apprentice.

From `example/content/gullhaven/harbor_roles.wyrd`:
```wyrd
role ferry_master
  scope: place(gullhaven)
  default_holder: ferry_master
  succession: relation(apprentice)
  vacancy: hold
```

A quest slot binds a role, and `on_empty: wait` holds the stage when a slot is empty or contested and no variant matched.

From `example/content/gullhaven/ferry_toll.wyrd`:
```wyrd
quest ferry_toll "The Ferry Toll"
  slot tavern  = tavern_owner mode: live
  slot ferry   = ferry_master mode: locked_at(pay_toll)
  slot lookout = storm_watcher mode: cast(world.storm_heard)
  on_empty: wait
  requires: [pack.harbor]
  start when deed_count(player, verb: arrived, place: gullhaven) > 0
```

Slot states are `default`, `successor`, `empty`, `contested`, `hostile`, `unwilling`, `barred`, and `locked_gone`. A variant replaces the stage body for one of those states. `locked_gone` is a frozen holder who was vacated or is not alive. `empty` is nobody in the slot.

From `example/content/gullhaven/ferry_toll.wyrd`:
```wyrd
    variant ferry.locked_gone:
      journal: The ferry master who took the lock is gone. #line:j_ft_gone
      waits_until false
    variant ferry.empty:
      journal: The dock is empty, so the crossing waits. #line:j_ft_empty
      -> gossip
```

The field rules are in [Role](../language.md#role) and [Quest](../language.md#quest). `on_empty` other than `wait` is stored and does not hold the stage. Only `wait` does, and only when no variant matched.

## Host side

The world adapter answers `is_alive`, `exists`, and `candidates`. See the [adapter guide](../adapters.md). An `election` succession fires [`election_needed`](../api/Wyrd.md#election_needed). A [`WyrdElectionAdapter`](../api/WyrdElectionAdapter.md) is optional; without one, the signal still fires and nobody is chosen. The host finishes a contested role with `assign`.

[`role_holder_changed`](../api/Wyrd.md#role_holder_changed), [`role_vacant`](../api/Wyrd.md#role_vacant), and [`election_needed`](../api/Wyrd.md#election_needed) are the stable signals.

## What to test

Vacate the ferry master after the toll stage locks the slot, and check the `locked_gone` journal. Clear the holder before the lock and check that `on_empty: wait` holds the stage. A cast that matches nobody leaves that slot `empty`.
