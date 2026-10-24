# Stability

What 1.0 freezes, what stays experimental, and how a stable call or keyword is retired.

The generated reference with per-member status is in [docs/api](api/index.md).

## Stable surface

From 1.0.0 these change only in add-only ways in 1.x. No existing call, signal, argument, default, return type, or property is renamed, removed, or reshaped. New members may be added.

A class in this list has no class-level `@experimental` mark. A member named here has no member-level `@experimental` mark. On the facade and the member objects, every other public method, signal, and property keeps a member-level `@experimental` mark.

`WyrdAIRequest`, `WyrdAIResult`, `WyrdChoiceView`, `WyrdDiagnostics`, `WyrdDocumentView`, and `WyrdProposal` are not scripts the API snapshot walks. A stable member passes or returns each of them, so their class-level `@experimental` mark is removed and every public member is stable.

### Wyrd

Script: `res://addons/wyrd/runtime/wyrd.gd`.

Calls: `get_version`, `configure`, `register_adapter`, `register_function`, `register_disposition_formula`, `start_new_game`, `load_content`, `tick`, `can_save`, `save_state`, `load_state`, `invalidate_world`, `invalidate_groups`, `deeds_known_to`.

Signals: `line_ready`, `choices_ready`, `scene_started`, `scene_ended`, `bark_ready`, `quest_state_changed`, `stage_changed`, `outcome_changed`, `journal_entry_added`, `topic_unlocked`, `role_holder_changed`, `role_vacant`, `election_needed`, `deed_recorded`, `fact_changed`, `content_unavailable`, `document_read`, `load_report_ready`.

Properties: `facts`, `events`, `deeds`, `roles`, `topics`, `documents`, `quests`, `dialogue`, `generator`, `ai`.

### WyrdFactStore

Script: `res://addons/wyrd/runtime/facts/wyrd_fact_store.gd`.

Calls: `set_in`, `invalidate`.

Signals: `fact_changed`.

Properties: (none).

### WyrdEvents

Script: `res://addons/wyrd/runtime/wyrd_events.gd`.

Calls: `emit`, `begin_batch`, `end_batch`.

Signals: (none).

Properties: (none).

### WyrdDeedLog

Script: `res://addons/wyrd/runtime/deeds/wyrd_deed_log.gd`.

Calls: `record`.

Signals: `deed_recorded`.

Properties: (none).

### WyrdRoles

Script: `res://addons/wyrd/runtime/roles/wyrd_roles.gd`.

Calls: `vacate`, `assign`.

Signals: `role_holder_changed`, `role_vacant`, `election_needed`.

Properties: (none).

### WyrdTopics

Script: `res://addons/wyrd/runtime/topics/wyrd_topics.gd`.

Calls: (none).

Signals: `topic_unlocked`.

Properties: (none).

### WyrdDocuments

Script: `res://addons/wyrd/runtime/documents/wyrd_documents.gd`.

Calls: `open`, `create_copy`.

Signals: `document_read`.

Properties: (none).

### WyrdQuestRunner

Script: `res://addons/wyrd/runtime/quests/wyrd_quest_runner.gd`.

Calls: `summary`, `summary_source`.

Signals: `quest_state_changed`, `stage_changed`, `journal_entry_added`, `content_unavailable`.

Properties: (none).

### WyrdSceneRunner

Script: `res://addons/wyrd/runtime/scenes/wyrd_scene_runner.gd`.

Calls: `open`, `ask_topic`, `choose`, `advance`, `abort`, `open_scene`.

Signals: `line_ready`, `choices_ready`, `scene_started`, `scene_ended`.

Properties: (none).

### WyrdGenerator

Script: `res://addons/wyrd/runtime/generator/wyrd_generator.gd`.

Calls: `offer`, `propose`, `accept`.

Signals: (none).

Properties: (none).

### WyrdAI

Script: `res://addons/wyrd/runtime/ai/wyrd_ai.gd`.

Calls: `set_enabled`, `request`, `cancel`, `host_text`, `deliver`, `register_classifier`.

Signals: (none).

Properties: (none).

### WyrdWorldAdapter

Script: `res://addons/wyrd/runtime/adapters/wyrd_world_adapter.gd`.

Calls: `attr`, `candidates`, `display_name`, `exists`, `groups_of`, `in_bounds`, `is_alive`, `is_protected`, `kind`, `members`, `reports_changes`, `tags`.

