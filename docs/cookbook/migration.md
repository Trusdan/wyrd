# Migration

A save from the previous content should still load after a stage, role, document, or verb is renamed.

## Content

`was:` on a stage, role, or document header, and `verb <new> was: <old>`, records the old id. A chain resolves at compile time.

From `tests/golden/link/alias_clean/a.wyrd`:
```wyrd
language 1

quest ferry_toll "Ferry Toll"
  stage offer was: offer_old
    -> done
  stage done

template ferry_job "Ferry Job"
  stage hire was: hire_old

role ferry_master was: boatman

document harbor_gazette "Harbor Gazette" was: gazette
  text: live
  page
    The tide is in.

document tide_notice "Tide Notice" was: notice publishes_by harbor_guild every 1 day delay 1 hour

verb settle was: pay
verb pay was: paid
```

An old id that is still live is `E_ALIAS_CONFLICT`. One old id claimed twice is `E_ALIAS_DUPLICATE`. A cycle is `E_ALIAS_CYCLE`. The rules are in [Aliases](../language.md#aliases).

## Host side

Load content before restoring a save. [`load_content`](../api/Wyrd.md#load_content) returns a [`WyrdLoadReport`](../api/WyrdLoadReport.md). For a content load, `rows` is empty; `ok` is false when the compiler reported an error. [`load_state`](../api/Wyrd.md#load_state) rewrites saved stage ids, role ids, deed verbs, and document ids through the alias tables and adds one `alias` row for each rewrite. Saving again and loading that dictionary adds no further alias rows.

[`load_report_ready`](../api/Wyrd.md#load_report_ready) fires at the end of `load_state`, whether the load applied or was refused. `load_content` does not emit it.

The save-shape rules, the missing-stage order, and the worked Gullhaven packs are in [Migration](../migration.md).

## What to test

Save with the old ids, load against content that aliases them, and check each `alias` row. Load that new save again and check that no alias row is added. A stage that is gone, with no alias, follows `on_missing_stage`, then the saved trail, then the first stage, as [Migration](../migration.md) describes.
