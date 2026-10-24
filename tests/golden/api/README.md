# Stable API surface

Snapshot of the calls, signals, properties, and value types this tree exposes for the 1.0 freeze. It records the code. It does not change it.

## What the snapshot covers

`tests/golden/api/expected/stable_api.json` is written by `WyrdApiGolden.write_expected()`, which `tools/update_goldens.sh` calls. CI compares `WyrdApiGolden.build()` to that file and never writes it. An intended change to a name, argument name, argument type, default, or return type regenerates the snapshot in the same PR.

`WyrdApiGolden.STABLE_CLASSES` is the covered set. At this commit that is 34 scripts, 407 methods, 23 signals, and 173 properties.

- Facade: `res://addons/wyrd/runtime/wyrd.gd`, reported as `Wyrd`. The script has no `class_name`.
- Member objects, taken from the facade's typed properties: `facts` (`WyrdFactStore`), `events` (`WyrdEvents`), `deeds` (`WyrdDeedLog`), `social` (`WyrdSocial`), `rumors` (`WyrdRumor`), `publish` (`WyrdPublish`), `roles` (`WyrdRoles`), `topics` (`WyrdTopics`), `documents` (`WyrdDocuments`), `quests` (`WyrdQuestRunner`), `dialogue` (`WyrdSceneRunner`), `storylets` (`WyrdStoryletDeck`), `sequences` (`WyrdSequences`), `director` (`WyrdDirector`), `generator` (`WyrdGenerator`), and `ai` (`WyrdAI`).
- Adapter base classes: `WyrdWorldAdapter`, `WyrdInventoryAdapter`, `WyrdSpatialAdapter`, `WyrdTimeAdapter`, `WyrdActionAdapter`, `WyrdElectionAdapter`, `WyrdAIProvider`, and `WyrdSkillAdapter`.
- `WyrdConfig`.
- Value types: `WyrdLoadReport`, `WyrdLineView`, `WyrdContentManifest`, `WyrdCommand`, `WyrdCommandResult`, `WyrdCommandSchema`, `WyrdEntityFilter`, and `WyrdSkillCheck`.

Left out on purpose: the scripts behind `trace`, `debug`, and `coverage`. The stability text keeps the debug, coverage, and console surfaces, CLI flags, trace text, compiler internals, and the export JSON experimental after 1.0. Those scripts are not walked. The facade properties `trace`, `debug`, and `coverage` are still in the `Wyrd` entry, because they are declared on that script.

`language` is the header version a one-line `language 1` source compiles to. The parser accepts that header and does not store a version field, so the snapshot reads the integer token the parser accepted and the `language_version` the linker records. `save_schema` is the `schema_version` a fresh `Wyrd.save_state()` writes. Both are discovered from the running code. No constant was added under `addons/wyrd/`.

Regenerate with `tools/update_goldens.sh`. Review the diff before committing.

### How a signature is recorded

Reflection uses `get_script_method_list()`, `get_script_signal_list()`, and `get_script_property_list()` on the pinned Godot. Names that start with `_` are skipped. If a name appears twice through script inheritance, the first entry is kept; the engine lists the derived script before its base. These covered scripts extend `Node`, `RefCounted`, or `Resource`, and none of them inherited a second copy of a script method. Lists are sorted by name. Argument order is the source order.

`type` is `type_string()` of the variant type. `void` is therefore `Nil`. A `Variant` parameter is also variant type nil, and the engine sets `PROPERTY_USAGE_NIL_IS_VARIANT` on it, so the snapshot stores that type as `Variant` instead of `Nil`. A later edit from `Variant` to `void`, or the other way, changes the snapshot.

`class` is the reflected `class_name`, or `""`. A typed array leaves `class_name` empty and puts the element type in `hint_string` (`PROPERTY_HINT_ARRAY_TYPE`). The snapshot copies that element name into `class`, so `Array[WyrdChoiceView]` is type `Array`, class `WyrdChoiceView`, and `Array[Dictionary]` is type `Array`, class `Dictionary`. Builtin element names are not classes. `unlisted_types` is every engine class or project `class_name` used by a covered signature that is not itself a covered script, sorted. `WyrdChoiceView` is in that list. `Dictionary` is not. The enum `WyrdCommandResult.Status` is stored on the `status` property's `class` field and is not a class, so it is not in `unlisted_types`.

Defaults are `var_to_str()` of the reflected default list, aligned to the trailing arguments. A `StringName` default stays text such as `&"world"`. An empty `PackedStringArray()` or `{}` default is reflected as null, so the snapshot text is `null`. A rename of that default to a real null, or to the other empty container, does not change the snapshot. The difference list below quotes the source, not that reflected null.

`WyrdSocial.members_of` has an inline setter. Reflection reports it as a method named `@members_of_setter`. The source is the `set(value)` at `addons/wyrd/runtime/social/wyrd_social.gd:31`. Its reflected return is `Variant` (the nil-is-variant flag); the source declares no return.

`_init` starts with `_` and is skipped. Constructor parameters on `WyrdCommand`, `WyrdEntityFilter`, and `WyrdLoadReport` are not in the snapshot. Their properties are.

## Differences from the design at `9be696b`

The design lists quoted here are the lifecycle, adapter, signal, and host-call lists in the 1.0 surface (sections 4.1 through 4.4) and the stability rule that every class stays `@experimental` until the freeze. The code cited is that tree. `7bbdeae` does not change `addons/wyrd`, `tests`, `docs`, `tools`, or `example` relative to `9be696b`. Nothing in this list is a fix.

Where the design writes a call and does not write a return type, a return type on the code is not a separate row. The snapshot still pins those return types. Argument names and counts are compared to the design text as written.

### `scene_started`

| Design | Code | Kind |
|---|---|---|
| `scene_started(scene_id)` | No `signal scene_started` anywhere under `addons/wyrd/`. | missing in code |

### Where each design signal is declared

Five signals are declared on the `Wyrd` facade (`addons/wyrd/runtime/wyrd.gd:20-24`): `bark_ready`, `topic_unlocked`, `topic_locked`, `document_read`, and `load_report_ready`. `topic_locked` is not in the design list; it is in the next table. The other design signals are declared on member objects, or on `WyrdEffects`, which is not a facade property.

| Design | Code | Kind |
|---|---|---|
| `line_ready(line)` | Not on the facade. `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:20` `signal line_ready(line: WyrdLineView)`. The argument name matches. | missing in code |
| `choices_ready(choices)` | Not on the facade. `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:21` `signal choices_ready(choices: Array[WyrdChoiceView])`. The argument name matches. | missing in code |
| `scene_ended(scene_id, result, reason)` | Not on the facade. `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:22` `signal scene_ended(scene_id: String, status: StringName, reason: StringName)`. Argument 2 is `status`, not `result`. | signature differs |
| `bark_ready(speaker, line)` | On the facade and the runtime, without `speaker`. `addons/wyrd/runtime/wyrd.gd:20` and `addons/wyrd/runtime/wyrd_runtime.gd:13` `signal bark_ready(line: WyrdLineView)`. | signature differs |
| `quest_state_changed(quest_id, old, new)` | Not on the facade. `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:29` `signal quest_state_changed(quest_id: String, status: StringName)`. One `status` argument stands where the design writes `old, new`. | signature differs |
| `stage_changed(quest_id, stage)` | Not on the facade. `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:30` `signal stage_changed(quest_id: String, stage_id: String)`. The second argument is `stage_id`, not `stage`. | signature differs |
| `outcome_changed(quest_id, branch, result)` | Not a facade member. `addons/wyrd/runtime/effects/wyrd_effects.gd:21` `signal outcome_changed(quest_id: String, branch: StringName, value: StringName)`. Argument 3 is `value`, not `result`. `WyrdEffects` is `WyrdRuntime.effects` at `addons/wyrd/runtime/wyrd_runtime.gd:29`. | signature differs |
| `journal_entry_added(quest_id, entry_id, text)` | Not on the facade. `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:31` `signal journal_entry_added(quest_id: String, entry_id: String, text: String)`. The argument names match. | missing in code |
| `topic_unlocked(topic_id)` | The argument is `topic`, not `topic_id`. The same signature is on the facade, the topic store, and effects: `addons/wyrd/runtime/wyrd.gd:21`, `addons/wyrd/runtime/topics/wyrd_topics.gd:13`, `addons/wyrd/runtime/effects/wyrd_effects.gd:20` `signal topic_unlocked(topic: StringName)`. | signature differs |
| `role_holder_changed(role_id, old, new)` | Not on the facade. `addons/wyrd/runtime/roles/wyrd_roles.gd:36` `signal role_holder_changed(role_id: StringName, old_holder: StringName, new_holder: StringName)`. | signature differs |
| `role_vacant(role_id)` | Not on the facade. `addons/wyrd/runtime/roles/wyrd_roles.gd:37` `signal role_vacant(role_id: StringName)`. The argument name matches. | missing in code |
| `election_needed(office)` | Not on the facade. `addons/wyrd/runtime/roles/wyrd_roles.gd:41` `signal election_needed(role_id: StringName, departed: StringName)`. | signature differs |
| `deed_recorded(deed)` | Not on the facade. `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:26` `signal deed_recorded(deed: Dictionary)`. The argument name matches. | missing in code |
| `fact_changed(key, old, new)` | Not on the facade. `addons/wyrd/runtime/facts/wyrd_fact_store.gd:18` `signal fact_changed(key: StringName, old_value: Variant, new_value: Variant)`. The fact store emits this for subscribed prefixes. | signature differs |
| `content_unavailable(quest_id, pack_id)` | Not on the facade. `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:32` `signal content_unavailable(quest_id: String, pack_id: String)`. The argument names match. | missing in code |
| `document_read(doc_id, copy_id, reader, first_time)` | On the facade and the document store. `addons/wyrd/runtime/wyrd.gd:23` and `addons/wyrd/runtime/documents/wyrd_documents.gd:15` `signal document_read(doc_id: StringName, copy_id: String, reader: StringName, first_time: bool)`. The argument names match. | missing in code |
| `load_report_ready(report)` | On the runtime and repeated on the facade. `addons/wyrd/runtime/wyrd_runtime.gd:2988` and `addons/wyrd/runtime/wyrd.gd:24` `signal load_report_ready(report: WyrdLoadReport)`. `load_state` emits it once on both the refused and the accepted path (`addons/wyrd/runtime/wyrd_runtime.gd:1377`). `load_content` does not emit it. The argument name matches. | missing in code |

`document_read` and `load_report_ready` do reach the facade, and their argument names match the design. The kind on those two rows is the same kind used for the other signals that the design does not place on a member: the design lists them as engine-to-host signals, and only `document_read`, `load_report_ready`, `bark_ready`, and `topic_unlocked` among that list are declared on `Wyrd`. `bark_ready` and `topic_unlocked` are on the facade with different argument names, so their kind is `signature differs`. There is no separate facade-only mismatch for `document_read` or `load_report_ready` beyond the design not naming the member that also declares them (`WyrdDocuments`, and `WyrdRuntime` for the load report).

The line view carried by `line_ready`, `bark_ready`, and `topic_answered` has `text_source`. `addons/wyrd/runtime/scenes/wyrd_line_view.gd:20` `var text_source: StringName = &"authored"`. The source comment names `authored` and `ai`. That property matches the design sentence. It is not a difference.

### Signals the design list does not name

| Design | Code | Kind |
|---|---|---|
| (not listed) | `addons/wyrd/runtime/wyrd.gd:22` and `addons/wyrd/runtime/topics/wyrd_topics.gd:14` `signal topic_locked(topic: StringName)`. The facade relays the topic store. | missing in design |
| (not listed) | `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:23` `signal topic_answered(npc: StringName, topic: StringName, line: WyrdLineView)`. | missing in design |
| (not listed) | `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:33` `signal host_step_requested(quest_id: String, screen_id: StringName, fields: PackedStringArray)`. | missing in design |
| (not listed) | `addons/wyrd/runtime/roles/wyrd_roles.gd:39` `signal succession_requested(role_id: StringName, departed: StringName)`. | missing in design |

No other `signal` is declared on a covered script. `WyrdEffects` also declares `topic_unlocked` and `outcome_changed`, both of which the design does list.

### Lifecycle and host calls

These design calls match the code on name and argument names. Return types the design does not write are omitted here; the snapshot pins them.

