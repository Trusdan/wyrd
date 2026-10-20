# M3 exit demo

Run this on the PR head. The `warning[W_CLAIM]` row in the Gullhaven baseline is intentional. It demonstrates the M5 claim lint. Info rows are expected and do not count as warnings. The baseline is `errors=0 warnings=1`.

Post pass or fail for each step as a PR comment before merging. The PR stays a draft until then. A failure in this PR's own files is fixed here. Anything else stops the demo and is reported. No tag is cut from this PR.

## 1. Setup

Godot is 4.7.2, as pinned in `tools/pins.env`. `wyrd.godotPath` points at that executable.

Install the extension from this PR. Download the `wyrd-vscode-vsix` artifact from the PR's CI run. It is a zip holding `wyrd.vsix`. Unzip it and run `code --install-extension wyrd.vsix`, or use Extensions: Install from VSIX…. The symlink route in `tools/vscode-wyrd/README.md` also works.

Install the free `ctagsx` extension. Open the repo root, the folder that contains `project.godot`, as the workspace folder. Start from a clean `git status`.

## 2. Colors

Open `example/content/gullhaven/ferry_toll.wyrd`, `dock_crate.wyrd`, and `harbor_documents.wyrd`. Keywords, ids, strings, `#line:` tags, and `{…}` spans are colored.

## 3. Errors on save

Run `Wyrd: check --watch (Gullhaven)`. Problems shows the baseline below: `errors=0 warnings=1`. The one warning is `W_CLAIM` on `harbor_tale.wyrd:42:41`. The `I_STORYLET_SCORE` rows are info. They are expected and do not count.

```
res://example/content/gullhaven/harbor_storylets.wyrd:4:1: info[I_STORYLET_SCORE]: storylet "harbor_gossip.generic" specificity 0 priority 0 generic=true
res://example/content/gullhaven/harbor_storylets.wyrd:9:1: info[I_STORYLET_SCORE]: storylet "harbor_gossip.tavern" specificity 2 priority 0 generic=false
res://example/content/gullhaven/harbor_storylets.wyrd:19:1: info[I_STORYLET_SCORE]: storylet "dock_bark_lantern" specificity 1 priority 0 generic=false
res://example/content/gullhaven/harbor_storylets.wyrd:26:1: info[I_STORYLET_SCORE]: storylet "dock_bark_lantern_carried" specificity 2 priority 0 generic=false
res://example/content/gullhaven/harbor_storylets.wyrd:33:1: info[I_STORYLET_SCORE]: storylet "dock_voice_crossing" specificity 0 priority 0 generic=true
res://example/content/gullhaven/harbor_storylets.wyrd:48:1: info[I_STORYLET_SCORE]: storylet "harbor_ledger.open" specificity 0 priority 0 generic=true
res://example/content/gullhaven/harbor_storylets.wyrd:55:1: info[I_STORYLET_SCORE]: storylet "harbor_ledger.sealed" specificity 1 priority 1 generic=false
res://example/content/gullhaven/harbor_storylets.wyrd:63:1: info[I_STORYLET_SCORE]: storylet "harbor_gossip.storm" specificity 0 priority 0 generic=true
res://example/content/gullhaven/harbor_tale.wyrd:42:41: warning[W_CLAIM]: interpolation presents "harbor.toll_fate" as a claim
```

In `example/content/gullhaven/dock_crate.wyrd`, change line 13 from `waits_until false` to `waits_until harbor.crate_missing` and save. Within a second or two, Problems shows `errors=1 warnings=1`: the baseline rows remain, and one `E_UNKNOWN_FACT` error is added at `dock_crate.wyrd:13:17`. Click it. The editor opens `dock_crate.wyrd` at that line and column. Undo and save. The error clears and Problems is back to `errors=0 warnings=1`. Stop the task. Do not commit the edit.

## 4. Check task

Run `Wyrd: check (Gullhaven)`. Problems shows the same baseline: `errors=0 warnings=1`, the `W_CLAIM` row, and the info rows.

## 5. Jump to definition

Run `Wyrd: defs (Gullhaven)`. F12 on each reference opens its definition. `cross` may show a pick list, because bare stage names can repeat. Ctrl+T, type `npc.{id}.alive`, and pick it: `facts.wyrd:31`. F12 on a filled-in pattern key is not expected to jump (see the extension README).

