# Social and reputation

Relationships should move because of what characters did, not because a line assigns a friendship number.

## Content

A deed is an append-only row. The toll records a public, memorable payment.

From `example/content/gullhaven/ferry_toll.wyrd`:
```wyrd
    ~ record deed paid(actor: player, target: ferry, place: gullhaven, tags: [toll], magnitude: 1, witnesses: auto, visibility: public, memorable: true)
```

`adjust baseline` adds a number to the stored baseline of one axis. It does not write a fact or a deed, and it does not clamp.

From `example/content/gullhaven/harbor_scenes.wyrd`:
```wyrd
    ~ start quest dock_errand
    ~ adjust baseline affinity(tavern_owner, player) by 5
    ~ assign role dock_runner to dock_apprentice
```

Disposition is derived. The default is `disposition_default + affinity / 2`, clamped to 0..100. Axes add a configured verb delta times the deed's decayed weight. A half-life is a pair of [`half_life_verbs`](../api/WyrdConfig.md#half_life_verbs) and [`half_life_minutes`](../api/WyrdConfig.md#half_life_minutes) on [`WyrdConfig`](../api/WyrdConfig.md). Reputation is the mean disposition of a group's members toward the subject, and it is not saved. The formula and the cache are on [WyrdSocial](../api/WyrdSocial.md). A host may replace the formula with [`register_disposition_formula`](../api/Wyrd.md#register_disposition_formula).

`deed_score` is the built-in that reads that log. The only committed lines that spell the call are comments in a condition golden.

From `tests/golden/conditions/c_units.wyrd`:
```wyrd
// @value deed_score(player, within: 14d)
// @value deed_score(player, within: 6h)
// @value deed_score(player, within: 30m)
```

The signature, including `verb`, `against`, `place`, `within`, and `tags`, is in [Built-ins](../language.md#built-ins). `within` is a duration. There is no `set_disposition` effect. The compiler rejects it and tells the author to record deeds or use `adjust baseline`.

## Host side

Recording from content needs no host call. A host that records a deed itself uses the deed log behind [`Wyrd.deeds`](../api/Wyrd.md#deeds). Witnesses of a `witnesses: auto` deed come from the [spatial adapter](../adapters.md). Group membership comes from the world adapter.

## What to test

Record the paid deed, read `deed_score` for that actor and verb inside the window, then advance the clock past the verb's half-life and read it again. Adjust the affinity baseline by 5 and check disposition moved and no fact was written. A self edge and a zero adjustment warn and do not change the baseline.