- `Wyrd.configure(config: WyrdConfig)` — `addons/wyrd/runtime/wyrd.gd:103` `func configure(config: WyrdConfig) -> void`.
- `Wyrd.register_adapter(WyrdWorldAdapter, my_world)` — `addons/wyrd/runtime/wyrd.gd:107` `func register_adapter(base: Script, adapter: RefCounted) -> void`.
- `Wyrd.load_content(...)` — `addons/wyrd/runtime/wyrd.gd:144` `func load_content(manifest: WyrdContentManifest) -> WyrdLoadReport`.
- `Wyrd.roles.vacate(role, reason)` — `addons/wyrd/runtime/roles/wyrd_roles.gd:675` `func vacate(role: StringName, reason: StringName) -> void`.
- `Wyrd.roles.assign(role, entity)` — `addons/wyrd/runtime/roles/wyrd_roles.gd:555` `func assign(role: StringName, entity: StringName) -> void`.
- `Wyrd.dialogue.open(npc)` — `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:78` `func open(npc: String) -> PackedStringArray`.
- `Wyrd.dialogue.ask_topic(npc, topic)` — `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:95` `func ask_topic(npc: String, topic: String) -> Dictionary`.
- `Wyrd.dialogue.choose(index)` — `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:295` `func choose(index: int) -> void`.
- `Wyrd.dialogue.advance()` — `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:280` `func advance() -> void`. `WyrdQuestRunner` also has `advance(quest_id, stage_id)` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:784`. That is a different call and is in the unnamed-member list.
- `Wyrd.dialogue.abort(reason)` — `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:341` `func abort(reason: StringName) -> void`.
- `Wyrd.can_save() -> bool` — `addons/wyrd/runtime/wyrd.gd:156` `func can_save() -> bool`.
- `Wyrd.save_state()` and `Wyrd.load_state(d)` both refuse while a scene is open. `addons/wyrd/runtime/wyrd_runtime.gd:1352` and `:1363` push the error; the refused load adds `E_SAVE_OPEN` at `:1365`. `save_state` is `addons/wyrd/runtime/wyrd.gd:160` `func save_state() -> Dictionary`.
- `Wyrd.documents.open(doc_id, copy_id, reader)` — `addons/wyrd/runtime/documents/wyrd_documents.gd:37` `func open(doc_id: StringName, copy_id: String, reader: StringName) -> WyrdDocumentView`.
- `Wyrd.events.begin_batch()` — `addons/wyrd/runtime/wyrd_events.gd:28` `func begin_batch() -> void`.
- `Wyrd.events.end_batch()` — `addons/wyrd/runtime/wyrd_events.gd:35` `func end_batch() -> void`.
- `Wyrd.generator.propose(context)` — `addons/wyrd/runtime/generator/wyrd_generator.gd:238` `func propose(context: Dictionary) -> WyrdProposal`.
- `Wyrd.generator.accept(proposal)` — `addons/wyrd/runtime/generator/wyrd_generator.gd:275` `func accept(proposal: WyrdProposal) -> String`.
- `Wyrd.ai.set_enabled(on)` — `addons/wyrd/runtime/ai/wyrd_ai.gd:44` `func set_enabled(on: bool) -> void`.
- `Wyrd.ai.cancel(request_id)` — `addons/wyrd/runtime/ai/wyrd_ai.gd:141` `func cancel(request_id: int) -> bool`.
- `Wyrd.ai.host_text(kind, packet, fallback)` — `addons/wyrd/runtime/ai/wyrd_ai.gd:417` `func host_text(kind: StringName, packet: Dictionary, fallback: String) -> String`.
- `Wyrd.ai.deliver(request_id, result)` — `addons/wyrd/runtime/ai/wyrd_ai.gd:100` `func deliver(request_id: int, result: WyrdAIResult) -> bool`.
- `Wyrd.ai.register_classifier(fn)` — `addons/wyrd/runtime/ai/wyrd_ai.gd:440` `func register_classifier(fn: Callable) -> void`.
- `Wyrd.tick(game_minutes)` — `addons/wyrd/runtime/wyrd.gd:148` `func tick(game_minutes: float) -> void`.
- `WyrdCommandResult.ok` — `addons/wyrd/runtime/adapters/wyrd_command_result.gd:14` `static func ok() -> WyrdCommandResult`.

| Design | Code | Kind |
|---|---|---|
| `Wyrd.facts.set(key, value)` | `addons/wyrd/runtime/facts/wyrd_fact_store.gd:487` `func set_in(key: StringName, new_value: Variant, perspective: StringName = &"world") -> bool`. There is no `set`. The source comment says `Object` already owns that name. | renamed |
| `Wyrd.facts.set(key, value)` | The code argument is `new_value`, not `value`, and a third argument `perspective` defaults to `&"world"`. Same line as the row above. | signature differs |
| `Wyrd.facts.invalidate(prefix)` | `addons/wyrd/runtime/facts/wyrd_fact_store.gd:617` `func invalidate(prefix: StringName, reason: StringName = &"") -> PackedStringArray`. | signature differs |
| `Wyrd.deeds.record(...)` | `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:510` `func record(verb: StringName, actor: StringName, target: StringName = &"", place: StringName = &"", tags: PackedStringArray = PackedStringArray(), magnitude: float = 1.0, witnesses: Variant = null, visibility: StringName = &"public", memorable: bool = false) -> int`. The design does not name these parameters. | signature differs |
| `Wyrd.register_disposition_formula(my_formula)` | No such call on `Wyrd`. The host hook is `addons/wyrd/runtime/social/wyrd_social.gd:139` `func register_formula(fn: Callable) -> void`. The default formula is `disposition_default + affinity / 2` (`addons/wyrd/runtime/social/wyrd_social.gd:12-14`). `WyrdConfig.disposition_default` is `50` at `addons/wyrd/runtime/wyrd_config.gd:33`. | missing in code |
| `Wyrd.register_function(&"hunger_tier", hunger_tier, [TYPE_STRING_NAME], TYPE_INT)` | `addons/wyrd/runtime/wyrd.gd:111` `func register_function(name: StringName, fn: Callable, arg_types: Array, return_type: StringName) -> bool`. The design's return-type argument is a variant-type constant; the code takes a `StringName`. | signature differs |
| `Wyrd.start_new_game(seed)` | `addons/wyrd/runtime/wyrd.gd:140` `func start_new_game(seed_value: int) -> void`. | signature differs |
| `Wyrd.load_state(d)` | `addons/wyrd/runtime/wyrd.gd:164` `func load_state(data: Dictionary) -> WyrdLoadReport`. The argument name is `data`. | signature differs |
| `Wyrd.documents.create_copy(doc_id, copy_id, params)` | `addons/wyrd/runtime/documents/wyrd_documents.gd:76` `func create_copy(doc_id: StringName, copy_id: String, params: Dictionary = {}, from_host: bool = true) -> bool`. | signature differs |
| `Wyrd.events.emit(name, payload)` | `addons/wyrd/runtime/wyrd_events.gd:23` `func emit(event_name: StringName, payload: Dictionary = {}) -> void`. | signature differs |
| `Wyrd.generator.offer(source, key, tier, payload)` | `addons/wyrd/runtime/generator/wyrd_generator.gd:27` `func offer(source: StringName, key: String, tier: StringName = &"", payload: Dictionary = {}) -> bool`. `tier` and `payload` have defaults the design does not write. | signature differs |
| `Wyrd.ai.request(kind, packet, constraints, path = "")` | `addons/wyrd/runtime/ai/wyrd_ai.gd:78` `func request(kind: StringName, packet: Dictionary, constraints: Dictionary = {}, path: StringName = &"") -> int`. `constraints` has a default, and `path` is a `StringName`. | signature differs |
| `Wyrd.quests.summary(quest)` | `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:347` `func summary(quest_id: String) -> String`. | signature differs |
| `Wyrd.quests.summary_source(quest)` | `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:359` `func summary_source(quest_id: String) -> StringName`. | signature differs |
| `failed(reason)` on `WyrdCommandResult` | `addons/wyrd/runtime/adapters/wyrd_command_result.gd:21` `static func failed(failure_reason: StringName) -> WyrdCommandResult`. | signature differs |

### Adapters

`WyrdWorldAdapter` methods whose argument names match the design sketch: `exists(id)`, `kind(id)`, `tags(id)`, `attr(id, key)`, `is_alive(id)`, `display_name(id)`, `members(faction)`, `candidates(filter)`, `reports_changes()` at `addons/wyrd/runtime/adapters/wyrd_world_adapter.gd:9-79`. The design's "(default false)" and "(default true)" notes describe the body when the host does not override. Those methods take no default argument; `is_protected` returns false (`:47`), `in_bounds` returns true (`:53`), and `reports_changes` returns false (`:69`).

`WyrdInventoryAdapter` matches the sketch's argument names: `count(holder, item_or_tag)`, `items(holder, filter)`, `owner_of(item)` at `addons/wyrd/runtime/adapters/wyrd_inventory_adapter.gd:10-20`.

`WyrdActionAdapter` matches `command_schema() -> WyrdCommandSchema` and `execute(cmd) -> WyrdCommandResult` at `addons/wyrd/runtime/adapters/wyrd_action_adapter.gd:10` and `:15`.

`WyrdAIProvider.id()`, `prompt_version()`, and `locales()` match the names at `addons/wyrd/runtime/adapters/wyrd_ai_provider.gd:12-22`.

§4.2 names `nearby`, `place_of`, `distance`, `can_perceive`, and `can_reach` with no parameters. The code is `nearby(center: StringName, radius_m: float, filter: WyrdEntityFilter)`, `place_of(entity: StringName)`, `distance(a: StringName, b: StringName)`, `can_perceive(observer: StringName, target: StringName)`, and `can_reach(agent: StringName, place: StringName)` at `addons/wyrd/runtime/adapters/wyrd_spatial_adapter.gd:13-38`.

| Design | Code | Kind |
|---|---|---|
| `WyrdWorldAdapter.is_protected(id)` | `addons/wyrd/runtime/adapters/wyrd_world_adapter.gd:47` `func is_protected(_id: StringName) -> bool`. | signature differs |
| `WyrdWorldAdapter.in_bounds(id, pack)` | `addons/wyrd/runtime/adapters/wyrd_world_adapter.gd:53` `func in_bounds(_id: StringName, _pack: String) -> bool`. | signature differs |
| `WyrdWorldAdapter.groups_of(agent)` | `addons/wyrd/runtime/adapters/wyrd_world_adapter.gd:61` `func groups_of(_agent: StringName) -> PackedStringArray`. | signature differs |
| `WyrdSpatialAdapter` methods beyond the five names | `addons/wyrd/runtime/adapters/wyrd_spatial_adapter.gd:44` `func witnesses_of(_actor: StringName, _target: StringName, _place: StringName) -> PackedStringArray`. | missing in design |
| `WyrdSpatialAdapter` methods beyond the five names | `addons/wyrd/runtime/adapters/wyrd_spatial_adapter.gd:50` `func precision(_place: StringName) -> StringName`. | missing in design |
| `WyrdSpatialAdapter` methods beyond the five names | `addons/wyrd/runtime/adapters/wyrd_spatial_adapter.gd:57` `func perceive(_observer: StringName, _actor: StringName, _target: StringName, _place: StringName) -> StringName`. | missing in design |
| `WyrdTimeAdapter.now_minutes()`, plus the calendar from config | `now_minutes` is `addons/wyrd/runtime/adapters/wyrd_time_adapter.gd:10` `func now_minutes() -> int`. No calendar field is declared on `WyrdConfig`. The adapter comment at `:6-7` says the calendar will live on a future config. | missing in code |
| (not listed on `WyrdTimeAdapter`) | `addons/wyrd/runtime/adapters/wyrd_time_adapter.gd:16` `func season() -> StringName`. | missing in design |
| `WyrdElectionAdapter.start_election(office, candidates)` | `addons/wyrd/runtime/adapters/wyrd_election_adapter.gd:10` `func start_election(role: StringName, departed: StringName) -> void`. The adapter comment says the host finishes with `WyrdRoles.assign`. | signature differs |
| `WyrdAIProvider.request(req)` | `addons/wyrd/runtime/adapters/wyrd_ai_provider.gd:27` `func request(_req: WyrdAIRequest) -> void`. | signature differs |
| `WyrdAIProvider.cancel(request_id)` | `addons/wyrd/runtime/adapters/wyrd_ai_provider.gd:31` `func cancel(_request_id: int) -> void`. | signature differs |
| (not in the adapter table) | `WyrdSkillAdapter` is a covered base class. `addons/wyrd/runtime/adapters/wyrd_skill_adapter.gd:10` `func check(request: WyrdSkillCheck) -> WyrdCommandResult`. | missing in design |

### `unlisted_types`

These class names appear in a covered signature and are not themselves covered. Builtin element names such as `Dictionary` and `StringName` are stored on the signature and are not in this list. The enum `WyrdCommandResult.Status` is not in this list.

| Design | Code | Kind |
|---|---|---|
| (not a covered type) | `RefCounted`, the engine class. `Wyrd.register_adapter` takes it at `addons/wyrd/runtime/wyrd.gd:107`. | missing in design |
| (not a covered type) | `Script`, the engine class. Same `register_adapter` parameter at `addons/wyrd/runtime/wyrd.gd:107`. | missing in design |

The project classes in `unlisted_types`, each with its `class_name` line:

| Design | Code | Kind |
|---|---|---|
| (not a covered type) | `WyrdAIRequest` at `addons/wyrd/runtime/ai/wyrd_ai_request.gd:1`. `WyrdAIProvider.request` takes it. | missing in design |
| (not a covered type) | `WyrdAIResult` at `addons/wyrd/runtime/ai/wyrd_ai_result.gd:1`. `WyrdAI.deliver` returns through it. | missing in design |
| (not a covered type) | `WyrdChoiceView` at `addons/wyrd/runtime/scenes/wyrd_choice_view.gd:1`. `choices_ready` passes `Array[WyrdChoiceView]` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:21`. | missing in design |
| (not a covered type) | `WyrdContent` at `addons/wyrd/runtime/wyrd_content.gd:1`. `Wyrd.content` returns it. | missing in design |
| (not a covered type) | `WyrdCoverage` at `addons/wyrd/runtime/debug/wyrd_coverage.gd:1`. The facade property `coverage` uses it. The script is not walked. | missing in design |
| (not a covered type) | `WyrdDebug` at `addons/wyrd/runtime/debug/wyrd_debug.gd:1`. The facade property `debug` uses it. The script is not walked. | missing in design |
| (not a covered type) | `WyrdDiagnostics` at `addons/wyrd/compiler/wyrd_diagnostics.gd:1`. `WyrdLoadReport.diagnostics` uses it. | missing in design |
| (not a covered type) | `WyrdDocumentView` at `addons/wyrd/runtime/documents/wyrd_document_view.gd:1`. `WyrdDocuments.open` returns it. | missing in design |
| (not a covered type) | `WyrdExprNode` at `addons/wyrd/compiler/expr/ast/wyrd_expr_node.gd:1`. | missing in design |
| (not a covered type) | `WyrdFactSchema` at `addons/wyrd/compiler/ast/wyrd_fact_schema.gd:1`. | missing in design |
| (not a covered type) | `WyrdParamDef` at `addons/wyrd/compiler/stmt/wyrd_param_def.gd:1`. | missing in design |
| (not a covered type) | `WyrdProposal` at `addons/wyrd/runtime/generator/wyrd_proposal.gd:1`. `WyrdGenerator.propose` returns it and `accept` takes it. | missing in design |
| (not a covered type) | `WyrdQuestDef` at `addons/wyrd/compiler/stmt/wyrd_quest_def.gd:1`. | missing in design |
| (not a covered type) | `WyrdRng` at `addons/wyrd/runtime/rng/wyrd_rng.gd:1`. `Wyrd.rng_stream` returns it. | missing in design |
| (not a covered type) | `WyrdRoleDef` at `addons/wyrd/compiler/stmt/wyrd_role_def.gd:1`. | missing in design |
| (not a covered type) | `WyrdRumorPolicy` at `addons/wyrd/runtime/rumor/wyrd_rumor_policy.gd:1`. `Wyrd.register_rumor_policy` takes it. | missing in design |
| (not a covered type) | `WyrdRuntime` at `addons/wyrd/runtime/wyrd_runtime.gd:1`. Member objects hold it. It is not a facade property. | missing in design |
| (not a covered type) | `WyrdScheduler` at `addons/wyrd/runtime/scheduler/wyrd_scheduler.gd:1`. | missing in design |
| (not a covered type) | `WyrdSlotDef` at `addons/wyrd/compiler/stmt/wyrd_slot_def.gd:1`. | missing in design |
| (not a covered type) | `WyrdStageDef` at `addons/wyrd/compiler/stmt/wyrd_stage_def.gd:1`. | missing in design |
| (not a covered type) | `WyrdStoryletDef` at `addons/wyrd/compiler/stmt/wyrd_storylet_def.gd:1`. | missing in design |
| (not a covered type) | `WyrdTemplateDef` at `addons/wyrd/compiler/stmt/wyrd_template_def.gd:1`. | missing in design |
| (not a covered type) | `WyrdTrace` at `addons/wyrd/runtime/trace/wyrd_trace.gd:1`. The facade property `trace` uses it. The script is not walked. | missing in design |

