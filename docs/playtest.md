# Play the Gullhaven test

This page is for someone who has not used Godot. Gullhaven is an invented fishing village used only as an example. It is not from another game.

You will install Godot, open this project, press Play, and walk a short conversation. The window is plain text. There is no art.

## 1. Install Godot 4.7.2

Use the standard Godot, not the .NET build. The .NET build has `mono` or `.NET` in the file name. Do not use that one.

Open the 4.7.2 archive page:

https://godotengine.org/download/archive/4.7.2-stable/

Download the zip for your computer:

- Windows: `Godot_v4.7.2-stable_win64.exe.zip`
- macOS: `Godot_v4.7.2-stable_macos.universal.zip`
- Linux: `Godot_v4.7.2-stable_linux.x86_64.zip`

Unzip it. Run the Godot program inside. On macOS, if the system blocks it, use the usual Open action from the Finder shortcut menu.

Check the version. In Godot, open the Help menu and choose About. The version line must start with **4.7.2**. If it says 4.3, 4.4, 4.5, 4.6, or 4.8, quit and use the 4.7.2 program instead.

## 2. Get the project

The project is the public repository `Trusdan/wyrd`:

https://github.com/Trusdan/wyrd

Either way works.

- ZIP: on that page, choose Code, then Download ZIP. Unzip it. You should see a folder named `wyrd-main` (or `wyrd`) that contains a file named `project.godot`.
- GitHub Desktop: install GitHub Desktop, choose Clone repository, enter `Trusdan/wyrd`, and clone it. Open the folder it created and confirm `project.godot` is there.

## 3. Import the project

1. Start Godot 4.7.2.
2. In the Project Manager, choose Import.
3. Select the `project.godot` file inside the folder from step 2. Import the folder that contains `project.godot`, not a folder above it and not a file inside `addons`.
4. Choose Import & Edit.

The first import can take a minute. Godot writes a `.godot` folder next to `project.godot`. That is normal. If a one-time import notice appears, continue.

The play scene is already set: `example/playtest/gullhaven_playtest.tscn`. If Godot asks you to pick a main scene, choose that file.

## 4. Press Play

Press **F5**, or the Play button at the top right. (F6 plays whatever scene is open in the editor. F5 plays the main scene, which is the one you want.)

A window opens at 1600×900. Drag the edges to resize it. The panels stay inside the window and grow with it, including at 1280×720 and 1920×1080. The journal pane and the fact pane start short, so Continue, the choice buttons, the controls, the route list, Start route, Tell secret, and Load in next version stay inside the window. Those panes grow when the window is taller. The journal and the fact list scroll when the text is taller than the pane.

The status line says "Press New game." You will see:

- A seed box (it starts at `1`) and buttons: New game, Advance time, Save, Load, Load in next version, Reset, Abort scene.
- A second button row: Emit alive, Batch world, Strike bell, Tell secret.
- A route list under that row: a menu, **Start route**, and a hint. Pick a route and press **Start route**. That resets the toggles, sets the ones that route needs, and presses New game. The hint names the next presses. Abort scene, Watch alive, Batch world, and Strike bell say "This step comes later" because you press those after New game.
- Toggles: Ferry master alive, Local tag, Lodging available, Notice succeeds, Season storm, Apprentice ready, Short on coins, Voice, Watch alive, Local AI flavor. Local AI flavor starts off. See [AI flavor](ai.md).
- An events line under the toggles. It lists recent world events and ends with `flush 1` after an emit or a batch. `flush 0` means nothing has been emitted since New game or Load.
- A dialogue panel: speaker, text, Continue. Space or Enter also continues.
- Choice buttons. A choice you cannot take is grey and shows the reason in parentheses.
- A journal. Quests that have entries get a header, `<quest title> — <status>`, then the dated lines. Each entry still starts with a game time such as `day 1, 00:00`.
- A quest summary that stays on screen: the quest title, the stage, the status, the outcome, the waiting reason, and one row per slot. A slot row is the role title, the current holder's personal name, and the slot state. One more row names the secret role. Under that, a load report and a fact list with a filter box. Before any load the report says `Content loaded.` After a load with no rows it says `No changes.` The filter keeps rows whose name or value contains what you type. A fact that changed on the last press is highlighted. A fact with no value shows `absent`. The season is one of those until Season storm is on, so the row reads `world world.season = absent`. The summary does not scroll away when the fact list does.

Leave the toggles as they are for the first walk. Ferry master alive, Lodging available, and Notice succeeds start on. The others start off.

