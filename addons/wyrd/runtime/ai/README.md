# ai

`WyrdAIProvider` is the host hook for an AI answer. `Wyrd.ai.request` returns at once. The answer comes back on the main thread through `WyrdAIRequest.reply` or `Wyrd.ai.deliver`. The null provider (`WyrdNullAIProvider`) is registered by default. It answers nothing, and a request on it keeps no pending state.

Results are not used yet in this release; the validation pipeline, cache and presentation follow.

`tools/core_isolation.sh` checks that `addons/wyrd/` has no network code, no thread primitives, and no process calls. A provider never waits.