### `known`

The design says deprecated items are removed at the freeze, and names `known` as removed then. The compiler still accepts it and warns `W_KNOWN_DEPRECATED`.

| Design | Code | Kind |
|---|---|---|
| `known` is removed at the 1.0 freeze | `addons/wyrd/compiler/wyrd_signatures.gd:58` still lists `known(agent:entity, key:fact_key)->bool`. The file comment at `:9-10` says `known` warns `W_KNOWN_DEPRECATED`. | still present |
| `known` is removed at the 1.0 freeze | `addons/wyrd/compiler/expr/wyrd_type_checker.gd:281` warns `W_KNOWN_DEPRECATED` and tells the author to use `knows`. | still present |
| `known` is removed at the 1.0 freeze | `addons/wyrd/compiler/wyrd_diagnostic.gd:112` `const W_KNOWN_DEPRECATED: StringName = &"W_KNOWN_DEPRECATED"`. | still present |
| `known` is removed at the 1.0 freeze | `addons/wyrd/compiler/wyrd_fact_xref.gd:415` and `addons/wyrd/compiler/wyrd_secrecy_lint.gd:172` still treat `known` the same way as `knows`. | still present |

### `@experimental`

The design says that until 1.0 every class is `@experimental`. Every covered script still has a `## @experimental` line. The snapshot's `experimental` field is true for all 34.

| Design | Code | Kind |
|---|---|---|
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/wyrd.gd:7` `## @experimental` on `Wyrd`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/facts/wyrd_fact_store.gd:6` `## @experimental` on `WyrdFactStore`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/wyrd_events.gd:6` `## @experimental` on `WyrdEvents`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:6` `## @experimental` on `WyrdDeedLog`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/social/wyrd_social.gd:6` `## @experimental` on `WyrdSocial`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/rumor/wyrd_rumor.gd:6` `## @experimental` on `WyrdRumor`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/publish/wyrd_publish.gd:6` `## @experimental` on `WyrdPublish`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/roles/wyrd_roles.gd:6` `## @experimental` on `WyrdRoles`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/topics/wyrd_topics.gd:6` `## @experimental` on `WyrdTopics`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/documents/wyrd_documents.gd:6` `## @experimental` on `WyrdDocuments`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:6` `## @experimental` on `WyrdQuestRunner`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:6` `## @experimental` on `WyrdSceneRunner`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:6` `## @experimental` on `WyrdStoryletDeck`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/quests/wyrd_sequences.gd:6` `## @experimental` on `WyrdSequences`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/storylets/wyrd_director.gd:6` `## @experimental` on `WyrdDirector`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/generator/wyrd_generator.gd:6` `## @experimental` on `WyrdGenerator`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/ai/wyrd_ai.gd:6` `## @experimental` on `WyrdAI`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/adapters/wyrd_world_adapter.gd:6` `## @experimental` on `WyrdWorldAdapter`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/adapters/wyrd_inventory_adapter.gd:6` `## @experimental` on `WyrdInventoryAdapter`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/adapters/wyrd_spatial_adapter.gd:6` `## @experimental` on `WyrdSpatialAdapter`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/adapters/wyrd_time_adapter.gd:6` `## @experimental` on `WyrdTimeAdapter`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/adapters/wyrd_action_adapter.gd:6` `## @experimental` on `WyrdActionAdapter`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/adapters/wyrd_election_adapter.gd:6` `## @experimental` on `WyrdElectionAdapter`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/adapters/wyrd_ai_provider.gd:6` `## @experimental` on `WyrdAIProvider`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/adapters/wyrd_skill_adapter.gd:6` `## @experimental` on `WyrdSkillAdapter`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/wyrd_config.gd:6` `## @experimental` on `WyrdConfig`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/wyrd_load_report.gd:6` `## @experimental` on `WyrdLoadReport`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/scenes/wyrd_line_view.gd:6` `## @experimental` on `WyrdLineView`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/compiler/wyrd_content_manifest.gd:6` `## @experimental` on `WyrdContentManifest`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/adapters/wyrd_command.gd:6` `## @experimental` on `WyrdCommand`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/adapters/wyrd_command_result.gd:6` `## @experimental` on `WyrdCommandResult`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/adapters/wyrd_command_schema.gd:6` `## @experimental` on `WyrdCommandSchema`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/adapters/wyrd_entity_filter.gd:6` `## @experimental` on `WyrdEntityFilter`. | still present |
| until 1.0 every class is `@experimental` | `addons/wyrd/runtime/adapters/wyrd_skill_check.gd:6` `## @experimental` on `WyrdSkillCheck`. | still present |

### Public members the design lists do not name

Every other public method and property on a covered class. Signals are all in the tables above, either as a design signal or as `topic_locked`, `topic_answered`, `host_step_requested`, or `succession_requested`. Methods and properties already cited above are not repeated. Facade properties the design uses as call targets (`facts`, `events`, `deeds`, `roles`, `dialogue`, `documents`, `generator`, `ai`, `quests`) are not repeated. `text_source` is not repeated. `WyrdConfig.disposition_default` is cited with the disposition formula and is not repeated.

`WyrdWorldAdapter`, `WyrdInventoryAdapter`, `WyrdSpatialAdapter`, `WyrdTimeAdapter`, `WyrdActionAdapter`, `WyrdElectionAdapter`, `WyrdAIProvider`, and `WyrdSkillAdapter` have no row in this section. Each of their public methods is already in the adapter section.

Kind for every row in this section: `missing in design`. There are 497 rows. Within a class, methods come first and properties second, and each of those groups is sorted by name.

#### Wyrd

| Design | Code | Kind |
|---|---|---|
| (not named) | `func condition_count() -> int` at `addons/wyrd/runtime/wyrd.gd:180` | missing in design |
| (not named) | `func condition_flags() -> PackedByteArray` at `addons/wyrd/runtime/wyrd.gd:184` | missing in design |
| (not named) | `func content() -> WyrdContent` at `addons/wyrd/runtime/wyrd.gd:176` | missing in design |
| (not named) | `func deeds_known_to(group: StringName, since: int, filter: StringName = &"") -> Array` at `addons/wyrd/runtime/wyrd.gd:127` | missing in design |
| (not named) | `func draw_u32(name: StringName) -> int` at `addons/wyrd/runtime/wyrd.gd:172` | missing in design |
| (not named) | `func eval_condition(index: int) -> bool` at `addons/wyrd/runtime/wyrd.gd:188` | missing in design |
| (not named) | `func get_version() -> String` at `addons/wyrd/runtime/wyrd.gd:99` | missing in design |
| (not named) | `func invalidate_groups() -> void` at `addons/wyrd/runtime/wyrd.gd:131` | missing in design |
| (not named) | `func invalidate_world(ids: PackedStringArray = PackedStringArray()) -> void` at `addons/wyrd/runtime/wyrd.gd:136` | missing in design |
| (not named) | `func last_rechecks() -> int` at `addons/wyrd/runtime/wyrd.gd:192` | missing in design |
| (not named) | `func now_minutes() -> int` at `addons/wyrd/runtime/wyrd.gd:152` | missing in design |
| (not named) | `func register_credibility(fn: Callable) -> void` at `addons/wyrd/runtime/wyrd.gd:119` | missing in design |
| (not named) | `func register_group_precedence(fn: Callable) -> void` at `addons/wyrd/runtime/wyrd.gd:115` | missing in design |
| (not named) | `func register_rumor_policy(policy: WyrdRumorPolicy) -> void` at `addons/wyrd/runtime/wyrd.gd:123` | missing in design |
| (not named) | `func rng_stream(name: StringName) -> WyrdRng` at `addons/wyrd/runtime/wyrd.gd:168` | missing in design |
| (not named) | `func trace_log() -> Array[Dictionary]` at `addons/wyrd/runtime/wyrd.gd:196` | missing in design |
| (not named) | `var coverage: WyrdCoverage` at `addons/wyrd/runtime/wyrd.gd:44` | missing in design |
| (not named) | `var debug: WyrdDebug` at `addons/wyrd/runtime/wyrd.gd:43` | missing in design |
| (not named) | `var director: WyrdDirector` at `addons/wyrd/runtime/wyrd.gd:39` | missing in design |
| (not named) | `var publish: WyrdPublish` at `addons/wyrd/runtime/wyrd.gd:31` | missing in design |
| (not named) | `var rumors: WyrdRumor` at `addons/wyrd/runtime/wyrd.gd:30` | missing in design |
| (not named) | `var sequences: WyrdSequences` at `addons/wyrd/runtime/wyrd.gd:38` | missing in design |
| (not named) | `var social: WyrdSocial` at `addons/wyrd/runtime/wyrd.gd:29` | missing in design |
| (not named) | `var storylets: WyrdStoryletDeck` at `addons/wyrd/runtime/wyrd.gd:37` | missing in design |
| (not named) | `var topics: WyrdTopics` at `addons/wyrd/runtime/wyrd.gd:33` | missing in design |
| (not named) | `var trace: WyrdTrace` at `addons/wyrd/runtime/wyrd.gd:42` | missing in design |

