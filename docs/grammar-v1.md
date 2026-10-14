# Wyrd grammar v1

**Status: lexical and block rules frozen.** Approved by Corey, 2026-10-14.

Sections 1–6 are the freeze. They cover files, indentation, comments, line tags, escapes, the `language` header, and reserved words. The quest, scene, and facts examples in section 7 are illustrations. Their statement grammar is not frozen and waits for the slice compiler. A multi-line prose syntax is future work and is not part of this freeze. Golden cases for sections 1–6 are in `tests/golden/cases/`.

Examples use only the invented village Gullhaven.

## 1. File and blocks

- Source is UTF-8.
- The first non-blank, non-comment line is the header `language 1` (section 5).
- Blocks are indentation-only. There is no `end` keyword. A block ends when the next line's indent decreases.
- Indentation is two spaces per level. A tab is an error.
- A nested line is indented exactly one level (two spaces) deeper than the line that opened its block.
- Blank lines are ignored. A blank line does not close a block.

## 2. Comments

- `//` starts a comment that runs to the end of the line. There is no block comment.
- `//` is not recognized inside a quoted string.
- `#` is never a comment. A leading `#` is how line tags are spelled.

## 3. Line tags

- A line tag has the form `#line:<id>`.
- `<id>` is a stable identifier. Editing the words of the line does not change the id.
- An id matches `[A-Za-z0-9_]+`. Clarification approved by Corey, 2026-10-14.
- The tag is the last token on the line, except that a `//` comment may follow it.

```wyrd
tavern: The stew is free tonight. #line:a91f // spoken by whoever holds the tavern slot
```

## 4. Escapes

In prose (spoken lines and other unquoted text):

- `{{` is the only escape, and it is a literal `{`.
- A single `{` starts an interpolation. The expression language inside it is not part of this freeze.
- `}` closes an interpolation. A `}` that does not close one is literal text.
- `}}` is not an escape.
- There are no backslash escapes in prose.

`The board lists the price as {{two coins}}.` displays as `The board lists the price as {two coins}.`

Inside a double-quoted title:

- Titles use double quotes. This freeze has no single-quoted strings.
- `\"` is a literal quote.
- `\\` is a literal backslash.
- No other backslash escape is defined.

`"The \"dawn\" crossing"` is the title `The "dawn" crossing`.

## 5. Header

```wyrd
language 1
```

`1` is that integer token. The header is required. A missing header, a quoted form, another number, or any other spelling is an error. There is no default.

## 6. Reserved words

These words are reserved. They are not legal identifiers. This freeze does not define their syntax:

- `document`
- `publishes_by`
- `tier`
- `await_host`
- `believe`
- `declare`
- `retract`

`document`, `publishes_by`, `tier`, and `await_host` name later features (readable documents, published issues, pressure tiers, and a host-modal step). `believe`, `declare`, and `retract` are reserved for belief layers. Writers should not use any of these as quest ids, fact keys, or role names.

## 7. Illustrated blocks

These examples show a `facts` block, a `quest`, and a `scene` with choices, in the shape used for Gullhaven. Words such as `when`, `slot`, and `journal` are part of the illustration. They are not frozen. One spoken line is one source line (section 8).

### Facts

```wyrd
// content/gullhaven/ferry_toll.wyrd
language 1

facts
  player.coins      : int     stored
  ferry.toll_coins  : int     stored
  npc.{id}.alive    : bool    source: world.is_alive
  world.season      : symbol  source: time.season  invalidate: on_event(season_changed)
```

### Quest

```wyrd
quest ferry_toll "The Ferry Toll"
  slot tavern = tavern_owner mode: live
  slot ferry  = ferry_master mode: live

  start when deed_count(player, verb: arrived, place: gullhaven) > 0

  stage gossip
    scene toll.offer_room with tavern
    -> pay_toll

  stage pay_toll
    journal "{holder(ferry).name} at the dock wants a toll before the crossing." #line:j_ft_01
```

### Scene with choices

```wyrd
scene toll.offer_room
  tavern: A room's two coins a night, and the stew is free. #line:a91f // room offer
  * [Take the room] -> took
    ~ do assign_lodging(player, place: gullhaven.tavern) on_fail -> no_room
  * {has_tag(player, local)} [I have a place in town] -> declined
  tavern: The ferry's charging double since the storm, mind. #line:a920
  tavern: The board lists the price as {{two coins}}. #line:a921
```

## 8. Approved decisions

Approved by Corey, 2026-10-14. Items 1–4 and 6–9 are the frozen lexical and block rules (sections 1–6). Item 5 is the current prose rule, with a later syntax explicitly left open. Item 10 keeps the examples unfrozen.

1. **Indentation.** Blocks are indentation-only. A block ends when the indent decreases. There is no `end` keyword.
2. **Indent width.** Two spaces per level. A tab is an error.
3. **Comments.** `//` line comments only. `#` is never a comment.
4. **Comment after a tag.** A `//` comment may follow a `#line:` tag.
5. **Spoken lines.** One source line per spoken line for now. A multi-line or wrap syntax may be added later. That syntax is future work and is not part of this freeze.
6. **Prose escapes.** `{{` is the only escape for `{`. A stray `}` is literal. There is no `}}` escape and no backslash escape in prose.
7. **Titles.** Inside double-quoted titles, `\"` escapes a quote and `\\` escapes a backslash.
8. **Header.** `language 1` is required. Anything else is an error.
9. **Reserved words.** `document`, `publishes_by`, `tier`, `await_host`, plus `believe`, `declare`, and `retract` for belief layers. No syntax for them is defined here.
10. **Examples.** The quest, scene, and facts examples remain illustrations until the slice compiler.
