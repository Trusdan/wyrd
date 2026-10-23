# Migration

How to rename or remove content so a save from the previous release still loads. The examples are Gullhaven and the packs under `tests/migration/packs/`. Save schema stays 4. A save with no aliases and no removed content loads as before.

## Renaming with `was:`

Put `was:` on a stage, role, or document header, or write `verb <new> was: <old>`. Keep each alias for at least one release, then drop it once old saves have been rewritten.

```
stage depart was: offer
role dock_master was: ferry_master
document tide_notice "Harbor Gazette" was: harbor_gazette
verb settle was: pay
verb pay was: paid
```

A chain resolves at compile time. `verb c was: b` and `verb b was: a` store `a → c` and `b → c`.

On load, Wyrd rewrites quest stages, role ids, deed verbs, and document ids. A stage id inside a saved `trail` is rewritten too. A periodic document's publish state follows the document id, and the verb of an in-flight rumor row follows the verb alias. Each rewritten id is one `alias` row. Saving again and loading that file adds no `alias` rows. When the old id and the new id are both in the save, the new id wins and the row's code is `W_SAVE_ALIAS`.

`tests/migration/test_m11_exit.gd` proves this with `test_exit_S1_rewrites_stage_role_verb_document_and_trail`, `test_exit_S1_publish_state_and_rumor_verb`, `test_exit_S1_a_collision_keeps_the_new_id`, and `test_exit_S1_a_resave_has_no_alias_rows`. The harbor and notice packs are the content.

## The three alias lints

| Code | When it fires |
| --- | --- |
| `E_ALIAS_CONFLICT` | The old id is still a live id in that scope. The message is `alias "<old>" is still a live <kind>`. |
| `E_ALIAS_DUPLICATE` | One old id is claimed by two new ids. The message is `alias "<old>" is claimed by "<a>" and "<b>"`. |
| `E_ALIAS_CYCLE` | The alias graph cycles. The message is `alias cycle: <a> -> <b> -> <a>`. Those entries are left out of the table. |

`test_exit_S1_lints_chain_and_manifest_hash` compiles a small source for each code and for the chain above. Content with no aliases keeps its manifest hash: Gullhaven stays `f003b6b54c91ad8e`.

## Removing a stage

A quest whose saved stage is gone moves in this order:

1. The stage alias, when `was:` names the saved id.
2. `on_missing_stage:` on the quest or template.
3. The latest stage in the saved `trail` that still exists.
4. The quest's first declared stage. A save with no `trail` uses this step too.

The quest arrives entered. The load runs no stage effects, so facts, deeds, and journal stay as they were saved, and the quest can still advance. A removed sub-state leaf restarts its region at the initial leaf. Each move adds one `missing_stage` row with `W_SAVE_STAGE`. A target that is not a stage of that quest is `E_MISSING_STAGE_TARGET` at compile time.

`test_exit_S2_alias_field_trail_and_first_stage`, `test_exit_S2_arrives_entered_without_effects`, `test_exit_S2_a_removed_leaf_restarts_its_region`, and `test_exit_S2_a_bad_target_is_rejected` cover the order on `stage_old` and `stage_new`.

## Removing other content

A removed storylet, topic, document, role, or hand-written quest is kept. A removed template adds a `template` row. The saved bytes stay in the file and come back when that content returns (old, then new, then old again). A kept hand-written quest is written back unchanged on the next save and does not tick. Facts are never rewritten to follow a rename or a removal.

A role the host defines in code with `roles.define`, and that the content does not declare, adds no `kept` row.

`test_exit_S3_removed_content_is_kept_and_returns` and `test_exit_S3_a_host_defined_role_adds_no_kept_row` prove this. The host-defined case uses the notice pack's `harbor_watch` role.

## What is not aliased

`was:` does not rename quests, storylets, topics, templates, sequences, or fact keys. Removing one of those is the kept path above. Fact values stay on the keys the save already has.

## Reading the load report

`WyrdLoadReport.rows` is an array of `{kind, id, from, to, count, code}`, sorted by kind, then id, then code. Connect `load_report_ready`. It fires once per `load_state`, including a refused load. `load_content` leaves `rows` empty and does not fire the signal. A clean load has no rows. In a debug build, a pack-hash mismatch adds a `manifest` row whose `from` and `to` are the two hashes.

`test_exit_S4_rows_signal_and_manifest` checks the shape, the sort, the signal, and the Gullhaven `v0.7.0-m9` hash pair.

## Refusal before import

A save that fails a check is not imported. `save_state()` after the call is byte-identical to `save_state()` before it, and the report has one `refused` row whose `id` names the check. A bad seed, a wrong-typed field, and a newer schema are three such checks.

`test_exit_S5_a_refused_save_is_unchanged` covers those three.

## Schema 4 and the fixture rule

A new save has `schema_version` 4. A save from schema 5 is refused. `test_exit_S6_schema_stays_4` checks both.

CI loads one fixture per earlier save schema and at least one save from a previous Gullhaven tag. Each file's sha256 is the value in `tests/migration/fixtures/README.md`, including the schema 2, 3, and 4 files under `tests/fixtures/`. The seeded loader fuzz runs on a fixed seed. `test_exit_S7_fixture_sha256_and_a_fuzz_sample` checks the hashes and a small sample of that fuzz.
