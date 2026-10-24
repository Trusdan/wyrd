# Barks

A character standing nearby should speak a short line, and should not repeat it on every tick.

## Content

A bark is a storylet with `scope: bark`. The director ignores the scope id for a bark query. `speaker_cooldown` is consulted only for barks.

From `example/content/gullhaven/harbor_storylets.wyrd`:
```wyrd
storylet dock_bark_lantern
  scope: bark
  speaker: ferry
  when: nearby(player, 4m, tag: lantern) > 0
  cooldown: 30m
  - Mind that flame near the ropes. #tag:ai #line:sg04

storylet dock_bark_lantern_carried
  scope: bark
  speaker: ferry
  when: has(player, lantern) and nearby(player, 4m, tag: lantern) > 0
  speaker_cooldown: 10m
  - That lantern in your hand is close to the ropes. #tag:ai #line:sg05
```

`cooldown` is how long this storylet stays ineligible after it is selected. `speaker_cooldown` is how long that speaker stays ineligible for another bark. Both are durations. Zero never excludes. The ranking rules are in [Storylet](../language.md#storylet).

## Host side

When a bark wins, [`bark_ready`](../api/Wyrd.md#bark_ready) fires with a [`WyrdLineView`](../api/WyrdLineView.md). The host renders that line. Wyrd does not draw it.

```gdscript
func _ready() -> void:
	Wyrd.bark_ready.connect(_on_bark)

func _on_bark(line: WyrdLineView) -> void:
	show_line(line)
```

`nearby` needs a [spatial adapter](../adapters.md). A missing adapter makes the count zero, so this `when` stays false.

## What to test

Put the player within 4 metres of a lantern and advance the clock. The lantern bark fires once, then stays quiet for its cooldown. Carry a lantern as well and the second bark can win, subject to the speaker cooldown. Move out of range and neither `when` matches.
