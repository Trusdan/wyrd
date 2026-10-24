# Walk the ferry quest

This page is for someone who has already done [Play the Gullhaven test](playtest.md) sections 1–4: Godot is installed, the project is imported, and F5 opens the playtest. Gullhaven is an invented fishing village. It is not from a host game.

## 1. What you'll do

You will play The Ferry Toll once, read the quest file beside the window, try two more routes, save and load, tell a secret, and load that save into a later version of the same pack.

Install and F5 are in [playtest.md](playtest.md). Leave the toggles at their defaults for the first walk. The route list under the world buttons can set those toggles for you: choose **Defaults** and press **Start route**.

## 2. The quest file

The ferry quest is one file. It names three slots, says what an empty slot does, names the pack it needs, and starts after the player arrives.

From `example/content/gullhaven/ferry_toll.wyrd`:
```wyrd
quest ferry_toll "The Ferry Toll"
  slot tavern  = tavern_owner mode: live
  slot ferry   = ferry_master mode: locked_at(pay_toll)
  slot lookout = storm_watcher mode: cast(world.storm_heard)
  on_empty: wait
  requires: [pack.harbor]
  start when deed_count(player, verb: arrived, place: gullhaven) > 0
```

`live` follows whoever holds the role now. `locked_at(pay_toll)` freezes the ferry holder when the quest reaches that stage. `cast(world.storm_heard)` picks the lookout once, from entities that pass, when the rumour is set. `on_empty: wait` holds the quest when a slot has nobody. `requires` names the pack. `start when` is the deed count that opens the quest. New game records `arrived` at Gullhaven, so the quest starts on the first tick.

## 3. The first stage

Press **New game**. The seed in the box is `1`.

The speaker is **innkeeper**. The text is: "A room's two coins a night, and the stew is free."

Press **Continue**. The speaker is **Nia**: "The headland bell rang twice before the rain."

Continue. The speaker is **Nia**: "Bram, the ferry master, is on the dock."

Continue. The speaker is **bell**: "The bell notes the tide."

One choice is shown: **Take the room**. That choice is this block. The braces are the rule that greys the choice out, and the words in quotes are the reason.

From `example/content/gullhaven/harbor_scenes.wyrd`:
```wyrd
  * [Take the room] show_disabled_when {player.coins < 2} "short on coins" -> took #line:c_room
    ~ do assign_lodging(player, place: gullhaven.tavern) on_fail -> no_room
    ~ set player.coins = player.coins - 2
    ~ set harbor.room_taken = true
```

Press **Take the room**. The innkeeper says: "The ferry's charging double since the storm, mind." Continue. The speaker is **Bram**: "Two coins, and the boat will cross." Continue. The speaker is **narrator**: "The boat leaves the dock." Continue once more. Continue becomes disabled.

On the right, the journal groups entries under a header. The header is the quest title and the status. The entry under it keeps the date and the text:

- `The Ferry Toll — active`
- `day 1, 00:00  Bram, the ferry master, at the dock wants 2 coins before the crossing.`

The quest summary stays on screen. After this walk the slot rows are:

- `slot tavern — tavern owner — innkeeper — default`
- `slot ferry — ferry master — Bram — default`
- `slot lookout — storm watcher — Nia — default`

The summary also says `quest The Ferry Toll`, `stage pay_toll`, and `status active`.

## 4. The toll stage

`pay_toll` waits until the player has the coins, counts the toll, and writes the journal line you just saw.

From `example/content/gullhaven/ferry_toll.wyrd`:
```wyrd
  stage pay_toll
    waits_until player.coins >= 2 and ferry.toll_coins >= 0
    // Count the toll before the journal so the entry can show it.
    // "the ferry master" is prose. A role has no title field.
    ~ inc ferry.toll_coins by 2
    journal: {holder(ferry).name}, the ferry master, at the dock wants {ferry.toll_coins} coins before the crossing. #line:j_ft_01
```

Press **Advance time**. The stage becomes `cross`. The dock lines open again. Continue through "Two coins, and the boat will cross." and "The boat leaves the dock." The summary then says `stage cross` and `status completed`.

## 5. Two more routes

The route list sets the toggles, then presses New game. Choose **Ferry master gone** and press **Start route**. Continue to **Take the room**. Nia says "The dock is empty." The journal entry is `day 1, 00:00  The dock is empty, so the crossing waits.` The ferry slot row is `slot ferry — ferry master — none — empty`.

That entry is the empty variant:

From `example/content/gullhaven/ferry_toll.wyrd`:
```wyrd
    variant ferry.empty:
      journal: The dock is empty, so the crossing waits. #line:j_ft_empty
      -> gossip
```

Choose **Successor** and press **Start route**. The ferry master is gone and the apprentice is ready, so Nia takes the chair. The journal entry is `day 1, 00:00  Nia, the ferry master, at the dock wants 2 coins before the crossing.` The ferry slot row is `slot ferry — ferry master — Nia — successor`.

## 6. Save and load

Before any load, the load-report panel under the quest summary says `Content loaded.`

Play section 3 until Continue is disabled. Do not press Advance time yet. Press **Save**, then press **Load**. The status says `Loaded.` The load-report panel says `No changes.` Coins are 2, the stage is `pay_toll`, and the journal header and entry are back.

## 7. The secret role

The storm watcher holds a public role and a secret role at once. Nothing in the quest text names the secret role. Content cannot branch on who was told.

From `example/content/gullhaven/harbor_roles.wyrd`:
```wyrd
role smugglers_contact
  visibility: secret
  default_holder: storm_watcher
  succession: host_decides
  vacancy: hold
```

Press **New game**, then **Tell secret**. The quest summary row changes.

- Before the press: `secret role smugglers_contact — holder hidden`
- After the press: `secret role smugglers_contact — watcher (told)`

`roles.tell` is a host call, and it is Experimental. `roles.revealed` is how the playtest reads that the player was told, and it is Experimental too. Finish the lines or press Abort scene before Save. Save and Load keep the tell: the row still ends with `(told)`.

## 8. A renamed stage

Gullhaven itself has no `was:`. A later copy of the pack, `example/versions/gullhaven_next/`, renames one stage and keeps the old id as an alias.

From `example/versions/gullhaven_next/ferry_toll.wyrd`:
```wyrd
  stage toll_due was: pay_toll
```

Play section 3 until Continue is disabled, and press **Save**. Then press **Load in next version**. The status says `Next version: ferry stage renamed pay_toll → toll_due.` The load report lists:

- `alias stage:ferry_toll pay_toll → toll_due ×1`
- `alias trail:ferry_toll:pay_toll pay_toll → toll_due ×1`
- a `manifest` row whose code is `W_SAVE_MANIFEST`

Reset or New game returns to Gullhaven. The same load is `tests/migration/test_gullhaven_next.gd`. How aliases load is [Save migration](cookbook/migration.md).

## 9. Check the content

From the project folder:

```bash
godot --headless --path . -s res://addons/wyrd/cli/wyrd_cli.gd -- check --strict --manifest example/content/gullhaven/harbor.wyrdmanifest.tres
```

The strict check exits 1. The diagnostics are one `warning[W_CLAIM]` in `harbor_tale.wyrd`, plus `info[I_STORYLET_SCORE]` and `info[I_TEMPLATE_SCORE]`. There is no other diagnostic. The side-pack manifest prints the same list.

## 10. Where next

The rest of the language is the [language reference](language.md). Short recipes are in the [cookbook](cookbook/index.md). The order a host should call is the [host checklist](host-checklist.md).
