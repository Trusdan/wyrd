# Topics

The player should be able to ask about something only after play has unlocked it.

## Content

There is no topic declaration. An id is whatever `unlock topic`, `lock topic`, or `scope: topic` uses. Paying the toll unlocks one topic.

From `example/content/gullhaven/ferry_toll.wyrd`:
```wyrd
    ~ record deed paid(actor: player, target: ferry, place: gullhaven, tags: [toll], magnitude: 1, witnesses: auto, visibility: public, memorable: true)
    ~ unlock topic storm_rumour
```

A storylet with `scope: topic` is what [`Wyrd.dialogue.open`](../api/WyrdSceneRunner.md#open) can offer, and what [`ask_topic`](../api/WyrdSceneRunner.md#ask_topic) can run.

From `example/content/gullhaven/harbor_storylets.wyrd`:
```wyrd
storylet harbor_gossip.generic
  scope: topic rumor.ferry_toll
  speaker: any
  - They say the ferry's dear since the storm. #line:sg01
```

The storm line is the storylet for the topic the toll unlocks. It also starts another quest.

From `example/content/gullhaven/harbor_storylets.wyrd`:
```wyrd
storylet harbor_gossip.storm
  scope: topic storm_rumour
  speaker: any
  ai_context: [world.storm_heard]
  ~ start quest dock_rumour
  - The storm took a skiff off the bar. #tag:ai #tag:gossip #line:sg_storm
```

A repeat unlock does not signal again. Locking a topic that is not unlocked is a no-op. The rules are in [Topics](../language.md#topics).

## Host side

`open` returns the sorted unlocked topics that have an eligible storylet for that npc now. It does not record a selection, run effects, or open a scene. `ask_topic` refuses an unknown npc, an open scene, a locked topic, and then no eligible storylet, in that order. A win runs the storylet.

```gdscript
var topics := Wyrd.dialogue.open(npc)
var answer := Wyrd.dialogue.ask_topic(npc, topic)
```

[`topic_unlocked`](../api/Wyrd.md#topic_unlocked) fires when a topic becomes unlocked. [`topic_locked`](../api/Wyrd.md#topic_locked) is experimental.

## What to test

Before the toll, `open` does not include `storm_rumour`. After the unlock effect, it does, and `ask_topic` returns the storm line. Asking while a scene is open is refused. Asking a topic that was never unlocked is refused.