New game sets `world.storm_heard` before the quest starts. The lookout is `cast(world.storm_heard)`. With that rumour set, the cast picks once from the entities the play host registered. At seed 1 the pick is the dock apprentice, so the speaker label is **Nia**. The storm watcher role stays with the watcher. If the rumour is still false, nobody passes, the slot is empty, and `on_empty: wait` holds the quest at `gossip`.

The pack also contains The Harbor Guild. It stays dormant on this walk. It starts after a deed `asked_guild` at Gullhaven. That quest is the guild-assigned factor, the elected reeve, the barred visitor, and the unwilling factor. The ferry lock has a `locked_gone` variant for the master who held it.

The Toll Tale stays dormant too. It starts after a deed `asked_council` at Gullhaven. The harbor council has declared the toll lost at sea. A fisher believes it was stolen. `dock_hand` inherits the council line and will not sit while that is the official line. The player believing it was stolen bars the hearing. One witness can hear the tale through a wall, and one statement fails when the listener does not trust the fisher.

## 5. Walk one route

This walk is the **Defaults** route. The route list can press New game for you.

1. Press **New game**.
2. The speaker is **innkeeper**. The text is: "A room's two coins a night, and the stew is free."
3. Press **Continue**. The speaker is **Nia**: "The headland bell rang twice before the rain."
4. Continue. The speaker is **Nia**: "Bram, the ferry master, is on the dock."
5. Continue. The speaker is **bell**: "The bell notes the tide."
6. One choice is shown: **Take the room**. Press it.
7. The innkeeper says: "The ferry's charging double since the storm, mind."
8. Continue. The speaker is **Bram**: "Two coins, and the boat will cross."
9. Continue. The speaker is **narrator**: "The boat leaves the dock."
10. Continue once more. Continue becomes disabled. The last line stays on screen.

On the right:

- The journal has a header `The Ferry Toll — active`, then one line dated `day 1, 00:00`: "Bram, the ferry master, at the dock wants 2 coins before the crossing." That sentence stays as it was written. Bram is the personal name the play host gave the person in the ferry slot. The words "the ferry master" are written in the example. A role has no title field, so the game does not look that phrase up.
- The fact list shows `player.coins` as `2` and `harbor.room_taken` as `true`. A row whose value changed on the last press is highlighted. Rows that did not change stay plain. Resolved facts also have a cache row, such as `cache world.season = on_event season_changed`. The value is the cache mode and the last event that dropped it. `per_query` facts are never cached.
- The summary says `The Ferry Toll`, stage `pay_toll`, status `active`, and outcome `absent`. A waiting row shows the time check. That block stays put while the fact list scrolls.
- Each slot row is `slot <slot> — <role title> — <holder name> — <state>`. The title is the role id with spaces (`ferry_master` becomes `ferry master`), because a role has no title field. The state is the runtime slot state, not the slot mode in the quest file. `default` means the first holder is in the slot. `successor` means someone else took it. `empty` means nobody holds it. `hostile` means disposition is too low. After this walk the rows are `slot tavern — tavern owner — innkeeper — default`, `slot ferry — ferry master — Bram — default`, and `slot lookout — storm watcher — Nia — default`. Nia is the cast pick, not the storm watcher's personal name.

Press **Advance time**. The status line shows `day 1, 01:00`. The stage becomes `cross`. The fact `world.storm_heard` becomes `true`. The dock conversation opens again: "Two coins, and the boat will cross." then "The boat leaves the dock." Continue through both. The quest status becomes `completed`.

## 6. Every other route

Press **Reset** or **New game** between routes. Set the toggles before you press the choice, as the table says. Expected lines are the words on screen.