Signals: (none).

Properties: (none).

### WyrdInventoryAdapter

Script: `res://addons/wyrd/runtime/adapters/wyrd_inventory_adapter.gd`.

Calls: `count`, `items`, `owner_of`.

Signals: (none).

Properties: (none).

### WyrdSpatialAdapter

Script: `res://addons/wyrd/runtime/adapters/wyrd_spatial_adapter.gd`.

Calls: `can_perceive`, `can_reach`, `distance`, `nearby`, `perceive`, `place_of`, `precision`, `witnesses_of`.

Signals: (none).

Properties: (none).

### WyrdTimeAdapter

Script: `res://addons/wyrd/runtime/adapters/wyrd_time_adapter.gd`.

Calls: `now_minutes`, `season`.

Signals: (none).

Properties: (none).

### WyrdActionAdapter

Script: `res://addons/wyrd/runtime/adapters/wyrd_action_adapter.gd`.

Calls: `command_schema`, `execute`.

Signals: (none).

Properties: (none).

### WyrdElectionAdapter

Script: `res://addons/wyrd/runtime/adapters/wyrd_election_adapter.gd`.

Calls: `start_election`.

Signals: (none).

Properties: (none).

### WyrdAIProvider

Script: `res://addons/wyrd/runtime/adapters/wyrd_ai_provider.gd`.

Calls: `cancel`, `id`, `locales`, `prompt_version`, `request`.

Signals: (none).

Properties: (none).

### WyrdSkillAdapter

Script: `res://addons/wyrd/runtime/adapters/wyrd_skill_adapter.gd`.

Calls: `check`.

Signals: (none).

Properties: (none).

### WyrdConfig

Script: `res://addons/wyrd/runtime/wyrd_config.gd`.

Calls: `axis_delta`, `half_life_for`, `kind_scale`, `scales_for`, `set_axis_delta`, `set_kind_scale`.

Signals: (none).

Properties: `ai_banned_terms`, `ai_cache_max`, `ai_max_inflight`, `ai_save_cache`, `axis_deltas`, `axis_names`, `axis_verbs`, `compact_after`, `credibility_threshold`, `disposition_default`, `generator_retries`, `half_life_minutes`, `half_life_verbs`, `hostile_threshold`, `hour_bucket_minutes`, `kind_scale_axes`, `kind_scale_kinds`, `kind_scale_values`, `pressure_tiers`, `publish_catchup_max`, `publish_slice_rows`, `rumor_coarse_minutes`, `scheduler_frame_warn_usec`, `scheduler_share_ai_prefetch`, `scheduler_share_cache`, `scheduler_share_generate`, `scheduler_share_publish`, `scheduler_share_rumor`, `scheduler_share_waits`, `scheduler_tick_minutes`, `scheduler_work_per_tick`, `secrecy_fact`, `secrecy_tiers`, `trace_director`.

### WyrdLoadReport

Script: `res://addons/wyrd/runtime/wyrd_load_report.gd`.

Calls: `add_row`, `error_count`, `sort_rows`.

Signals: (none).

Properties: `diagnostics`, `manifest_hash`, `ok`, `rows`.

### WyrdLineView

Script: `res://addons/wyrd/runtime/scenes/wyrd_line_view.gd`.

Calls: (none).

Signals: (none).

Properties: `audio`, `display_name`, `id`, `roles`, `speaker`, `tags`, `text`, `text_source`.

### WyrdContentManifest

Script: `res://addons/wyrd/compiler/wyrd_content_manifest.gd`.

Calls: (none).

Signals: (none).

Properties: `files`, `language_version`, `pack_id`.

### WyrdCommand

Script: `res://addons/wyrd/runtime/adapters/wyrd_command.gd`.

Calls: (none).

Signals: (none).

Properties: `args`, `name`.

### WyrdCommandResult

Script: `res://addons/wyrd/runtime/adapters/wyrd_command_result.gd`.

Calls: `failed`, `is_ok`, `ok`.

Signals: (none).

Properties: `reason`, `status`.

### WyrdCommandSchema

Script: `res://addons/wyrd/runtime/adapters/wyrd_command_schema.gd`.

Calls: `add_command`, `add_skill`, `has_command`, `has_skill`.

Signals: (none).

Properties: `checks_skills`, `command_names`, `skill_names`.

### WyrdEntityFilter

