# Epilogues

The end of a story should be able to look back at the journal and the deeds, without a special epilogue syntax.

Language 1 has no epilogue block. Nothing in the [language reference](../language.md) declares one. An ending is ordinary content: journal lines, deed totals, and, if the host wants a stitched paragraph, a host-called AI kind with a deterministic fallback.

## Content

Journal text is frozen when it is written. [`Wyrd.quests.summary`](../api/WyrdQuestRunner.md#summary) joins those entries in order, or returns validated cached summary text.

From `example/content/gullhaven/harbor_storylets.wyrd`:
```wyrd
quest harbor_ledger "The Dock Ledger"
  start when false
  stage note
    ~ set player.clearance = open
    journal: The dock ledger stays on the bench. #line:j_ledger
```

The toll journal names the holder and the price.

From `example/content/gullhaven/ferry_toll.wyrd`:
```wyrd
    journal: {holder(ferry).name}, the ferry master, at the dock wants {ferry.toll_coins} coins before the crossing. #line:j_ft_01
```

Deed totals use `deed_score`. The committed lines that spell a window are comments, not a live condition in Gullhaven.

From `tests/golden/conditions/c_units.wyrd`:
```wyrd
// @value deed_score(player, within: 14d)
// @value deed_score(player, within: 6h)
// @value deed_score(player, within: 30m)
```

The call is documented in [Built-ins](../language.md#built-ins). `deed_count` is the same filters, returning an int.

## Host side

`summary` does not send an AI request. [`summary_source`](../api/WyrdQuestRunner.md#summary_source) is `ai` when the summary would return cached text now, and it sends nothing.

`epilogue_stitch` is a host-called AI kind. [`request`](../api/WyrdAI.md#request) returns 0 when the kind is unknown, the hook is off, or the provider is null, including the null provider registered by default. [`host_text`](../api/WyrdAI.md#host_text) is the read. It sends nothing and logs nothing. It returns the cached text when AI is active and the locale passes, and the fallback otherwise. Pass the journal summary as that fallback so the ending still has words.

```gdscript
var journal := Wyrd.quests.summary(quest_id)
var request_id := Wyrd.ai.request(&"epilogue_stitch", packet)
var ending := Wyrd.ai.host_text(&"epilogue_stitch", packet, journal)
```

`request_id` is 0 while the null provider is in place, and `ending` is `journal`.

## What to test

Write a journal line, call `summary`, and check the frozen sentence is in the result. With the null provider, `host_text` returns that same string and `request` returns 0. With a provider registered, a delivered answer can replace the fallback, and a failed validation leaves the fallback in place.