| What you set | What you should see |
|---|---|
| Defaults, as in section 5 | Innkeeper room line, Nia on "The headland bell rang twice before the rain." and "Bram, the ferry master, is on the dock.", bell, then Take the room, then the dock lines spoken by **Bram**. Coins go from 4 to 2. Journal `day 1, 00:00`. Advance time moves the stage to `cross` and finishes the quest after the dock lines. |
| **Local tag** on before New game | A second choice appears: "I have a place in town". Press it. Coins stay 4. The dock lines still play. The stage is still `pay_toll` and the journal still appears. |
| **Lodging available** off before Take the room | After Take the room the innkeeper says "No room left tonight." and "The board lists the price as {two coins}}." The second line really does show a single `{` and an extra `}`. Coins stay 4. The stage is `pay_toll`. |
| **Notice succeeds** off before Take the room | The room conversation plays as in section 5, then the tavern conversation is offered again and the stage is `gossip`. The journal already has Bram's toll line. |
| **Ferry master gone** (**Ferry master alive** off before New game, or after New game before you continue to the dock line) | Nia says "The dock is empty." You do not see a line with `{?holder(ferry).name}`. Take the room. The journal says "The dock is empty, so the crossing waits." dated `day 1, 00:00`. The stage returns to `gossip` and then waits with no new scene. The fact list shows `alive ferry_master = false`. The ferry slot row is `slot ferry — ferry master — none — empty`. |
| **Successor** (**Apprentice ready** on before New game, then **Ferry master alive** off before Take the room) | The successor is Nia, a different person from Bram. Nia also speaks the lookout line "Nia, the ferry master, is on the dock." The journal says "Nia, the ferry master, at the dock wants 2 coins before the crossing." The ferry slot row is `slot ferry — ferry master — Nia — successor`. Advance time reaches `cross`. The dock speaker is **Nia**, and the quest completes. |
| **Season storm** on before New game, or before you continue past "Bram, the ferry master, is on the dock." | An extra line appears before the bell: narrator, "The season smells like rain." |
| **Abort scene** while the first lines are up | The conversation stops. The status says you can save. The stage stays `gossip` and the tavern scene is offered again. The last line stays visible. |
| **Short on coins** on before the choices appear | "Take the room (short on coins)" is grey and cannot be pressed. |
| **Watch alive** on before New game, then **Emit alive** while the innkeeper line is up | The conversation stays on that line. Continue then shows narrator: "The ferry master is gone." The fact list shows `alive ferry_master = false` and `cache npc.ferry_master.alive = on_event entity_alive_changed`. The ferry slot is still filled. Emit alive does not vacate the role. |
| **Batch world** after New game | The events line shows `season_changed` and `mechanism_state`, then `flush 1`. The season fact becomes `storm`. The journal gains "The harbor bell was struck." |
| **Strike bell** after New game, then Strike bell again | The journal says "The harbor bell was struck." `harbor.bell_count` is `1` and stays `1` the second time. The innkeeper line stays up. |
| **Tell secret** after New game | Before the press, the quest summary says `secret role smugglers_contact — holder hidden`. Press **Tell secret**. The row becomes `secret role smugglers_contact — watcher (told)`. Save and Load keep that row. `roles.tell` and `roles.revealed` are Experimental host calls. |
| **Next version** after the journal appears | Press **Save**, then **Load in next version**. The status says `Next version: ferry stage renamed pay_toll → toll_due.` The stage is `toll_due`. The load report lists the alias rows from `pay_toll` to `toll_due`. |

## 7. Save and load

Finish a conversation first. Save is refused while lines are still advancing. The status says "Can't save during a conversation." Abort scene if you need to save in the middle.

1. Play section 5 until the journal appears and Continue is disabled. Do not press Advance time yet.
2. Press **Save**. The status says the save is in memory and in `user://playtest_save.json`.
3. Press **Advance time**. The dock lines open again and the clock moves to `day 1, 01:00`.
4. Press **Load**. That conversation closes. Coins are 2 again, the stage is `pay_toll`, and the journal line is back. The clock returns to the saved time. The events line clears. World events are not stored in the save. The load report says `No changes.`
5. Press **Load in next version** after a save. The playtest boots the later Gullhaven pack, loads the slot, and the status says `Next version: ferry stage renamed pay_toll → toll_due.` **Reset** or **New game** returns to Gullhaven. An empty slot says `Save first.`

**Reset** starts a fresh game at seed 0 and deletes that save file.

## 8. Voice

1. Turn **Voice** on.
2. Press **New game**.
3. The innkeeper line is on screen, and a short tone plays.
4. Turn **Voice** off and press **New game** again.
5. The same words are on screen. No tone plays.

The words do not wait for the tone, and the tone does not turn the page. Continue is what moves to the next line.

## 9. Automated tests (optional)

You do not need these to play.

In the Godot editor, open the GUT panel at the bottom and choose Run All.

From a terminal, in the project folder, with `godot` on your PATH:

```bash
tools/run_tests.sh
```

The script imports the project and runs the same tests. It is finished when it prints `All tests passed!`.

## 10. If something looks wrong

- Open the bottom panel and look at **Output** and **Debugger**. A red script error there is the useful clue.
- Help → About must say 4.7.2. A different Godot will refuse this project or fail the import.
- The project already uses the compatibility renderer. You do not need to change it. If the window is blank, confirm Project → Project Settings → Rendering → Renderer is `gl_compatibility`.
- You imported the folder that contains `project.godot`. If the FileSystem dock does not show `addons`, `example`, and `project.godot` at the top, close the project and import the right folder.
- Project → Project Settings → Plugins should list GUT and Wyrd. Tests need GUT. Playing the scene does not.
- F5 runs the main scene. If Play opens an empty editor view, Project → Project Settings → Application → Run → Main Scene should be `example/playtest/gullhaven_playtest.tscn`.
