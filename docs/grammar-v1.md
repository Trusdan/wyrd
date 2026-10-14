# Wyrd grammar v1 (draft)

**Status: draft for approval. This pull request does not freeze the grammar.**

The lexical rules below are the default proposal: indentation-scoped blocks, `//` comments, `#line:` tags at the end of a line, `{{` as the escape for `{`, and a `language 1` header. Statement grammar (conditions, effects, quests, scenes) is illustrated so the shape is reviewable. It is not a parser spec.

Examples use only the invented village Gullhaven.

## 1. File

- Source is UTF-8.
- The first non-blank, non-comment line is the header `language 1`.
- Blank lines are ignored. A blank line does not close a block.
- Indentation uses spaces, two per level. A tab is an error under this proposal.
- A nested line is indented exactly one level deeper than the line that opened its block.

## 2. Comments

- `//` starts a comment that runs to the end of the line.
- Comments are not recognized inside a quoted string.
- `#` does not start a comment. A leading `#` is how line tags are spelled, and a comment marker would be ambiguous next to them.

## 3. Line tags

- A line tag has the form `#line:<id>` and is the last token on the line.
- `<id>` is a stable identifier. Editing the words of the line does not change the id.
- This draft allows a `//` comment after the tag (`#line:a91f // note`). That is an open choice below.

## 4. Braces

- `{{` in text is a literal `{`.
- A single `{` starts an interpolation. The expression language inside it is not defined in this draft.
- `}` closes an interpolation. A `}` that does not close one is literal text, so `}}` is not an escape.

`The board lists the price as {{two coins}}.` displays as `The board lists the price as {two coins}.`

## 5. Header

```wyrd
language 1
```

`1` is an integer. This draft does not define a quoted form, a minor version, or a default when the header is missing. The proposal is that a missing or unknown header is an error.

## 6. Reserved words

These words are reserved. They are not legal identifiers in this draft, and this draft does not define their syntax:

- `document`
- `publishes_by`
- `tier`
- `await_host`

They name later features (readable documents, published issues, pressure tiers, and a host-modal step). Writers should not use them as quest ids, fact keys, or role names.

## 7. Illustrated blocks

Indentation scopes each block. The examples follow the shape already used for Gullhaven in the design notes: a `facts` schema, a `quest` with stages, and a `scene` with choices. Words such as `when`, `slot`, and `journal` are part of that illustration. Their full grammar waits for the slice compiler.

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
  tavern: A room's two coins a night, and the stew is free. #line:a91f
  * [Take the room] -> took
    ~ do assign_lodging(player, place: gullhaven.tavern) on_fail -> no_room
  * {has_tag(player, local)} [I have a place in town] -> declined
  tavern: The ferry's charging double since the storm, mind. #line:a920
  tavern: The board lists the price as {{two coins}}. #line:a921
```

## 8. Open choices

These need a decision before the grammar can be called frozen. The proposal in sections 1–5 is the default, not a lock.

1. **Indentation versus an explicit `end`.** The proposal is indentation only. Confirm that a block ends when the indent decreases, and that `end` is not a keyword.
2. **Indent width and tabs.** The proposal is two spaces, and a tab is an error. Four spaces, or tabs only, are the alternatives.
3. **Comments.** The proposal is `//` line comments only, with no block comment. Confirm that `#` is never a comment.
4. **Comment after a tag.** The proposal allows `//` after `#line:<id>`. The alternative is that the tag must be the final characters on the line.
5. **Multi-line prose.** Not decided. This draft requires one source line per spoken line. A continuation marker, or a quoted block, is still open. This is the item the default proposal does not settle.
6. **Brace escape.** The proposal is that `{{` is the only escape, and that a stray `}` is literal. Confirm there is no `}}` escape and no backslash escape in prose.
7. **Quoted strings.** Titles use double quotes in the examples (`"The Ferry Toll"`). Escaping a quote inside a title is open. This draft has no single-quoted strings.
8. **Header.** The proposal is that `language 1` is required and that anything else is an error. An optional header that defaults to 1 is the alternative.
9. **Reserved list.** Confirm that `document`, `publishes_by`, `tier`, and `await_host` are the complete reserved list for this draft.
10. **What this draft freezes, once approved.** The proposal is to freeze only the rules in sections 1–6. The quest, scene, and facts illustrations stay examples until the slice compiler specifies them.
