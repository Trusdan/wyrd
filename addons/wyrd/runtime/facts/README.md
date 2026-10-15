# facts

`WyrdFactStore` keeps stored facts per perspective and a resolver cache.

World and `known/<agent>` are active. Only `known/player` is used by the slice. `believed/` and `held/` stay empty.

A stored write of the wrong type is refused, logged with `push_error`, and recorded as a trace row (`kind`, `key`, `detail`). Resolved facts are not writable. A missing read is null, and a condition comparison of that null is false.

Resolvers come from `source:` (`world.is_alive`, `time.season`). `per_query` is never cached. `on_event(name)` drops on `events.emit` or `invalidate(prefix)`. A pattern key such as `npc.{id}.alive` drops every cached concrete key of that pattern. `poll(minutes)` drops when that many game minutes have passed. An empty invalidate clause is a compile error on content. A hand-built fact with an empty clause stays cached until `invalidate` (`mode` `manual`). `cache_view(key)` reports `cached`, `mode`, and the last invalidate event.

`fact_changed` fires only for prefixes passed to `subscribe`. A `known/` write marks dependents of that key. `remember` writes a `known/` value that is not in the schema; secret role reveals use it.
