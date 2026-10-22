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

`Wyrd.ai.deliver` still closes the request and discards the text. After the `ai_result` line (transport: the request was closed, `rule=-`), an accepted delivery is validated. The first failing rule is the `ai_validate` line. The order is:

1. `limits`. Empty text fails. The cap starts at 240 characters, and `constraints.max_chars` can only lower it. A non-empty authored fallback lowers it again to twice that fallback's length. Newlines, control characters, zero-width characters, and `{ } # [ ] < >` fail. The validator does not edit the text.
2. `names`. An uppercase display name used as a whole word or phrase must name an entity already in the packet.
3. `banned`. `WyrdConfig.ai_banned_terms`, case-insensitive whole words or phrases. Empty entries are ignored. The list is not saved.
4. `spoiler`. Stored world values the player does not know, their spaced form, the entity's display name, and unrevealed secret role ids. The secrecy fact is skipped. Resolved facts are not read.
5. `classifier`. Optional. Without one, this step passes.

`Wyrd.ai.register_classifier` sets one `fn(text, kind, packet) -> bool`. It runs on the main thread, synchronously, and must return exactly `true`. Any other return, or a classifier whose object was freed, fails the classifier rule. `Callable()` clears it. It is not saved, and it survives a new game and a load.

The authored line is the fallback: `packet.text`, or for `journal_summary` the frozen `packet.entries` joined with newlines. That text is what would show on a cache miss, while a request is unanswered, when AI is off or the null provider is active, when the current locale is not in the provider's `locales()`, on a provider error, and on any validation failure. This release still shows nothing and caches nothing.

Host-called kinds (`epilogue_stitch`, `tts_prep`) keep the packet the host passed to `request`. Their results are validated against that packet.

`tools/core_isolation.sh` checks that `addons/wyrd/` has no network code, no thread primitives, and no process calls. A provider never waits.
