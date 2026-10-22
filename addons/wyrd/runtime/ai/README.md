# ai

`WyrdAIProvider` is the host hook for an AI answer. `Wyrd.ai.request` returns at once. The answer comes back on the main thread through `WyrdAIRequest.reply` or `Wyrd.ai.deliver`. The null provider (`WyrdNullAIProvider`) is registered by default. It answers nothing, and a request on it keeps no pending state.

`Wyrd.ai.packet_for_line` builds the context packet for an opted-in line. It does not send a request. The packet is version `v: 1` and holds only these fields:

- `text`, the authored line in the current locale
- `speaker`, when the speaker is a real entity: `id`, `name`, and the roles the player may know. `any`, `narrator`, and an empty speaker omit the block. A role the player has not been told is left out
- `facts`, the `ai_context` keys the player knows, in source order, with the known value (or the holder id for a revealed `role.<id>.holder` key). A key the player has not learned is dropped, including every resolved fact
- `entities`, the speaker and every fact value that is an entity, sorted by id
- `line_ids`, `kind`

Facts carry no secrecy name and no public marker, so this release includes only facts the player knows. A world value the player does not know never enters the packet. Widening that needs a design change.

`WyrdAIPacket.canonical` is the packet as JSON with sorted keys and no extra whitespace.

`Wyrd.ai.cache_key` is 16 lowercase hex digits: FNV-1a 64 of the kind, that canonical JSON, the provider id, the provider's prompt version, and the locale, folded with `WyrdHash.combine`. Constraints are not part of the key. A host that sends the same packet under different constraints should vary the packet. A sent request stores the key on `WyrdAIRequest.key` before the provider runs. A provider may use it, for example as a seed.

Only a result whose verdict is `-` is cached. The cache keeps at most `WyrdConfig.ai_cache_max` entries (default 256). The oldest inserted is evicted first. Re-inserting a key replaces its text and makes it the newest. `0` or less stores nothing. Lowering the cap takes effect at the next insert or load. The cache survives a provider change, a locale change, and turning the hook off, because the key already separates those. `start_new_game` clears it. `WyrdConfig.ai_save_cache` (default true) writes an optional top-level `ai` save key when the cache is not empty: `{v: 1, cache: [{k, t}, ...]}`, oldest first. Schema stays 4. An older loader ignores the key. A malformed key warns `W_SAVE_AI` and is ignored. Open requests are never saved.

Wyrd sends `bark_paraphrase` requests when a scene opens (its opted-in spoken lines, including a divert, under the root scene id) and when a topic menu opens (the eligible storylets' opted-in lines, line sets included, a scene body skipped). At most `WyrdConfig.ai_max_inflight` requests are open at once (default 4). `0` or less turns that prefetch off and logs nothing. Host requests count toward the cap and are never refused by it. A cached key or a key already open is not sent again. The speaker passed to the packet is the id the view will show, or empty for `narrator` and an empty speaker, so the prefetch key and the display key match. A host request has an empty owner. A scene prefetch is owned by `scene:<root>`. A topic prefetch is owned by `topic:<npc>`. The owner is not part of the cache key.

AI text is used only when `WyrdAI.locale_ok` passes: the provider's `locales()` lists the current locale, or the text before its first `_`. The null provider never passes. At display, an opted-in line sets `WyrdLineView.text_source` to `ai` on a cache hit and to `authored` otherwise (`off`, `locale`, `waiting`, `rejected`, or `miss`). Only `text` changes. The line id, tags, audio, speaker, and choices stay the authored ones. Dialogue never waits. A line that is not opted in is left alone and logs no `ai_use`.

Requests still open when their scene ends are cancelled (`reason=scene_end`) and kept on a late list. Opening another topic menu does the same for the previous topic's requests (`reason=superseded`). A result that arrives after that is validated and cached when it passes (`ai_result rule=late`) and does not change a view already emitted. The next showing of that line can be a hit. The late list keeps at most `max(ai_max_inflight, 1)` entries and is dropped with the open requests (`off`, `provider`, `new_game`, `load`). It is not saved. Host requests stay open across scene end and topic changes. `can_save()` ignores open and late requests.

`ai_deliver` is a recorded replay input, not a printed line. Replay with those rows shows the same text when the provider answers on a later frame. Replay with them removed shows the authored lines and the same gameplay state. A provider that answers inside `request` records the row during the input that sent it, so replay delivers it only after that input returns, and lines shown during that input can differ.

Barks are not prefetched here. A bark still uses cached text when a request for that line has already been answered.

`Wyrd.ai.deliver` still closes the request and discards the text. After the `ai_result` line (transport: the request was closed, `rule=-`), an accepted delivery is validated. The first failing rule is the `ai_validate` line. The order is:

1. `limits`. Empty text fails. The cap starts at 240 characters, and `constraints.max_chars` can only lower it. A non-empty authored fallback lowers it again to twice that fallback's length. Newlines, control characters, zero-width characters, and `{ } # [ ] < >` fail. The validator does not edit the text.
2. `names`. An uppercase display name used as a whole word or phrase must name an entity already in the packet.
3. `banned`. `WyrdConfig.ai_banned_terms`, case-insensitive whole words or phrases. Empty entries are ignored. The list is not saved.
4. `spoiler`. Stored world values the player does not know, their spaced form, the entity's display name, and unrevealed secret role ids. The secrecy fact is skipped. Resolved facts are not read.
5. `classifier`. Optional. Without one, this step passes.

`Wyrd.ai.register_classifier` sets one `fn(text, kind, packet) -> bool`. It runs on the main thread, synchronously, and must return exactly `true`. Any other return, or a classifier whose object was freed, fails the classifier rule. `Callable()` clears it. It is not saved, and it survives a new game and a load.

The authored line is the fallback: `packet.text`, or for `journal_summary` the frozen `packet.entries` joined with newlines. That text shows on a cache miss, while a request is unanswered, when AI is off or the null provider is active, when the current locale is not in the provider's `locales()`, on a provider error, and on any validation failure.

Host-called kinds (`epilogue_stitch`, `tts_prep`) keep the packet the host passed to `request`. Their results are validated against that packet.

`tools/core_isolation.sh` checks that `addons/wyrd/` has no network code, no thread primitives, and no process calls. A provider never waits.