Script: `res://addons/wyrd/runtime/adapters/wyrd_entity_filter.gd`.

Calls: (none).

Signals: (none).

Properties: `kind`, `tag`.

### WyrdSkillCheck

Script: `res://addons/wyrd/runtime/adapters/wyrd_skill_check.gd`.

Calls: (none).

Signals: (none).

Properties: `args`, `choice_id`, `roll`, `scene_id`, `skill`.

### WyrdAIRequest

Script: `res://addons/wyrd/runtime/ai/wyrd_ai_request.gd`.

Calls: `set_deliver`, `reply`.

Signals: (none).

Properties: `id`, `kind`, `packet`, `constraints`, `locale`, `path`, `key`, `owner`, `sent_minute`.

### WyrdAIResult

Script: `res://addons/wyrd/runtime/ai/wyrd_ai_result.gd`.

Calls: (none).

Signals: (none).

Properties: `ok`, `text`, `error`.

### WyrdChoiceView

Script: `res://addons/wyrd/runtime/scenes/wyrd_choice_view.gd`.

Calls: (none).

Signals: (none).

Properties: `index`, `id`, `text`, `enabled`, `reason`, `tags`, `check`, `check_args`.

### WyrdDiagnostics

Script: `res://addons/wyrd/compiler/wyrd_diagnostics.gd`.

Calls: `add`, `has_errors`, `has_warnings`, `sort_items`, `format`.

Signals: (none).

Properties: `items`.

### WyrdDocumentView

Script: `res://addons/wyrd/runtime/documents/wyrd_document_view.gd`.

Calls: (none).

Signals: (none).

Properties: `id`, `copy_id`, `reader`, `title`, `frozen`, `first_time`, `tags`, `meta`, `pages`.

### WyrdProposal

Script: `res://addons/wyrd/runtime/generator/wyrd_proposal.gd`.

Calls: (none).

Signals: (none).

Properties: `id`, `source`, `key`, `tier`, `origin`, `template`, `instance`, `casts`, `params`, `payload`, `expected_counter`, `used`.

## Experimental

CLI flags, trace text, `debug`, `coverage`, `console`, compiler internals, and the `export-json` shape stay experimental after 1.0. So does every member marked `@experimental` in the API docs.

These facade properties stay experimental: `social`, `rumors`, `publish`, `storylets`, `sequences`, `director`, `trace`, `debug`, and `coverage`. These facade calls stay experimental: `register_group_precedence`, `register_credibility`, `register_rumor_policy`, `now_minutes`, `rng_stream`, `draw_u32`, `content`, `condition_count`, `condition_flags`, `eval_condition`, `last_rechecks`, and `trace_log`.

`WyrdSocial`, `WyrdRumor`, `WyrdPublish`, `WyrdStoryletDeck`, `WyrdSequences`, and `WyrdDirector` keep a class-level `@experimental` mark. `WyrdEffects` is not a facade member and keeps its class-level mark. The facade signal `topic_locked` stays, and it is experimental. `topic_answered`, `host_step_requested`, and `succession_requested` stay on their objects and are not repeated on the facade.

## Save promise

Every 1.x release loads any 1.x save and every schema 1–4 save. The save schema in this tree is 4.

## Deprecation policy

A stable call or `.wyrd` keyword may be deprecated in any 1.x minor release. It keeps working, warns once per id (at runtime and from `check`), and is listed in this document with its replacement and the release that deprecated it. It is removed only in 2.0.

The runtime warning is `Wyrd: <id> is deprecated since <since>; use <replacement>`. `check` still reports the compiler diagnostic once per use. The runtime warns once per id for a loaded pack, not once per use.

## Deprecated

| id | kind | replacement | deprecated in | removed in |
| --- | --- | --- | --- | --- |
| disabled_when | keyword | show_disabled_when | 0.6.3-m8 | 2.0.0 |

## Removed before 1.0

`known` (use `knows`) was removed in 1.0.0. Compiling it reports `E_KNOWN_REMOVED` with the message `known was removed in 1.0; use knows(agent, key)`. The `known/<agent>` fact perspective is a different name and stays.

## Support

Wyrd 1.x keeps the stable surface, the save promise, and the deprecation policy above. Report bugs as GitHub issues on this repository. Fixes land on `main` and ship in the next 1.x release. There is no guaranteed response time and no backport to an older 1.x release.
