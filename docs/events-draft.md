# Events draft

Draft, not frozen. Grammar v1 sections 1–6 do not change. `docs/statements-draft.md` has the stage `on` form. This file is the schema and the runtime.

## Declaration

A top-level `events` block sits beside `facts`. Names are unique in the pack. An event with no fields is invalidate-only: the payload must be empty. Field types are `bool`, `int`, `float`, and `symbol`. Every declared field is required.

```
events
  season_changed()
  entity_alive_changed(entity: symbol, alive: bool)
  mechanism_state(object: symbol, state: symbol, actor: symbol)
  item_inserted(item: symbol, receptacle: symbol, actor: symbol)
  liquid_poured(liquid: symbol, amount: int, target: symbol, actor: symbol)
```

`invalidate: on_event(name)` must name an event declared in the pack. `per_query` never caches. `poll(minutes)` is unchanged. A resolved fact with no invalidate mode is `E_RESOLVER_NO_INVALIDATE`.

## `on` handlers

Only a stage may say `on <event> where <condition>:`. The block is effects and `->` transitions, in source order. `event.<field>` is a readonly binding in that `where` and in those nested expressions. It is not stored unless an effect `set`s a fact. The same stage runs at most one matching handler per emit. A transition does not run the destination stage's handlers for that emit.

An open scene is not aborted when an event arrives. The next line, choice, or wait sees the new values. A holder leaving a passed slot still aborts on the role change. A dead holder aborts on the next `Wyrd.tick`. Authors who need a hard interrupt call `dialogue.abort`.

## Emit

`Wyrd.events.emit(name, payload)` checks the payload against the loaded schema. A failure is `push_error`, trace kind `emit_rejected`, and no invalidation. Success traces `emit` with the name, payload, game time, invalidated keys, and the condition indexes re-checked, in ascending index order. Only dependents are re-checked.

`begin_batch` / `end_batch` nest. Each emit still type-checks, drops caches, and runs handlers. One re-check runs when the outermost batch ends (`batch_begin` / `batch_end` in the trace).

## Save and replay

`save_state` does not store the event log. Load restores facts, roles, quests, and RNG. Caches start empty. Replay injects `emit`, `emit_rejected`, `batch_begin`, and `batch_end` in order. A mismatched payload fails the trace diff the same way a host answer does.

`debug_dump` and the playtest events line show the last 32 emits. That ring is not saved.

## Diagnostics

| Code | Meaning |
|---|---|
| `E_EVENT_DUPLICATE` | The same event name is declared twice |
| `E_EVENT_UNKNOWN` | `on_event` or `on` names an event the pack does not declare |
| `E_EVENT_ARG` | The declaration shape is wrong, a field name is repeated, or `event.<field>` is not on that event |
| `E_EVENT_TYPE` | A field type is not `bool`, `int`, `float`, or `symbol` |
| `E_RESOLVER_NO_INVALIDATE` | A resolved fact has no `invalidate` mode |
| `E_WAIT_RESOLVER_MODE` | A wait reads a resolved fact whose mode is empty or `per_query` |