#### WyrdFactStore

| Design | Code | Kind |
|---|---|---|
| (not named) | `func bind_schema(schema: WyrdFactSchema) -> void` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:58` | missing in design |
| (not named) | `func cache_view(key: String) -> Dictionary` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:668` | missing in design |
| (not named) | `func choice_summary(query: Dictionary = {}) -> Array` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:72` | missing in design |
| (not named) | `func clear_in(key: StringName, perspective: StringName) -> bool` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:526` | missing in design |
| (not named) | `func clear_values() -> void` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:391` | missing in design |
| (not named) | `func decay_evidence(now: int) -> void` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:434` | missing in design |
| (not named) | `func evidence_rows() -> Array` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:429` | missing in design |
| (not named) | `func export_state() -> Dictionary` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:214` | missing in design |
| (not named) | `func get_in(key: StringName, perspective: StringName = &"world") -> Variant` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:467` | missing in design |
| (not named) | `func import_state(data: Dictionary) -> void` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:254` | missing in design |
| (not named) | `func invalidate_event(event_name: StringName) -> PackedStringArray` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:652` | missing in design |
| (not named) | `func note_evidence(key: String, value: Variant, place: String, until: int, event_name: String, actor: String, target: String) -> void` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:403` | missing in design |
| (not named) | `func refresh_poll(now: int) -> void` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:679` | missing in design |
| (not named) | `func remember(key: StringName, value: Variant, perspective: StringName) -> bool` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:593` | missing in design |
| (not named) | `func render_choice_summary(query: Dictionary = {}) -> String` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:103` | missing in design |
| (not named) | `func saved_type_issue(key: String, value: Variant) -> String` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:228` | missing in design |
| (not named) | `func subscribe(prefix: StringName) -> void` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:450` | missing in design |
| (not named) | `func world_keys() -> PackedStringArray` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:458` | missing in design |
| (not named) | `var belief_trace_of: Callable = Callable()` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:28` | missing in design |
| (not named) | `var clock: Callable = Callable()` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:32` | missing in design |
| (not named) | `var on_belief: Callable = Callable()` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:24` | missing in design |
| (not named) | `var on_belief_touch: Callable = Callable()` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:26` | missing in design |
| (not named) | `var on_choice_summary: Callable = Callable()` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:37` | missing in design |
| (not named) | `var on_keys: Callable = Callable()` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:20` | missing in design |
| (not named) | `var on_knowledge: Callable = Callable()` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:30` | missing in design |
| (not named) | `var on_resolved: Callable = Callable()` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:31` | missing in design |
| (not named) | `var provenance_of: Callable = Callable()` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:35` | missing in design |
| (not named) | `var resolver_of: Callable = Callable()` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:33` | missing in design |
| (not named) | `var runtime: WyrdRuntime` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:38` | missing in design |
| (not named) | `var tracer: Callable = Callable()` at `addons/wyrd/runtime/facts/wyrd_fact_store.gd:21` | missing in design |

#### WyrdEvents

| Design | Code | Kind |
|---|---|---|
| (not named) | `func batching() -> bool` at `addons/wyrd/runtime/wyrd_events.gd:44` | missing in design |
| (not named) | `func clear_recent() -> void` at `addons/wyrd/runtime/wyrd_events.gd:56` | missing in design |
| (not named) | `func debug_dump() -> String` at `addons/wyrd/runtime/wyrd_events.gd:67` | missing in design |
| (not named) | `func remember(row: Dictionary) -> void` at `addons/wyrd/runtime/wyrd_events.gd:60` | missing in design |
| (not named) | `func reset_session() -> void` at `addons/wyrd/runtime/wyrd_events.gd:48` | missing in design |
| (not named) | `var last_flush: int = 0` at `addons/wyrd/runtime/wyrd_events.gd:15` | missing in design |
| (not named) | `var last_keys: PackedStringArray = PackedStringArray()` at `addons/wyrd/runtime/wyrd_events.gd:17` | missing in design |
| (not named) | `var last_wave: int = 0` at `addons/wyrd/runtime/wyrd_events.gd:16` | missing in design |
| (not named) | `var on_batch: Callable = Callable()` at `addons/wyrd/runtime/wyrd_events.gd:13` | missing in design |
| (not named) | `var on_emit: Callable = Callable()` at `addons/wyrd/runtime/wyrd_events.gd:12` | missing in design |
| (not named) | `var recent: Array[Dictionary] = []` at `addons/wyrd/runtime/wyrd_events.gd:18` | missing in design |
| (not named) | `var ring_limit: int = 32` at `addons/wyrd/runtime/wyrd_events.gd:14` | missing in design |

#### WyrdDeedLog

| Design | Code | Kind |
|---|---|---|
| (not named) | `func actor_at(index: int) -> StringName` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:595` | missing in design |
| (not named) | `func actor_indexes(actor: StringName) -> PackedInt32Array` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:92` | missing in design |
| (not named) | `func agent_names(prefix: String) -> PackedStringArray` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:735` | missing in design |
| (not named) | `func believer_deeds(who: StringName) -> Array` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:167` | missing in design |
| (not named) | `func believer_index(who: StringName) -> Dictionary` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:158` | missing in design |
| (not named) | `func believer_minutes(deed_id: int) -> Dictionary` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:151` | missing in design |
| (not named) | `func believer_snapshot(members: Dictionary) -> Dictionary` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:135` | missing in design |
| (not named) | `func clear() -> void` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:466` | missing in design |
| (not named) | `func compact() -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:220` | missing in design |
| (not named) | `func count_matching(actor: StringName, verb: Variant = null, target: Variant = null, place: Variant = null, within: Variant = null, tags: PackedStringArray = PackedStringArray()) -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:569` | missing in design |
| (not named) | `func export_state() -> Dictionary` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:84` | missing in design |
| (not named) | `func generation() -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:202` | missing in design |
| (not named) | `func id_at(index: int) -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:603` | missing in design |
| (not named) | `func import_state(data: Dictionary) -> void` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:206` | missing in design |
| (not named) | `func index_of(deed_id: int) -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:107` | missing in design |
| (not named) | `func index_size(which: StringName, key: StringName) -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:503` | missing in design |
| (not named) | `func index_text_bytes() -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:686` | missing in design |
| (not named) | `func lookup_enabled() -> bool` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:679` | missing in design |
| (not named) | `func magnitude_at(index: int) -> float` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:615` | missing in design |
| (not named) | `func memorable_at(index: int) -> bool` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:619` | missing in design |
| (not named) | `func minute_at(index: int) -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:607` | missing in design |
| (not named) | `func mode_of(agent: StringName, verb: StringName) -> StringName` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:780` | missing in design |
| (not named) | `func note_believer(deed_id: int, who: StringName, minute: int) -> void` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:114` | missing in design |
| (not named) | `func pair_keys() -> PackedStringArray` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:655` | missing in design |
| (not named) | `func place_at(index: int) -> StringName` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:611` | missing in design |
| (not named) | `static func round_sum(value: float) -> float` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:811` | missing in design |
| (not named) | `func row_at(index: int) -> Dictionary` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:762` | missing in design |
| (not named) | `func rows_for_deed_prefix(prefix: String) -> PackedInt32Array` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:711` | missing in design |
| (not named) | `func rows_for_pair_prefix(prefix: String) -> PackedInt32Array` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:723` | missing in design |
| (not named) | `func rows_since(minute: int) -> PackedInt32Array` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:629` | missing in design |
| (not named) | `func score_matching(actor: StringName, verb: Variant = null, target: Variant = null, place: Variant = null, within: Variant = null, tags: PackedStringArray = PackedStringArray()) -> float` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:580` | missing in design |
| (not named) | `func set_lookup(enabled: bool) -> void` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:675` | missing in design |
| (not named) | `func size() -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:499` | missing in design |
| (not named) | `func target_at(index: int) -> StringName` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:599` | missing in design |
| (not named) | `func target_indexes(agent: StringName) -> PackedInt32Array` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:97` | missing in design |
| (not named) | `func time_buckets() -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:699` | missing in design |
| (not named) | `func time_refs() -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:704` | missing in design |
| (not named) | `func verb_at(index: int) -> StringName` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:591` | missing in design |
| (not named) | `func verb_indexes(verb: StringName) -> PackedInt32Array` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:624` | missing in design |
| (not named) | `func weight_at(index: int) -> float` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:750` | missing in design |
| (not named) | `func weight_stamp() -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:188` | missing in design |
| (not named) | `func witness_buckets() -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:691` | missing in design |
| (not named) | `func witness_count_at(index: int) -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:642` | missing in design |
| (not named) | `func witness_indexes(agent: StringName) -> PackedInt32Array` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:102` | missing in design |
| (not named) | `func witness_mode_name_at(index: int, offset: int) -> String` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:650` | missing in design |
| (not named) | `func witness_name_at(index: int, offset: int) -> String` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:646` | missing in design |
| (not named) | `func witness_refs() -> int` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:695` | missing in design |
| (not named) | `func witnessed(index: int, agent: StringName) -> bool` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:670` | missing in design |
| (not named) | `func witnesses_at(index: int) -> PackedStringArray` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:666` | missing in design |
| (not named) | `var clock: Callable = Callable()` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:32` | missing in design |
| (not named) | `var config_of: Callable = Callable()` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:33` | missing in design |
| (not named) | `var on_compact: Callable = Callable()` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:38` | missing in design |
| (not named) | `var on_perceived: Callable = Callable()` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:36` | missing in design |
| (not named) | `var runtime: WyrdRuntime` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:28` | missing in design |
| (not named) | `var spatial_of: Callable = Callable()` at `addons/wyrd/runtime/deeds/wyrd_deed_log.gd:34` | missing in design |

#### WyrdSocial

| Design | Code | Kind |
|---|---|---|
| (not named) | `set(value) (reflected as @members_of_setter(value: Callable))` at `addons/wyrd/runtime/social/wyrd_social.gd:31` | missing in design |
| (not named) | `func adjust_baseline(a: StringName, b: StringName, axis_name: StringName, n: float) -> bool` at `addons/wyrd/runtime/social/wyrd_social.gd:219` | missing in design |
| (not named) | `func affinity(source: StringName, target: StringName) -> float` at `addons/wyrd/runtime/social/wyrd_social.gd:713` | missing in design |
| (not named) | `func axis(source: StringName, target: StringName, axis_name: StringName) -> float` at `addons/wyrd/runtime/social/wyrd_social.gd:333` | missing in design |
| (not named) | `func cache_bytes() -> int` at `addons/wyrd/runtime/social/wyrd_social.gd:295` | missing in design |
| (not named) | `func cache_enabled() -> bool` at `addons/wyrd/runtime/social/wyrd_social.gd:285` | missing in design |
| (not named) | `func cache_entries() -> int` at `addons/wyrd/runtime/social/wyrd_social.gd:289` | missing in design |
| (not named) | `func clear_baseline(source: StringName, target: StringName, axis_name: StringName) -> void` at `addons/wyrd/runtime/social/wyrd_social.gd:258` | missing in design |
| (not named) | `func clear_kind(source: StringName, target: StringName, kind: StringName) -> void` at `addons/wyrd/runtime/social/wyrd_social.gd:164` | missing in design |
| (not named) | `func clear_state() -> void` at `addons/wyrd/runtime/social/wyrd_social.gd:131` | missing in design |
| (not named) | `func disposition(source: StringName, target: StringName) -> int` at `addons/wyrd/runtime/social/wyrd_social.gd:717` | missing in design |
| (not named) | `func export_state() -> Dictionary` at `addons/wyrd/runtime/social/wyrd_social.gd:84` | missing in design |
| (not named) | `func fill_pair_matrix(count: int) -> void` at `addons/wyrd/runtime/social/wyrd_social.gd:300` | missing in design |
| (not named) | `func has_kind(source: StringName, target: StringName, kind: StringName) -> bool` at `addons/wyrd/runtime/social/wyrd_social.gd:180` | missing in design |
| (not named) | `func import_state(data: Dictionary) -> void` at `addons/wyrd/runtime/social/wyrd_social.gd:114` | missing in design |
| (not named) | `func invalidate_members() -> void` at `addons/wyrd/runtime/social/wyrd_social.gd:271` | missing in design |
| (not named) | `func path_exists(source: StringName, target: StringName, kinds: PackedStringArray, max_hops: int) -> bool` at `addons/wyrd/runtime/social/wyrd_social.gd:752` | missing in design |
| (not named) | `func rebuild_cached(token: String) -> void` at `addons/wyrd/runtime/social/wyrd_social.gd:317` | missing in design |
| (not named) | `func reputation(subject: StringName, group: StringName) -> float` at `addons/wyrd/runtime/social/wyrd_social.gd:383` | missing in design |
| (not named) | `func set_baseline(source: StringName, target: StringName, axis_name: StringName, value: float) -> void` at `addons/wyrd/runtime/social/wyrd_social.gd:209` | missing in design |
| (not named) | `func set_cache(enabled: bool) -> void` at `addons/wyrd/runtime/social/wyrd_social.gd:278` | missing in design |
| (not named) | `func set_kind(source: StringName, target: StringName, kind: StringName) -> void` at `addons/wyrd/runtime/social/wyrd_social.gd:147` | missing in design |
| (not named) | `func sync_cache() -> void` at `addons/wyrd/runtime/social/wyrd_social.gd:312` | missing in design |
| (not named) | `func targets(source: StringName, kind: StringName) -> PackedStringArray` at `addons/wyrd/runtime/social/wyrd_social.gd:189` | missing in design |
| (not named) | `var config_of: Callable = Callable()` at `addons/wyrd/runtime/social/wyrd_social.gd:25` | missing in design |
| (not named) | `var deeds: WyrdDeedLog` at `addons/wyrd/runtime/social/wyrd_social.gd:23` | missing in design |
| (not named) | `var enqueue_cache: Callable = Callable()` at `addons/wyrd/runtime/social/wyrd_social.gd:39` | missing in design |
| (not named) | `var formula: Callable = Callable()` at `addons/wyrd/runtime/social/wyrd_social.gd:26` | missing in design |
| (not named) | `var members_of: Callable = Callable()` at `addons/wyrd/runtime/social/wyrd_social.gd:30` | missing in design |
| (not named) | `var on_cache: Callable = Callable()` at `addons/wyrd/runtime/social/wyrd_social.gd:41` | missing in design |
| (not named) | `var on_changed: Callable = Callable()` at `addons/wyrd/runtime/social/wyrd_social.gd:27` | missing in design |
| (not named) | `var on_reputation: Callable = Callable()` at `addons/wyrd/runtime/social/wyrd_social.gd:37` | missing in design |
| (not named) | `var runtime: WyrdRuntime` at `addons/wyrd/runtime/social/wyrd_social.gd:24` | missing in design |
| (not named) | `var trace_of: Callable = Callable()` at `addons/wyrd/runtime/social/wyrd_social.gd:45` | missing in design |
| (not named) | `var tracing_of: Callable = Callable()` at `addons/wyrd/runtime/social/wyrd_social.gd:43` | missing in design |

#### WyrdRumor

| Design | Code | Kind |
|---|---|---|
| (not named) | `func clear_flight() -> void` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:83` | missing in design |
| (not named) | `func enqueue_due() -> void` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:246` | missing in design |
| (not named) | `func export_state() -> Dictionary` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:96` | missing in design |
| (not named) | `func has_reach() -> bool` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:339` | missing in design |
| (not named) | `func hop(token: String) -> void` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:274` | missing in design |
| (not named) | `func import_state(data: Dictionary) -> Array` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:128` | missing in design |
| (not named) | `func materialize(who: StringName, key: StringName) -> void` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:354` | missing in design |
| (not named) | `static func missing_policy_message(policy_id: String, deed_id: String) -> String` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:191` | missing in design |
| (not named) | `func note_deed(deed: Dictionary, claim_key: String, claim_value: Variant) -> void` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:206` | missing in design |
| (not named) | `func reach_level(deed_id: String, place: StringName) -> int` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:197` | missing in design |
| (not named) | `func register(policy: WyrdRumorPolicy) -> void` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:64` | missing in design |
| (not named) | `var config_of: Callable = Callable()` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:36` | missing in design |
| (not named) | `var deeds: WyrdDeedLog` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:35` | missing in design |
| (not named) | `var enqueue_hop: Callable = Callable()` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:46` | missing in design |
| (not named) | `var facts: WyrdFactStore` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:34` | missing in design |
| (not named) | `var now_of: Callable = Callable()` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:38` | missing in design |
| (not named) | `var on_reach: Callable = Callable()` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:50` | missing in design |
| (not named) | `var reach_any: bool = false` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:52` | missing in design |
| (not named) | `var score_of: Callable = Callable()` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:40` | missing in design |
| (not named) | `var seed_of: Callable = Callable()` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:37` | missing in design |
| (not named) | `var social: WyrdSocial` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:33` | missing in design |
| (not named) | `var spatial_of: Callable = Callable()` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:39` | missing in design |
| (not named) | `var threshold_of: Callable = Callable()` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:41` | missing in design |
| (not named) | `var trace_of: Callable = Callable()` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:42` | missing in design |
| (not named) | `var tracing_of: Callable = Callable()` at `addons/wyrd/runtime/rumor/wyrd_rumor.gd:44` | missing in design |

#### WyrdPublish

| Design | Code | Kind |
|---|---|---|
| (not named) | `func clear() -> void` at `addons/wyrd/runtime/publish/wyrd_publish.gd:63` | missing in design |
| (not named) | `func deeds_known_to(group: StringName, since: int, filter: StringName = &"") -> Array` at `addons/wyrd/runtime/publish/wyrd_publish.gd:194` | missing in design |
| (not named) | `func enqueue_due() -> void` at `addons/wyrd/runtime/publish/wyrd_publish.gd:211` | missing in design |
| (not named) | `func export_state() -> Dictionary` at `addons/wyrd/runtime/publish/wyrd_publish.gd:76` | missing in design |
| (not named) | `func import_state(data: Dictionary) -> void` at `addons/wyrd/runtime/publish/wyrd_publish.gd:110` | missing in design |
| (not named) | `func issue(token: String) -> bool` at `addons/wyrd/runtime/publish/wyrd_publish.gd:226` | missing in design |
| (not named) | `var config_of: Callable = Callable()` at `addons/wyrd/runtime/publish/wyrd_publish.gd:29` | missing in design |
| (not named) | `var content_of: Callable = Callable()` at `addons/wyrd/runtime/publish/wyrd_publish.gd:32` | missing in design |
| (not named) | `var cursor_trace_of: Callable = Callable()` at `addons/wyrd/runtime/publish/wyrd_publish.gd:35` | missing in design |
| (not named) | `var deeds: WyrdDeedLog` at `addons/wyrd/runtime/publish/wyrd_publish.gd:28` | missing in design |
| (not named) | `var enqueue_of: Callable = Callable()` at `addons/wyrd/runtime/publish/wyrd_publish.gd:36` | missing in design |
| (not named) | `var eval_of: Callable = Callable()` at `addons/wyrd/runtime/publish/wyrd_publish.gd:33` | missing in design |
| (not named) | `var facts: WyrdFactStore` at `addons/wyrd/runtime/publish/wyrd_publish.gd:27` | missing in design |
| (not named) | `var members_of: Callable = Callable()` at `addons/wyrd/runtime/publish/wyrd_publish.gd:31` | missing in design |
| (not named) | `var now_of: Callable = Callable()` at `addons/wyrd/runtime/publish/wyrd_publish.gd:30` | missing in design |
| (not named) | `var trace_of: Callable = Callable()` at `addons/wyrd/runtime/publish/wyrd_publish.gd:34` | missing in design |

#### WyrdRoles

| Design | Code | Kind |
|---|---|---|
| (not named) | `func abolished(role: StringName) -> bool` at `addons/wyrd/runtime/roles/wyrd_roles.gd:545` | missing in design |
| (not named) | `func assign_from_content(role: StringName, entity: StringName) -> bool` at `addons/wyrd/runtime/roles/wyrd_roles.gd:593` | missing in design |
| (not named) | `func begin_quest(quest_id: String) -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:962` | missing in design |
| (not named) | `func bind_content(content: WyrdContent) -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:103` | missing in design |
| (not named) | `func bind_instance(instance_id: String, quest: WyrdQuestDef) -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:866` | missing in design |
| (not named) | `func binding_since(role: StringName) -> int` at `addons/wyrd/runtime/roles/wyrd_roles.gd:848` | missing in design |
| (not named) | `func binding_status(role: StringName) -> StringName` at `addons/wyrd/runtime/roles/wyrd_roles.gd:817` | missing in design |
| (not named) | `func cast_pool(slot: WyrdSlotDef) -> Dictionary` at `addons/wyrd/runtime/roles/wyrd_roles.gd:1123` | missing in design |
| (not named) | `func cast_pool_scan(slot: WyrdSlotDef) -> Dictionary` at `addons/wyrd/runtime/roles/wyrd_roles.gd:1134` | missing in design |
| (not named) | `func clear() -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:133` | missing in design |
| (not named) | `func define(role: StringName, succession: String = "none", secret: bool = false, hostile_threshold: int = -1, scope: String = "", eligibility: String = "", default_holder: StringName = &"", vacancy: String = "", visibility: String = "") -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:360` | missing in design |
| (not named) | `func definition(role: StringName) -> Dictionary` at `addons/wyrd/runtime/roles/wyrd_roles.gd:474` | missing in design |
| (not named) | `func departed(role: StringName) -> StringName` at `addons/wyrd/runtime/roles/wyrd_roles.gd:549` | missing in design |
| (not named) | `func drop_cast_index() -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:1160` | missing in design |
| (not named) | `func drop_instances() -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:891` | missing in design |
| (not named) | `func eligible(role: StringName, entity: StringName) -> bool` at `addons/wyrd/runtime/roles/wyrd_roles.gd:495` | missing in design |
| (not named) | `func enter_stage(quest_id: String, stage_id: String) -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:983` | missing in design |
| (not named) | `func export_state() -> Dictionary` at `addons/wyrd/runtime/roles/wyrd_roles.gd:142` | missing in design |
| (not named) | `func freeze_given(quest_id: String, slot: WyrdSlotDef, holder: StringName) -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:911` | missing in design |
| (not named) | `func history(role: StringName) -> Array` at `addons/wyrd/runtime/roles/wyrd_roles.gd:852` | missing in design |
| (not named) | `func holder(slot_or_role: StringName) -> StringName` at `addons/wyrd/runtime/roles/wyrd_roles.gd:733` | missing in design |
| (not named) | `func import_state(data: Dictionary) -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:245` | missing in design |
| (not named) | `func indexed_digest() -> int` at `addons/wyrd/runtime/roles/wyrd_roles.gd:1180` | missing in design |
| (not named) | `func indexed_digest_ready() -> bool` at `addons/wyrd/runtime/roles/wyrd_roles.gd:1176` | missing in design |
| (not named) | `func indexed_pool() -> bool` at `addons/wyrd/runtime/roles/wyrd_roles.gd:1172` | missing in design |
| (not named) | `func install(role: WyrdRoleDef, from_content: bool = false) -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:435` | missing in design |
| (not named) | `func install_casts(quest_id: String, casts: Dictionary) -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:925` | missing in design |
| (not named) | `func instance_casts() -> Dictionary` at `addons/wyrd/runtime/roles/wyrd_roles.gd:941` | missing in design |
| (not named) | `func invalidate_world(ids: PackedStringArray = PackedStringArray()) -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:1167` | missing in design |
| (not named) | `func is_host_defined(role: String) -> bool` at `addons/wyrd/runtime/roles/wyrd_roles.gd:448` | missing in design |
| (not named) | `func note_started() -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:537` | missing in design |
| (not named) | `func param_pool(param: WyrdParamDef) -> Dictionary` at `addons/wyrd/runtime/roles/wyrd_roles.gd:1142` | missing in design |
| (not named) | `func param_pool_scan(param: WyrdParamDef) -> Dictionary` at `addons/wyrd/runtime/roles/wyrd_roles.gd:1153` | missing in design |
| (not named) | `func pick_id(ids: Array, stream: StringName, decision_key: String) -> StringName` at `addons/wyrd/runtime/roles/wyrd_roles.gd:1193` | missing in design |
| (not named) | `func present_role_ids() -> PackedStringArray` at `addons/wyrd/runtime/roles/wyrd_roles.gd:453` | missing in design |
| (not named) | `func render_table(prefix: String = "") -> String` at `addons/wyrd/runtime/roles/wyrd_roles.gd:824` | missing in design |
| (not named) | `func resolve_slot(quest_id: String, slot_name: StringName, trace_it: bool = false) -> Dictionary` at `addons/wyrd/runtime/roles/wyrd_roles.gd:752` | missing in design |
| (not named) | `func revealed(agent: StringName, key: StringName) -> bool` at `addons/wyrd/runtime/roles/wyrd_roles.gd:856` | missing in design |
| (not named) | `func roles_of(entity: StringName) -> PackedStringArray` at `addons/wyrd/runtime/roles/wyrd_roles.gd:720` | missing in design |
| (not named) | `func set_faction_rank(fn: Callable) -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:519` | missing in design |
| (not named) | `func set_host_decides(fn: Callable) -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:526` | missing in design |
| (not named) | `func slot_holder(quest_id: String, slot_name: StringName) -> StringName` at `addons/wyrd/runtime/roles/wyrd_roles.gd:740` | missing in design |
| (not named) | `func slot_state(slot_name: StringName, quest_id: String = "") -> StringName` at `addons/wyrd/runtime/roles/wyrd_roles.gd:744` | missing in design |
| (not named) | `func store_indexed_digest(digest: int) -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:1184` | missing in design |
| (not named) | `func tell(role: StringName, agent: StringName) -> void` at `addons/wyrd/runtime/roles/wyrd_roles.gd:706` | missing in design |
| (not named) | `func vacate_from_content(role: StringName) -> bool` at `addons/wyrd/runtime/roles/wyrd_roles.gd:632` | missing in design |
| (not named) | `var cast_index_enabled: bool = true` at `addons/wyrd/runtime/roles/wyrd_roles.gd:71` | missing in design |
| (not named) | `var clock: Callable = Callable()` at `addons/wyrd/runtime/roles/wyrd_roles.gd:60` | missing in design |
| (not named) | `var config_of: Callable = Callable()` at `addons/wyrd/runtime/roles/wyrd_roles.gd:61` | missing in design |
| (not named) | `var content_of: Callable = Callable()` at `addons/wyrd/runtime/roles/wyrd_roles.gd:62` | missing in design |
| (not named) | `var deeds: WyrdDeedLog` at `addons/wyrd/runtime/roles/wyrd_roles.gd:57` | missing in design |
| (not named) | `var election_of: Callable = Callable()` at `addons/wyrd/runtime/roles/wyrd_roles.gd:84` | missing in design |
| (not named) | `var eval_value: Callable = Callable()` at `addons/wyrd/runtime/roles/wyrd_roles.gd:69` | missing in design |
| (not named) | `var eval_with: Callable = Callable()` at `addons/wyrd/runtime/roles/wyrd_roles.gd:67` | missing in design |
| (not named) | `var faction_rank: Callable = Callable()` at `addons/wyrd/runtime/roles/wyrd_roles.gd:86` | missing in design |
| (not named) | `var facts: WyrdFactStore` at `addons/wyrd/runtime/roles/wyrd_roles.gd:58` | missing in design |
| (not named) | `var host_decides: Callable = Callable()` at `addons/wyrd/runtime/roles/wyrd_roles.gd:88` | missing in design |
| (not named) | `var inventory_of: Callable = Callable()` at `addons/wyrd/runtime/roles/wyrd_roles.gd:65` | missing in design |
| (not named) | `var runtime: WyrdRuntime` at `addons/wyrd/runtime/roles/wyrd_roles.gd:59` | missing in design |
| (not named) | `var seed_of: Callable = Callable()` at `addons/wyrd/runtime/roles/wyrd_roles.gd:82` | missing in design |
| (not named) | `var social: WyrdSocial` at `addons/wyrd/runtime/roles/wyrd_roles.gd:56` | missing in design |
| (not named) | `var stage_of: Callable = Callable()` at `addons/wyrd/runtime/roles/wyrd_roles.gd:80` | missing in design |
| (not named) | `var trace_of: Callable = Callable()` at `addons/wyrd/runtime/roles/wyrd_roles.gd:78` | missing in design |
| (not named) | `var world_of: Callable = Callable()` at `addons/wyrd/runtime/roles/wyrd_roles.gd:63` | missing in design |

#### WyrdTopics

| Design | Code | Kind |
|---|---|---|
| (not named) | `func clear() -> void` at `addons/wyrd/runtime/topics/wyrd_topics.gd:60` | missing in design |
| (not named) | `func export_state() -> PackedStringArray` at `addons/wyrd/runtime/topics/wyrd_topics.gd:64` | missing in design |
| (not named) | `func import_state(ids: Array) -> void` at `addons/wyrd/runtime/topics/wyrd_topics.gd:68` | missing in design |
| (not named) | `func is_unlocked(id: StringName) -> bool` at `addons/wyrd/runtime/topics/wyrd_topics.gd:22` | missing in design |
| (not named) | `func lock(id: StringName) -> String` at `addons/wyrd/runtime/topics/wyrd_topics.gd:47` | missing in design |
| (not named) | `func unlock(id: StringName) -> String` at `addons/wyrd/runtime/topics/wyrd_topics.gd:34` | missing in design |
| (not named) | `func unlocked() -> PackedStringArray` at `addons/wyrd/runtime/topics/wyrd_topics.gd:26` | missing in design |
| (not named) | `var runtime: WyrdRuntime` at `addons/wyrd/runtime/topics/wyrd_topics.gd:17` | missing in design |
| (not named) | `var trace_of: Callable = Callable()` at `addons/wyrd/runtime/topics/wyrd_topics.gd:16` | missing in design |

#### WyrdDocuments

| Design | Code | Kind |
|---|---|---|
| (not named) | `func clear() -> void` at `addons/wyrd/runtime/documents/wyrd_documents.gd:24` | missing in design |
| (not named) | `func export_state() -> Dictionary` at `addons/wyrd/runtime/documents/wyrd_documents.gd:109` | missing in design |
| (not named) | `func has_copy(doc_id: StringName, copy_id: String) -> bool` at `addons/wyrd/runtime/documents/wyrd_documents.gd:33` | missing in design |
| (not named) | `func has_read(reader: StringName, doc_id: StringName) -> bool` at `addons/wyrd/runtime/documents/wyrd_documents.gd:29` | missing in design |
| (not named) | `func import_state(data: Dictionary) -> void` at `addons/wyrd/runtime/documents/wyrd_documents.gd:155` | missing in design |
| (not named) | `func stored_doc_ids() -> PackedStringArray` at `addons/wyrd/runtime/documents/wyrd_documents.gd:137` | missing in design |
| (not named) | `var runtime: WyrdRuntime` at `addons/wyrd/runtime/documents/wyrd_documents.gd:17` | missing in design |

#### WyrdQuestRunner

| Design | Code | Kind |
|---|---|---|
| (not named) | `func abandon(quest_id: String) -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:859` | missing in design |
| (not named) | `func active_count(template_id: String) -> int` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:411` | missing in design |
| (not named) | `func advance(quest_id: String, stage_id: String) -> String` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:784` | missing in design |
| (not named) | `func bind(host: WyrdRuntime) -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:107` | missing in design |
| (not named) | `func clear_event_fires() -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:200` | missing in design |
| (not named) | `func complete_host_step(quest_id: String, values: Dictionary) -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:897` | missing in design |
| (not named) | `func create_instance(template_id: String, casts: Dictionary = {}, params: Dictionary = {}) -> String` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:594` | missing in design |
| (not named) | `static func entry_step_count(body: WyrdStageDef) -> int` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:1075` | missing in design |
| (not named) | `static func entry_steps(body: WyrdStageDef) -> Array` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:1053` | missing in design |
| (not named) | `func expire_due(now: int) -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:830` | missing in design |
| (not named) | `func export_generator() -> Dictionary` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:422` | missing in design |
| (not named) | `func export_state() -> Dictionary` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:513` | missing in design |
| (not named) | `func format_date(minutes: int) -> String` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:156` | missing in design |
| (not named) | `func host_returns(quest_id: String) -> Dictionary` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:380` | missing in design |
| (not named) | `func import_generator(data: Dictionary, report: WyrdLoadReport) -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:478` | missing in design |
| (not named) | `func import_state(data: Dictionary) -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:566` | missing in design |
| (not named) | `func journal(quest_id: String) -> Array` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:340` | missing in design |
| (not named) | `func kept_quest_ids() -> PackedStringArray` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:1885` | missing in design |
| (not named) | `func note_outcome(quest_id: String, branch: StringName, value: StringName) -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:283` | missing in design |
| (not named) | `func note_ready(index: int) -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:162` | missing in design |
| (not named) | `func offer_for(scene_id: String) -> Dictionary` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:387` | missing in design |
| (not named) | `func offered_scene(quest_id: String) -> String` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:326` | missing in design |
| (not named) | `func on_scene_ended(scene_id: String, status: StringName, _reason: StringName) -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:264` | missing in design |
| (not named) | `func on_tick() -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:169` | missing in design |
| (not named) | `func on_world_event(emit_id: int, event_name: StringName, payload: Dictionary) -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:207` | missing in design |
| (not named) | `func outcome(quest_id: String, branch: String) -> String` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:312` | missing in design |
| (not named) | `func param_entity(instance_id: String, name: String) -> StringName` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:401` | missing in design |
| (not named) | `func regions_of(quest_id: String) -> Dictionary` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:305` | missing in design |
| (not named) | `func register_date_formatter(fn: Callable) -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:149` | missing in design |
| (not named) | `static func remember_trail(entries: Array, stage_id: String) -> Array` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:1091` | missing in design |
| (not named) | `func request_host_step(quest_id: String, screen_id: StringName, fields: PackedStringArray = PackedStringArray()) -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:878` | missing in design |
| (not named) | `func reset() -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:113` | missing in design |
| (not named) | `func stage(quest_id: String) -> String` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:297` | missing in design |
| (not named) | `static func stage_body(stage: WyrdStageDef, variant_key: String) -> WyrdStageDef` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:1080` | missing in design |
| (not named) | `func start(quest_id: String) -> void` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:739` | missing in design |
| (not named) | `func status(quest_id: String) -> StringName` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:290` | missing in design |
| (not named) | `func template_counter(template_id: String) -> int` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:397` | missing in design |
| (not named) | `func variant_of(quest_id: String) -> String` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:333` | missing in design |
| (not named) | `func waiting_reason(quest_id: String) -> String` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:319` | missing in design |
| (not named) | `var runtime: WyrdRuntime` at `addons/wyrd/runtime/quests/wyrd_quest_runner.gd:46` | missing in design |

#### WyrdSceneRunner

| Design | Code | Kind |
|---|---|---|
| (not named) | `func audio_for(line_id: String) -> Variant` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:251` | missing in design |
| (not named) | `func bind(host: WyrdRuntime) -> void` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:47` | missing in design |
| (not named) | `func can_save() -> bool` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:72` | missing in design |
| (not named) | `func choices() -> Array[WyrdChoiceView]` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:255` | missing in design |
| (not named) | `func force_close() -> void` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:410` | missing in design |
| (not named) | `func is_open() -> bool` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:60` | missing in design |
| (not named) | `func line() -> WyrdLineView` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:241` | missing in design |
| (not named) | `func note_role(role_id: StringName, _old_holder: StringName, _new_holder: StringName) -> void` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:384` | missing in design |
| (not named) | `func on_tick() -> void` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:367` | missing in design |
| (not named) | `func open_quest_id() -> String` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:65` | missing in design |
| (not named) | `func open_scene(scene_id: String) -> void` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:259` | missing in design |
| (not named) | `func register_line_audio(fn: Callable) -> void` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:53` | missing in design |
| (not named) | `func render_prose(prose: WyrdExprNode, line_id: String) -> String` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:245` | missing in design |
| (not named) | `var locale: String = ""` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:26` | missing in design |
| (not named) | `var runtime: WyrdRuntime` at `addons/wyrd/runtime/scenes/wyrd_scene_runner.gd:25` | missing in design |

#### WyrdStoryletDeck

| Design | Code | Kind |
|---|---|---|
| (not named) | `func bind(content: WyrdContent) -> void` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:32` | missing in design |
| (not named) | `func clear() -> void` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:39` | missing in design |
| (not named) | `func clear_draws() -> void` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:45` | missing in design |
| (not named) | `func clear_speakers() -> void` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:50` | missing in design |
| (not named) | `func draw(id: String, visible: Callable = Callable()) -> Dictionary` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:58` | missing in design |
| (not named) | `func export_speakers() -> Dictionary` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:174` | missing in design |
| (not named) | `func export_state() -> Dictionary` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:144` | missing in design |
| (not named) | `func ignored_ids() -> PackedStringArray` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:165` | missing in design |
| (not named) | `func import_speakers(data: Dictionary) -> void` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:190` | missing in design |
| (not named) | `func import_state(data: Dictionary) -> void` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:208` | missing in design |
| (not named) | `func last_minute_of(id: String) -> int` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:101` | missing in design |
| (not named) | `func note_bark_speaker(key: String, cooldown: int, minute: int) -> void` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:107` | missing in design |
| (not named) | `func note_selected(id: String, minute: int) -> void` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:133` | missing in design |
| (not named) | `func seen_of(id: String) -> int` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:95` | missing in design |
| (not named) | `func set_seed(seed_value: int) -> void` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:54` | missing in design |
| (not named) | `func speaker_cooldown_of(key: String) -> int` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:120` | missing in design |
| (not named) | `func speaker_cooling(key: String, now_minute: int) -> bool` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:113` | missing in design |
| (not named) | `func speaker_remaining(key: String, now_minute: int) -> int` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:126` | missing in design |
| (not named) | `var on_coverage: Callable = Callable()` at `addons/wyrd/runtime/storylets/wyrd_storylet_deck.gd:22` | missing in design |

#### WyrdSequences

| Design | Code | Kind |
|---|---|---|
| (not named) | `func bind(host: WyrdRuntime) -> void` at `addons/wyrd/runtime/quests/wyrd_sequences.gd:18` | missing in design |
| (not named) | `func clear() -> void` at `addons/wyrd/runtime/quests/wyrd_sequences.gd:30` | missing in design |
| (not named) | `func done(id: String) -> bool` at `addons/wyrd/runtime/quests/wyrd_sequences.gd:43` | missing in design |
| (not named) | `func export_state() -> Dictionary` at `addons/wyrd/runtime/quests/wyrd_sequences.gd:107` | missing in design |
| (not named) | `func import_state(data: Dictionary) -> void` at `addons/wyrd/runtime/quests/wyrd_sequences.gd:140` | missing in design |
| (not named) | `func on_emit(event_name: StringName, payload: Dictionary) -> void` at `addons/wyrd/runtime/quests/wyrd_sequences.gd:86` | missing in design |
| (not named) | `func on_tick() -> void` at `addons/wyrd/runtime/quests/wyrd_sequences.gd:52` | missing in design |
| (not named) | `func progress(id: String) -> int` at `addons/wyrd/runtime/quests/wyrd_sequences.gd:34` | missing in design |
| (not named) | `func stored_ids() -> PackedStringArray` at `addons/wyrd/runtime/quests/wyrd_sequences.gd:131` | missing in design |
| (not named) | `var runtime: WyrdRuntime` at `addons/wyrd/runtime/quests/wyrd_sequences.gd:13` | missing in design |

#### WyrdDirector

| Design | Code | Kind |
|---|---|---|
| (not named) | `func bind(runtime: WyrdRuntime) -> void` at `addons/wyrd/runtime/storylets/wyrd_director.gd:57` | missing in design |
| (not named) | `func candidate_rows(scope_kind: String, scope_id: String = "", speaker: String = "") -> Array` at `addons/wyrd/runtime/storylets/wyrd_director.gd:261` | missing in design |
| (not named) | `func diagnose(storylet_id: String, scope_kind: String, scope_id: String = "", speaker: String = "") -> Dictionary` at `addons/wyrd/runtime/storylets/wyrd_director.gd:299` | missing in design |
| (not named) | `func eligible_for_entity(scope_kind: StringName, scope_id: String, entity: String) -> Array` at `addons/wyrd/runtime/storylets/wyrd_director.gd:96` | missing in design |
| (not named) | `static func format_candidate(row: Dictionary) -> String` at `addons/wyrd/runtime/storylets/wyrd_director.gd:327` | missing in design |
| (not named) | `static func format_why_not(row: Dictionary) -> String` at `addons/wyrd/runtime/storylets/wyrd_director.gd:232` | missing in design |
| (not named) | `func query(scope_kind: String, scope_id: String = "", speaker: String = "") -> Dictionary` at `addons/wyrd/runtime/storylets/wyrd_director.gd:61` | missing in design |
| (not named) | `func query_for_entity(scope_kind: String, scope_id: String, entity: String) -> Dictionary` at `addons/wyrd/runtime/storylets/wyrd_director.gd:82` | missing in design |
| (not named) | `func speaker_matches(story_speaker: String, query_speaker: String) -> bool` at `addons/wyrd/runtime/storylets/wyrd_director.gd:323` | missing in design |
| (not named) | `func when_holds(story: WyrdStoryletDef) -> bool` at `addons/wyrd/runtime/storylets/wyrd_director.gd:102` | missing in design |
| (not named) | `func why_not(storylet_id: String, scope_kind: String, scope_id: String = "", speaker: String = "") -> Dictionary` at `addons/wyrd/runtime/storylets/wyrd_director.gd:190` | missing in design |

#### WyrdGenerator

| Design | Code | Kind |
|---|---|---|
| (not named) | `func bind(host: WyrdRuntime) -> void` at `addons/wyrd/runtime/generator/wyrd_generator.gd:60` | missing in design |
| (not named) | `func clear() -> void` at `addons/wyrd/runtime/generator/wyrd_generator.gd:64` | missing in design |
| (not named) | `func finish_reservations() -> void` at `addons/wyrd/runtime/generator/wyrd_generator.gd:223` | missing in design |
| (not named) | `func fulfill(entry: Dictionary) -> void` at `addons/wyrd/runtime/generator/wyrd_generator.gd:260` | missing in design |
| (not named) | `func pending() -> Array` at `addons/wyrd/runtime/generator/wyrd_generator.gd:49` | missing in design |
| (not named) | `func pending_count() -> int` at `addons/wyrd/runtime/generator/wyrd_generator.gd:56` | missing in design |
| (not named) | `func pending_creations() -> Array` at `addons/wyrd/runtime/generator/wyrd_generator.gd:216` | missing in design |
| (not named) | `func proposal(id: String) -> WyrdProposal` at `addons/wyrd/runtime/generator/wyrd_generator.gd:212` | missing in design |
| (not named) | `func queue_deed(template_id: String, deed_id: String, payload: Dictionary) -> void` at `addons/wyrd/runtime/generator/wyrd_generator.gd:43` | missing in design |
| (not named) | `func take_next() -> Dictionary` at `addons/wyrd/runtime/generator/wyrd_generator.gd:105` | missing in design |
| (not named) | `func tier_matches(offer_tier: StringName, template: WyrdTemplateDef) -> bool` at `addons/wyrd/runtime/generator/wyrd_generator.gd:87` | missing in design |
| (not named) | `func tier_rank(name: String) -> int` at `addons/wyrd/runtime/generator/wyrd_generator.gd:75` | missing in design |
| (not named) | `func why_not(template_id: String) -> Dictionary` at `addons/wyrd/runtime/generator/wyrd_generator.gd:314` | missing in design |
| (not named) | `var candidate_traces: int = 0` at `addons/wyrd/runtime/generator/wyrd_generator.gd:24` | missing in design |
| (not named) | `var config_of: Callable = Callable()` at `addons/wyrd/runtime/generator/wyrd_generator.gd:12` | missing in design |
| (not named) | `var generate_handler: Callable = Callable()` at `addons/wyrd/runtime/generator/wyrd_generator.gd:11` | missing in design |
| (not named) | `var runtime: WyrdRuntime = null` at `addons/wyrd/runtime/generator/wyrd_generator.gd:14` | missing in design |
| (not named) | `var trace_of: Callable = Callable()` at `addons/wyrd/runtime/generator/wyrd_generator.gd:13` | missing in design |

#### WyrdAI

| Design | Code | Kind |
|---|---|---|
| (not named) | `func bind(runtime: WyrdRuntime) -> void` at `addons/wyrd/runtime/ai/wyrd_ai.gd:40` | missing in design |
| (not named) | `func cache_key(kind: StringName, packet: Dictionary, locale: StringName = &"") -> String` at `addons/wyrd/runtime/ai/wyrd_ai.gd:331` | missing in design |
| (not named) | `func cache_keys() -> PackedStringArray` at `addons/wyrd/runtime/ai/wyrd_ai.gd:504` | missing in design |
| (not named) | `func cache_size() -> int` at `addons/wyrd/runtime/ai/wyrd_ai.gd:499` | missing in design |
| (not named) | `func cached_text(key: String) -> String` at `addons/wyrd/runtime/ai/wyrd_ai.gd:495` | missing in design |
| (not named) | `func clear_cache() -> void` at `addons/wyrd/runtime/ai/wyrd_ai.gd:509` | missing in design |
| (not named) | `func close_owner(owner: String, reason: StringName) -> void` at `addons/wyrd/runtime/ai/wyrd_ai.gd:319` | missing in design |
| (not named) | `func close_prefixed(prefix: String, reason: StringName) -> void` at `addons/wyrd/runtime/ai/wyrd_ai.gd:324` | missing in design |
| (not named) | `func drop_pending(reason: StringName) -> void` at `addons/wyrd/runtime/ai/wyrd_ai.gd:461` | missing in design |
| (not named) | `func export_cache() -> Dictionary` at `addons/wyrd/runtime/ai/wyrd_ai.gd:521` | missing in design |
| (not named) | `func import_cache(raw: Variant, present: bool, report: WyrdLoadReport) -> void` at `addons/wyrd/runtime/ai/wyrd_ai.gd:527` | missing in design |
| (not named) | `func is_active() -> bool` at `addons/wyrd/runtime/ai/wyrd_ai.gd:68` | missing in design |
| (not named) | `func is_enabled() -> bool` at `addons/wyrd/runtime/ai/wyrd_ai.gd:53` | missing in design |
| (not named) | `func kind_for_line(line_id: String) -> StringName` at `addons/wyrd/runtime/ai/wyrd_ai.gd:348` | missing in design |
| (not named) | `func kinds() -> Array[StringName]` at `addons/wyrd/runtime/ai/wyrd_ai.gd:72` | missing in design |
| (not named) | `func locale_ok(locale: String = "") -> bool` at `addons/wyrd/runtime/ai/wyrd_ai.gd:182` | missing in design |
| (not named) | `func packet_for_line(line_id: String, kind: StringName = &"bark_paraphrase", speaker: StringName = &"") -> Dictionary` at `addons/wyrd/runtime/ai/wyrd_ai.gd:358` | missing in design |
| (not named) | `func pending_count() -> int` at `addons/wyrd/runtime/ai/wyrd_ai.gd:155` | missing in design |
| (not named) | `func prefetch_carry() -> int` at `addons/wyrd/runtime/ai/wyrd_ai.gd:273` | missing in design |
| (not named) | `func prefetch_has_work() -> bool` at `addons/wyrd/runtime/ai/wyrd_ai.gd:268` | missing in design |
| (not named) | `func prefetch_lines(source: StringName, id: String, rows: Array, owner_cap: int = -1) -> void` at `addons/wyrd/runtime/ai/wyrd_ai.gd:203` | missing in design |
| (not named) | `func prefetch_unit() -> void` at `addons/wyrd/runtime/ai/wyrd_ai.gd:278` | missing in design |
| (not named) | `func present(view: WyrdLineView, line_id: String) -> void` at `addons/wyrd/runtime/ai/wyrd_ai.gd:287` | missing in design |
| (not named) | `func provider() -> WyrdAIProvider` at `addons/wyrd/runtime/ai/wyrd_ai.gd:57` | missing in design |
| (not named) | `func provider_id() -> StringName` at `addons/wyrd/runtime/ai/wyrd_ai.gd:61` | missing in design |
| (not named) | `func set_provider(next: WyrdAIProvider) -> void` at `addons/wyrd/runtime/ai/wyrd_ai.gd:451` | missing in design |
| (not named) | `func summary_for(quest_id: String, entries: Array) -> String` at `addons/wyrd/runtime/ai/wyrd_ai.gd:388` | missing in design |
| (not named) | `func summary_packet(quest_id: String, entries: Array) -> Dictionary` at `addons/wyrd/runtime/ai/wyrd_ai.gd:363` | missing in design |
| (not named) | `func tick_prefetch(now: int, scheduler: WyrdScheduler) -> void` at `addons/wyrd/runtime/ai/wyrd_ai.gd:243` | missing in design |
| (not named) | `func validate(text: String, kind: StringName, packet: Dictionary, constraints: Dictionary = {}) -> StringName` at `addons/wyrd/runtime/ai/wyrd_ai.gd:427` | missing in design |

#### WyrdConfig

| Design | Code | Kind |
|---|---|---|
| (not named) | `func axis_delta(verb: StringName, axis_name: StringName) -> float` at `addons/wyrd/runtime/wyrd_config.gd:156` | missing in design |
| (not named) | `func half_life_for(verb: StringName) -> float` at `addons/wyrd/runtime/wyrd_config.gd:105` | missing in design |
| (not named) | `func kind_scale(kind: StringName, axis_name: StringName) -> float` at `addons/wyrd/runtime/wyrd_config.gd:137` | missing in design |
| (not named) | `func scales_for(axis_name: StringName) -> Array` at `addons/wyrd/runtime/wyrd_config.gd:146` | missing in design |
| (not named) | `func set_axis_delta(verb: StringName, axis_name: StringName, delta: float) -> void` at `addons/wyrd/runtime/wyrd_config.gd:113` | missing in design |
| (not named) | `func set_kind_scale(kind: StringName, axis_name: StringName, scale: float) -> void` at `addons/wyrd/runtime/wyrd_config.gd:125` | missing in design |
| (not named) | `@export var ai_banned_terms: PackedStringArray = PackedStringArray()` at `addons/wyrd/runtime/wyrd_config.gd:90` | missing in design |
| (not named) | `@export var ai_cache_max: int = 256` at `addons/wyrd/runtime/wyrd_config.gd:94` | missing in design |
| (not named) | `@export var ai_max_inflight: int = 4` at `addons/wyrd/runtime/wyrd_config.gd:102` | missing in design |
| (not named) | `@export var ai_save_cache: bool = true` at `addons/wyrd/runtime/wyrd_config.gd:97` | missing in design |
| (not named) | `@export var axis_deltas: PackedFloat64Array = PackedFloat64Array()` at `addons/wyrd/runtime/wyrd_config.gd:37` | missing in design |
| (not named) | `@export var axis_names: PackedStringArray = PackedStringArray()` at `addons/wyrd/runtime/wyrd_config.gd:36` | missing in design |
| (not named) | `@export var axis_verbs: PackedStringArray = PackedStringArray()` at `addons/wyrd/runtime/wyrd_config.gd:35` | missing in design |
| (not named) | `@export var compact_after: int = 0` at `addons/wyrd/runtime/wyrd_config.gd:76` | missing in design |
| (not named) | `@export var credibility_threshold: float = 0.5` at `addons/wyrd/runtime/wyrd_config.gd:74` | missing in design |
| (not named) | `@export var generator_retries: int = 8` at `addons/wyrd/runtime/wyrd_config.gd:83` | missing in design |
| (not named) | `@export var half_life_minutes: PackedFloat64Array = PackedFloat64Array()` at `addons/wyrd/runtime/wyrd_config.gd:32` | missing in design |
| (not named) | `@export var half_life_verbs: PackedStringArray = PackedStringArray()` at `addons/wyrd/runtime/wyrd_config.gd:31` | missing in design |
| (not named) | `@export var hostile_threshold: int = 20` at `addons/wyrd/runtime/wyrd_config.gd:34` | missing in design |
| (not named) | `@export var hour_bucket_minutes: int = 60` at `addons/wyrd/runtime/wyrd_config.gd:30` | missing in design |
| (not named) | `@export var kind_scale_axes: PackedStringArray = PackedStringArray()` at `addons/wyrd/runtime/wyrd_config.gd:40` | missing in design |
| (not named) | `@export var kind_scale_kinds: PackedStringArray = PackedStringArray()` at `addons/wyrd/runtime/wyrd_config.gd:39` | missing in design |
| (not named) | `@export var kind_scale_values: PackedFloat64Array = PackedFloat64Array()` at `addons/wyrd/runtime/wyrd_config.gd:41` | missing in design |
| (not named) | `@export var pressure_tiers: PackedStringArray = PackedStringArray()` at `addons/wyrd/runtime/wyrd_config.gd:80` | missing in design |
| (not named) | `@export var publish_catchup_max: int = 3` at `addons/wyrd/runtime/wyrd_config.gd:68` | missing in design |
| (not named) | `@export var publish_slice_rows: int = 128` at `addons/wyrd/runtime/wyrd_config.gd:72` | missing in design |
| (not named) | `@export var rumor_coarse_minutes: int = 60` at `addons/wyrd/runtime/wyrd_config.gd:64` | missing in design |
| (not named) | `@export var scheduler_frame_warn_usec: int = 2000` at `addons/wyrd/runtime/wyrd_config.gd:61` | missing in design |
| (not named) | `@export var scheduler_share_ai_prefetch: int = 0` at `addons/wyrd/runtime/wyrd_config.gd:57` | missing in design |
| (not named) | `@export var scheduler_share_cache: int = 4` at `addons/wyrd/runtime/wyrd_config.gd:51` | missing in design |
| (not named) | `@export var scheduler_share_generate: int = 0` at `addons/wyrd/runtime/wyrd_config.gd:54` | missing in design |
| (not named) | `@export var scheduler_share_publish: int = 8` at `addons/wyrd/runtime/wyrd_config.gd:50` | missing in design |
| (not named) | `@export var scheduler_share_rumor: int = 12` at `addons/wyrd/runtime/wyrd_config.gd:49` | missing in design |
| (not named) | `@export var scheduler_share_waits: int = 40` at `addons/wyrd/runtime/wyrd_config.gd:48` | missing in design |
| (not named) | `@export var scheduler_tick_minutes: int = 1` at `addons/wyrd/runtime/wyrd_config.gd:45` | missing in design |
| (not named) | `@export var scheduler_work_per_tick: int = 64` at `addons/wyrd/runtime/wyrd_config.gd:42` | missing in design |
| (not named) | `@export var secrecy_fact: String = "player.clearance"` at `addons/wyrd/runtime/wyrd_config.gd:85` | missing in design |
| (not named) | `@export var secrecy_tiers: PackedStringArray = PackedStringArray()` at `addons/wyrd/runtime/wyrd_config.gd:78` | missing in design |
| (not named) | `@export var trace_director: bool = false` at `addons/wyrd/runtime/wyrd_config.gd:88` | missing in design |

#### WyrdLoadReport

| Design | Code | Kind |
|---|---|---|
| (not named) | `func add_row(kind: String, id: String, from_value: String, to_value: String, count: int, code: String) -> void` at `addons/wyrd/runtime/wyrd_load_report.gd:26` | missing in design |
| (not named) | `func error_count() -> int` at `addons/wyrd/runtime/wyrd_load_report.gd:51` | missing in design |
| (not named) | `func sort_rows() -> void` at `addons/wyrd/runtime/wyrd_load_report.gd:37` | missing in design |
| (not named) | `var diagnostics: WyrdDiagnostics` at `addons/wyrd/runtime/wyrd_load_report.gd:17` | missing in design |
| (not named) | `var manifest_hash: int = 0` at `addons/wyrd/runtime/wyrd_load_report.gd:18` | missing in design |
| (not named) | `var ok: bool = false` at `addons/wyrd/runtime/wyrd_load_report.gd:16` | missing in design |
| (not named) | `var rows: Array = []` at `addons/wyrd/runtime/wyrd_load_report.gd:19` | missing in design |

#### WyrdLineView

| Design | Code | Kind |
|---|---|---|
| (not named) | `var audio: Variant = null` at `addons/wyrd/runtime/scenes/wyrd_line_view.gd:22` | missing in design |
| (not named) | `var display_name: String = ""` at `addons/wyrd/runtime/scenes/wyrd_line_view.gd:12` | missing in design |
| (not named) | `var id: String = ""` at `addons/wyrd/runtime/scenes/wyrd_line_view.gd:10` | missing in design |
| (not named) | `var roles: PackedStringArray = PackedStringArray()` at `addons/wyrd/runtime/scenes/wyrd_line_view.gd:16` | missing in design |
| (not named) | `var speaker: StringName = &""` at `addons/wyrd/runtime/scenes/wyrd_line_view.gd:11` | missing in design |
| (not named) | `var tags: PackedStringArray = PackedStringArray()` at `addons/wyrd/runtime/scenes/wyrd_line_view.gd:21` | missing in design |
| (not named) | `var text: String = ""` at `addons/wyrd/runtime/scenes/wyrd_line_view.gd:17` | missing in design |

#### WyrdContentManifest

| Design | Code | Kind |
|---|---|---|
| (not named) | `@export var files: PackedStringArray = PackedStringArray()` at `addons/wyrd/compiler/wyrd_content_manifest.gd:13` | missing in design |
| (not named) | `@export var language_version: int = 1` at `addons/wyrd/compiler/wyrd_content_manifest.gd:14` | missing in design |
| (not named) | `@export var pack_id: StringName = &""` at `addons/wyrd/compiler/wyrd_content_manifest.gd:12` | missing in design |

#### WyrdCommand

| Design | Code | Kind |
|---|---|---|
| (not named) | `var args: Dictionary = {}` at `addons/wyrd/runtime/adapters/wyrd_command.gd:10` | missing in design |
| (not named) | `var name: StringName = &""` at `addons/wyrd/runtime/adapters/wyrd_command.gd:9` | missing in design |

#### WyrdCommandResult

| Design | Code | Kind |
|---|---|---|
| (not named) | `func is_ok() -> bool` at `addons/wyrd/runtime/adapters/wyrd_command_result.gd:28` | missing in design |
| (not named) | `var reason: StringName = &""` at `addons/wyrd/runtime/adapters/wyrd_command_result.gd:11` | missing in design |
| (not named) | `var status: Status = Status.FAILED` at `addons/wyrd/runtime/adapters/wyrd_command_result.gd:10` | missing in design |

#### WyrdCommandSchema

| Design | Code | Kind |
|---|---|---|
| (not named) | `func add_command(command_name: StringName) -> void` at `addons/wyrd/runtime/adapters/wyrd_command_schema.gd:15` | missing in design |
| (not named) | `func add_skill(skill_name: StringName) -> void` at `addons/wyrd/runtime/adapters/wyrd_command_schema.gd:24` | missing in design |
| (not named) | `func has_command(command_name: StringName) -> bool` at `addons/wyrd/runtime/adapters/wyrd_command_schema.gd:20` | missing in design |
| (not named) | `func has_skill(skill_name: StringName) -> bool` at `addons/wyrd/runtime/adapters/wyrd_command_schema.gd:29` | missing in design |
| (not named) | `var checks_skills: bool = false` at `addons/wyrd/runtime/adapters/wyrd_command_schema.gd:12` | missing in design |
| (not named) | `var command_names: Array[StringName] = []` at `addons/wyrd/runtime/adapters/wyrd_command_schema.gd:10` | missing in design |
| (not named) | `var skill_names: Array[StringName] = []` at `addons/wyrd/runtime/adapters/wyrd_command_schema.gd:11` | missing in design |

#### WyrdEntityFilter

| Design | Code | Kind |
|---|---|---|
| (not named) | `var kind: StringName = &""` at `addons/wyrd/runtime/adapters/wyrd_entity_filter.gd:12` | missing in design |
| (not named) | `var tag: StringName = &""` at `addons/wyrd/runtime/adapters/wyrd_entity_filter.gd:11` | missing in design |

#### WyrdSkillCheck

| Design | Code | Kind |
|---|---|---|
| (not named) | `var args: Dictionary = {}` at `addons/wyrd/runtime/adapters/wyrd_skill_check.gd:12` | missing in design |
| (not named) | `var choice_id: String = ""` at `addons/wyrd/runtime/adapters/wyrd_skill_check.gd:14` | missing in design |
| (not named) | `var roll: float = 0.0` at `addons/wyrd/runtime/adapters/wyrd_skill_check.gd:15` | missing in design |
| (not named) | `var scene_id: String = ""` at `addons/wyrd/runtime/adapters/wyrd_skill_check.gd:13` | missing in design |
| (not named) | `var skill: StringName = &""` at `addons/wyrd/runtime/adapters/wyrd_skill_check.gd:11` | missing in design |
