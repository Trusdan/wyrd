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
  bucket_poured(actor: symbol, place: symbol) leaves: harbor.deck_wet = true decays 60
```

`leaves: <fact> = <value>` writes that stored fact into `world` when the event is emitted. `decays <minutes>` is a positive count of game minutes. Omit it and the fact stays. The fact must be a concrete stored key. A pattern, a resolved fact, a type mismatch, a field named `witnesses`, or `decays` that is not a positive integer is a diagnostic (`E_EVENT_ARG`, `E_UNKNOWN_FACT`, `E_WRITE_RESOLVED`, or `E_WRITE_TYPE`). There is no separate evidence store.

`emit` may pass `witnesses` beside the declared fields. An array of `{id, mode}` uses the deed modes: `saw` writes `known/<id>`, and `heard` or `inferred` writes `believed/<id>`. An empty mode skips that witness. `witnesses: auto` calls `WyrdSpatialAdapter.witnesses_of`, then `perceive`, with `actor`, then `target` or `object`, then `place` or that same target. A missing `witnesses` key writes no witness layers. A bad witness list is `push_error` and the emit still leaves the world fact.

The deadline is cleared on `tick` once `now_minutes()` reaches it, and only when the world value is still the evidence value. `known` and `believed` stay. Re-emitting replaces the deadline for that fact. `save_state` stores the deadlines in `facts.evidence` when any exist. Schema stays 2. `notice_evidence(observer, place)` runs `perceive` for evidence still at that place and writes the same layers. It does not clear the world fact.

`invalidate: on_event(name)` must name an event declared in the pack. `per_query` never caches. `poll(minutes)` is unchanged. A resolved fact with no invalidate mode is `E_RESOLVER_NO_INVALIDATE`.

## `on` handlers

Only a stage may say `on <event> where <condition>:`. The block is effects and `->` transitions, in source order. `event.<field>` is a readonly binding in that `where` and in those nested expressions. It is not stored unless an effect `set`s a fact. The same stage runs at most one matching handler per emit. A transition does not run the destination stage's handlers for that emit.

An open scene is not aborted when an event arrives. The next line, choice, or wait sees the new values. A holder leaving a passed slot still aborts on the role change. A dead holder aborts on the next `Wyrd.tick`. Authors who need a hard interrupt call `dialogue.abort`.

## Emit

`Wyrd.events.emit(name, payload)` checks the payload against the loaded schema. `witnesses` is not a declared field. A failure is `push_error`, trace kind `emit_rejected`, and no invalidation. Success traces `emit` with the name, payload, game time, invalidated keys, and the condition indexes re-checked, in ascending index order. Only dependents are re-checked. Each witness adds one `event_witness` line: `wyrd event_witness agent=%s mode=%s event=%s key=%s value=%s`. Each evidence write adds one `evidence` line: `wyrd evidence event=%s key=%s value=%s until=%s`. `until` is empty when the fact does not decay. Both lines carry `who` and `key` for the trace prefix. The evidence line's `who` is empty.

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
