# M3 exit demo

Stopped on Unverified 1. `check` of the Gullhaven manifest prints a warning, so this file records that baseline and does not continue the checklist. The exit scenario, the version bump, and the CHANGELOG roll-up are not in this change. No tag was cut.

## Baseline

On `518ba75`, `check --manifest example/content/gullhaven/harbor.wyrdmanifest.tres` exits 0 and prints:

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

There is no `error[` row. There is one `warning[W_CLAIM]` row and eight `info[I_STORYLET_SCORE]` rows. `tests/unit/test_cli.gd` already requires that warning on this manifest. The specified watch cycle ends with `errors=0 warnings=0`, which this output does not.

## Checked before stopping

These checks did not change the design.

A `user://` copy of the 15 Gullhaven files, `wyrd_commands.json`, and a manifest with the same `pack_id` and `language_version` checks the same as the original once `res://example/content/gullhaven/` is replaced with the copy directory.

Replacing `waits_until false` with `waits_until harbor.crate_missing` in the copied `dock_crate.wyrd` adds one row and leaves the others: `dock_crate.wyrd:13:17: error[E_UNKNOWN_FACT]: unknown fact "harbor.crate_missing"`. That edit is not committed. Nothing under `example/` changed.

Each §3.3 lint other than `kind: object|item` succession has a `WyrdDiagnostic` code, a message in the compiler, and a golden. Slot `kind:` is not in the grammar, so that lint is not applicable in M3.
