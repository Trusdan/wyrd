# Visual playtest

This runs the example playtest in a real Godot window, presses the on-screen buttons, and saves a screenshot after every step. It then checks the pictures and the Godot log.

The window is the same playtest scene you open with Play. The script does not call the story ahead. It emits the `pressed` and `toggled` signals on the buttons that are in the window.

Gullhaven, the fishing village in the example, is the route this harness walks. The checks and the file format are generic: a new scenario is a block in the expectations file.

## 1. What you need

- Godot 4.7.2, the version in `tools/pins.env`, on your `PATH`. The standard build, not the .NET build.
- `xvfb-run`, from the `xvfb` package, so the window has a screen without a monitor.

The script looks for `godot` on `PATH`. If it is missing and `~/.local/bin/godot` exists, the script uses that.

## 2. Run it locally

From the project folder:

```bash
tools/visual_playtest.sh
```

That writes `visual-playtest-out/` next to the project. Pass another folder if you want the files somewhere else:

```bash
tools/visual_playtest.sh /tmp/visual-playtest-out
```

The script imports the project, starts a 1600×900 virtual screen, and opens the playtest at that size. The window is borderless so the client area matches the screen. Software OpenGL is turned on so the draw works under xvfb.

When it finishes it prints `visual-playtest passed`. A failed check prints `visual-playtest failed` and the script exits non-zero.

Open `visual-playtest-out/index.html` in a browser to see every shot. `index.md` is the same gallery in Markdown, and it links to `state.md`. `state.jsonl` is one JSON object per step with the facts, the quest, the slots, and the journal. `report.json` is the machine-readable result. `godot.log` is the engine log from the windowed run.

`visual-playtest-out/` is gitignored.

## 3. What it checks

Each failure names the scenario and the step.

- Any visible label, button, or journal row contains `{?` or `{}`. That is a missing or empty interpolation. A dialogue body that is empty while Continue is enabled fails too. A literal brace in example prose, such as `{two coins}}`, is left as written. An empty speaker label is left as written: a line can be on screen when the slot it names has no holder.
- The same `{?`, `{}`, and blank-value checks for facts, the quest, the outcome, and the slots read `state.jsonl`, not the fact list on screen. A row the list has scrolled out of view still fails the run if its value is blank (`world.season =` with nothing after the equals sign). An unset fact shows the word `absent`, including the season before Season storm is on. A journal line that is only a date fails too.
- The Godot log from the windowed run contains a script error, a parse error, `ERROR:`, or `WARNING:`. These engine lines are ignored, and only these: `ObjectDB instances were leaked` and `resources still in use at exit` (printed while the process is exiting), and `Could not set V-Sync mode, as changing V-Sync mode is not supported by the graphics driver` (the virtual display's software OpenGL driver).
- A main panel is missing, has no size, or sits outside the 1600×900 viewport. The panel names are the `panels` list in the expectations file. Every visible button is checked the same way.
- The scenario's `final` block. `contains` and `lacks` for a fact, quest, outcome, or slot row are matched against the state recorded for the last step, so a row hidden by the fact-list scrollbar still counts. Dialogue, buttons, and journal lines are matched against the last screen. `seen` and `unseen` are matched against every screen in that scenario, including the lines that have already scrolled off the dialogue panel. Quest title, stage, status, and outcome belong in `contains`.

Each step can also set `expect` for the screen just after that button press: `speaker`, `line`, `audio` (true when the current line has a voice clip), `continue_enabled`, `status_contains`, `contains`, and `lacks`.

## 4. How a scenario runs

The driver presses Reset, then sets every toggle through its `toggled` signal. `flags` on a scenario override `defaults`. A flag you omit stays at the default. `defaults` has to name every toggle in the playtest. A new toggle that is not listed fails the run.

Seed stays `1`. New game reads that box.

Steps run in order. Two actions are supported:

| action | target | what it presses |
|---|---|---|
| `press` | the button's label | New game, Continue, Advance time, Save, Load, Reset, Abort scene, Emit alive, Batch world, Strike bell |
| `choice` | the choice's label | a choice button under the dialogue |
| `flag` | the toggle key | sets that toggle. The step also has `"on": true` or `"on": false` |

Continue moves one line. After the last line of a scene, one more Continue closes it. The words stay in the text panel, and the choice buttons, journal, or the next scene show up on that same press. The screenshot is taken after the press, so name the step for what is on screen then.

The file name is `{scenario}_{step}.png`, for example `default_03_lookout.png`. The setup shot, after Reset and the toggles, is `{scenario}_00_setup.png`.

## 5. Add a scenario

1. Open `tools/visual_playtest_expectations.json`.
2. Copy a scenario object.
3. Set `id` to letters, digits, underscores, or hyphens. That id is the start of each screenshot name.
4. Set `flags` to the toggles that differ from `defaults`. Use the toggle keys (`ferry_alive`, `local`, `lodging`, `notice`, `storm`, `apprentice`, `short`, `voice`, `watch_alive`, `ai_local`), not the labels on the buttons.
5. List `steps`. Each step needs `name`, `action`, and `target`. Add `expect` for the line or panel text that must be on screen after that press.
6. Set `final.contains` to the quest title, stage, status, and outcome the state record should hold when the route is done. Put key lines in `final.seen`. Put text that must not have appeared, including `{?`, in `final.unseen`.
7. Run `tools/visual_playtest.sh` and read the failure line. It names the scenario and the step. Fix the expectation, or the playtest, and run it again.

You do not need to change the driver to add a route.

## 6. GitHub Actions

`.github/workflows/visual-playtest.yml` runs the same script. GitHub starts it in two cases: a push to `main`, and a manual run from the Actions tab (`workflow_dispatch`).

The job installs the Godot build named in `tools/pins.env`, installs `xvfb`, runs `tools/visual_playtest.sh`, and uploads `visual-playtest-out/` as the artifact `visual-playtest`. The job fails when the script exits non-zero, which it does when a check fails. The upload still runs so the screenshots and `report.json` are there after a failure.

On a branch, run the script on your machine before you merge. A manual run from the Actions tab is available once this workflow file is on main.
