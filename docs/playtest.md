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

A window opens at 1600×900. Drag the edges to resize it. The panels stay inside the window and grow with it. The journal and the fact list scroll when the text is taller than the pane.

The status line says "Press New game." You will see:

- A seed box (it starts at `1`) and buttons: New game, Advance time, Save, Load, Reset, Abort scene.
- Toggles on two rows: Ferry master alive, Local tag, Lodging available, Notice succeeds, Season storm, Apprentice ready, Short on coins, Voice.
- A dialogue panel: speaker, text, Continue. Space or Enter also continues.
- Choice buttons. A choice you cannot take is grey and shows the reason in parentheses.
- A journal. Each line starts with a game time such as `day 1, 00:00`.
- A list of facts, the quest stage, and who holds each role.

Leave the toggles as they are for the first walk. Ferry master alive, Lodging available, and Notice succeeds start on. The others start off.

## 5. Walk one route

1. Press **New game**.
2. The speaker is **innkeeper**. The text is: "A room's two coins a night, and the stew is free."
3. Press **Continue**. The speaker is **watcher**: "The headland bell rang twice before the rain."
4. Continue. The speaker is **watcher**: "The ferry master is on the dock."
5. Continue. The speaker is **bell**: "The bell notes the tide."
6. One choice is shown: **Take the room**. Press it.
7. The innkeeper says: "The ferry's charging double since the storm, mind."
8. Continue. The speaker is **ferry master**: "Two coins, and the boat will cross."
9. Continue. The speaker is **narrator**: "The boat leaves the dock."
10. Continue once more. Continue becomes disabled. The last line stays on screen.

On the right:

- The journal has one line dated `day 1, 00:00`. It names the ferry master and a coin count. That sentence stays as it was written.
- The fact list shows `player.coins` as `2` and `harbor.room_taken` as `true`.
- The quest `ferry_toll` is active, stage `pay_toll`, waiting on a time check.

Press **Advance time**. The status line shows `day 1, 01:00`. The stage becomes `cross`. The fact `world.storm_heard` becomes `true`. The dock conversation opens again: "Two coins, and the boat will cross." then "The boat leaves the dock." Continue through both. The quest status becomes `completed`.

## 6. Every other route

Press **Reset** or **New game** between routes. Set the toggles before you press the choice, as the table says. Expected lines are the words on screen.

| What you set | What you should see |
|---|---|
| Defaults, as in section 5 | Innkeeper room line, watcher, ferry master on the dock, bell, then Take the room, then the dock lines. Coins go from 4 to 2. Journal `day 1, 00:00`. Advance time moves the stage to `cross` and finishes the quest after the dock lines. |
| **Local tag** on before New game | A second choice appears: "I have a place in town". Press it. Coins stay 4. The dock lines still play. The stage is still `pay_toll` and the journal still appears. |
| **Lodging available** off before Take the room | After Take the room the innkeeper says "No room left tonight." and "The board lists the price as {two coins}}." The second line really does show a single `{` and an extra `}`. Coins stay 4. The stage is `pay_toll`. |
| **Notice succeeds** off before Take the room | The room conversation plays as in section 5, then the tavern conversation is offered again and the stage is `gossip`. The journal already has the ferry-master line. |
| **Ferry master alive** off before Take the room (before or after New game is fine) | Take the room as usual. The journal says "The dock is empty, so the crossing waits." dated `day 1, 00:00`. The stage returns to `gossip` and then waits with no new scene. The fact list shows the ferry master is not alive. |
| **Apprentice ready** on before New game, then **Ferry master alive** off before Take the room | The journal names the apprentice. Advance time reaches `cross`. The dock speaker is **apprentice**, and the quest completes. |
| **Season storm** on before New game, or before you continue past "The ferry master is on the dock." | An extra line appears before the bell: narrator, "The season smells like rain." |
| **Abort scene** while the first lines are up | The conversation stops. The status says you can save. The stage stays `gossip` and the tavern scene is offered again. The last line stays visible. |
| **Short on coins** on before the choices appear | "Take the room (short on coins)" is grey and cannot be pressed. |

## 7. Save and load

Finish a conversation first. Save is refused while lines are still advancing. The status says "Can't save during a conversation." Abort scene if you need to save in the middle.

1. Play section 5 until the journal appears and Continue is disabled. Do not press Advance time yet.
2. Press **Save**. The status says the save is in memory and in `user://playtest_save.json`.
3. Press **Advance time**. The dock lines open again and the clock moves to `day 1, 01:00`.
4. Press **Load**. That conversation closes. Coins are 2 again, the stage is `pay_toll`, and the journal line is back. The clock returns to the saved time.

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
