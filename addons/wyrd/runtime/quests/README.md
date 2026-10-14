# quests

`WyrdQuestRunner` is the facade's `quests` object.

Statuses: `dormant`, `available`, `active`, `completed`, `failed`, `abandoned`, `unavailable`. A true `start when` becomes `available` and then `active` in the same check. There is no accept step.

Entry steps (journal, effect, scene offer) run in source order, once. A variant whose slot state matches replaces that body. `on_empty: wait` holds the stage when a slot is empty and no variant matched.

`waiting_reason` is `host:<screen>`, `scene:<id>`, `waits_until: <text>`, `on_empty`, or empty.

`request_host_step` blocks the stage until `complete_host_step`. The grammar statement `await_host` is a proposal and is not parsed.
