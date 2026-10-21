# generator

`Wyrd.generator.offer(source, key, tier, payload)` queues unsaved story pressure. The queue is a FIFO. The same source and key replace tier and payload in place and keep their position. An empty source or key, a tier that is not in `WyrdConfig.pressure_tiers`, or a payload value other than string, number, or bool is rejected. An empty tier list makes every named tier unknown. An empty tier is always accepted.

`pressure_tiers` is an ordered list, lowest first. `tier_rank` is the index, or -1. `tier_matches` is true for an empty offer tier and for a template with no `tier:`. Otherwise the offer's rank must sit between the template's low and high, inclusive. A single name is that name at both ends. Unknown names do not match a tiered template.

A template `on_deed <verb> [where <condition>]` queues an offer when a matching deed is recorded. The key is `<template>:<deed id>`, the source and origin are `deed`, and the tier is empty. The same key replaces. A deed restored by `load_state` does not queue an offer. The queue is cleared by `start_new_game`, `load_content`, and `load_state`. It is not part of the save.

With tracing on, a queued or replaced offer logs `wyrd gen_offer source=… key=… tier=… origin=host|deed template=… queued=<n> replaced=true|false`. A rejected offer does not. Load does not log the line. Replay skips it.

The scheduler's `generate` queue has share 0. One unit calls `take_next` and then `generate_handler` when that handler is set. Pick, cast, and bind are later.