| Reference | Id | Kind | Definition |
|---|---|---|---|
| `dock_crate.wyrd:11` (`scene dock.crate_talk with tavern`) | `dock.crate_talk` | `g` | `dock_crate.wyrd:15` |
| `bell_repair.wyrd:23` (`-> done when harbor.rope_done …`) | `harbor.rope_done` | `f` | `facts.wyrd:20` |
| `ferry_toll.wyrd:32` (`-> cross when …`) | `cross` | `s` | `ferry_toll.wyrd:34` |
| `harbor_documents.wyrd:8` (`outcome(ferry_toll, crossing)`) | `ferry_toll` | `q` | `ferry_toll.wyrd:4` |
| `harbor_documents.wyrd:9` (`filled(ferry_master)`) | `ferry_master` | `r` | `harbor_roles.wyrd:9` |
| Ctrl+T only | `npc.{id}.alive` | `f` | `facts.wyrd:31` |

All paths are under `example/content/gullhaven/`.

## 6. POT

Run `Wyrd: pot (Gullhaven)`. `wyrd.pot` at the project root has `crate_line` and the `ferry_schedule` title and paragraphs (`sched_title`, `sched_plain`, `sched_toll`, `sched_empty`).

## 7. tag-lines

Run `Wyrd: tag lines (dry run)`. It prints proposals, or nothing, and changes no file.

## 8. Clean up

`git status` is clean. `tags` and `wyrd.pot` are gitignored.

## 9. What CI proves

| Criterion | CI proves | Corey checks by hand |
|---|---|---|
| Colored syntax in VS Code | Grammar snapshots (`vscode` job); keyword parity (`test_vscode_keywords.gd`); VSIX builds | The colors look right in an open `.wyrd` file |
| Errors and warnings in the Problems panel as he saves | `$wyrd` regex against real `check` output (`test_vscode_matcher.gd`); watch loop (`test_check_watch.gd`); Watch smoke step; exit test (edit, one `E_UNKNOWN_FACT` row, fix) | The watch task updates Problems after a save |
| Click-through to file:line | Regex captures path, line, and column; `fileLocation` is `autoDetect` from the workspace folder (`test_vscode_matcher.gd`) | Clicking the row opens the right line and column |
| F12 jumps to a definition | `defs` golden; `wordPattern` keeps dotted ids whole (`test_vscode_word_pattern.gd`); exit test pins every demo target | F12 on each plain id in the table above; Ctrl+T for the pattern key |
| `wyrd pot` includes `.wyrd` lines and document paragraphs | POT golden; POT check (`msgfmt --check`); `test_pot_translations.gd`; exit test | Running the pot task writes `wyrd.pot` |
| `tag-lines` from VS Code | `test_vscode_tasks.gd` (commands exist); `test_tag_lines.gd` (dry run writes nothing) | The dry-run task prints and changes nothing |
| Lints on the M3 row: `fact_never_read`, `fact_never_written`, secrecy leak | `W_FACT_NEVER_READ`, `W_FACT_NEVER_SET`, `W_SECRECY_LEAK` link goldens and the golden inventory | — |
| §3.3 lint list | The coverage table below; every code has a golden (inventory test) | — |

## 10. §3.3 lint coverage

| Lint | Code |
|---|---|
| Role-fallback coverage | `W_EMPTY_UNCOVERED`, `W_LOCKED_GONE_UNCOVERED` |
| Unknown facts, roles, functions | `E_UNKNOWN_FACT`, `W_ROLE_UNKNOWN`, `E_UNKNOWN_FUNCTION` |
| Unreachable stages | `W_STAGE_UNREACHABLE` |
| Duplicate or missing line ids | `E_LINE_ID_DUPLICATE`, `E_LINE_ID_MISSING` |
| Resolvers in waiting conditions without invalidation | `E_RESOLVER_NO_INVALIDATE` |
| Specificity ties | `W_STORYLET_TIE` |
| Sub-state nesting deeper than 2 | `W_SUBSTATE_DEPTH` |
| Interpolation in voiced lines | `E_VOICED_VARIABLE` |
| Text revealing `world:`-only facts | `E_FACT_LEAK` |
| `fact_never_read`, `fact_never_written` | `W_FACT_NEVER_READ`, `W_FACT_NEVER_SET` |
| Secrecy-tier leak | `W_SECRECY_LEAK` |
| `kind: object\|item` slots with a succession strategy | Not applicable in M3. No slot `kind:` exists yet. The lint comes with the milestone that adds slot kinds. |

## 11. Result

Corey runs this checklist on the PR head and posts pass or fail per step as a PR comment before merging. The PR stays a draft until then.
