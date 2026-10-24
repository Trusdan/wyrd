# Adapter guide

A host subclasses each adapter base and passes the instance to [`Wyrd.register_adapter`](api/Wyrd.md#register_adapter). The base argument is the script, as in `Wyrd.register_adapter(WyrdWorldAdapter, world_adapter)`. The adapter's script must extend that base directly. A method left on the stub reports that it is not implemented and returns the typed fallback named below. The order of steps for a host is [the host checklist](host-checklist.md).

Content built-ins for world, inventory, and spatial reads treat a missing adapter as empty, false, or zero, and do not call the stub. Register the adapter when the host wants a real answer.

## WyrdWorldAdapter

Wyrd asks this adapter what entities exist, what they are, and which ones match a cast. It never walks the scene tree. Register one for any pack that casts roles or reads entities. The scripted host is [`tests/fake_host/wyrd_fake_world.gd`](../tests/fake_host/wyrd_fake_world.gd).

Methods on [WyrdWorldAdapter](api/WyrdWorldAdapter.md):

- [`exists`](api/WyrdWorldAdapter.md#exists), [`kind`](api/WyrdWorldAdapter.md#kind), [`tags`](api/WyrdWorldAdapter.md#tags), [`attr`](api/WyrdWorldAdapter.md#attr), [`is_alive`](api/WyrdWorldAdapter.md#is_alive), [`display_name`](api/WyrdWorldAdapter.md#display_name), and [`members`](api/WyrdWorldAdapter.md#members) report that they are not implemented. They return false, an empty name, null, an empty string, or an empty list.
- [`is_protected`](api/WyrdWorldAdapter.md#is_protected) defaults to false and does not report an error.
- [`in_bounds`](api/WyrdWorldAdapter.md#in_bounds) defaults to true and does not report an error.
- [`groups_of`](api/WyrdWorldAdapter.md#groups_of) defaults to an empty list and does not report an error. A membership change is unseen until the host emits `groups_changed` or calls [`invalidate_groups`](api/Wyrd.md#invalidate_groups).
- [`reports_changes`](api/WyrdWorldAdapter.md#reports_changes) defaults to false. Returning true is a promise to call [`invalidate_world`](api/Wyrd.md#invalidate_world) when an entity, its kind, tags, liveness, attributes, or candidate membership changes.
- [`candidates`](api/WyrdWorldAdapter.md#candidates) returns ids that match a [`WyrdEntityFilter`](api/WyrdEntityFilter.md). An item cast uses kind `item`. The stub reports that it is not implemented and returns an empty list.

## WyrdInventoryAdapter

Wyrd asks what a holder carries. A missing adapter makes `has` false, `count` zero, and `owner_of` empty. The scripted host is [`tests/fake_host/wyrd_fake_inventory.gd`](../tests/fake_host/wyrd_fake_inventory.gd).

Every method on [WyrdInventoryAdapter](api/WyrdInventoryAdapter.md) reports that it is not implemented:

- [`count`](api/WyrdInventoryAdapter.md#count) takes an item id or a tag and returns 0.
- [`items`](api/WyrdInventoryAdapter.md#items) takes a tag. An empty tag asks for every item that holder carries. The stub returns an empty list.
- [`owner_of`](api/WyrdInventoryAdapter.md#owner_of) returns an empty name.

## WyrdSpatialAdapter

Wyrd asks where things are and who can perceive or reach them. It never touches the scene tree. A missing adapter makes `nearby` zero and `can_perceive` and `can_reach` false. The scripted host is [`tests/fake_host/wyrd_fake_spatial.gd`](../tests/fake_host/wyrd_fake_spatial.gd).

Methods on [WyrdSpatialAdapter](api/WyrdSpatialAdapter.md):

- [`nearby`](api/WyrdSpatialAdapter.md#nearby), [`place_of`](api/WyrdSpatialAdapter.md#place_of), [`distance`](api/WyrdSpatialAdapter.md#distance), [`can_perceive`](api/WyrdSpatialAdapter.md#can_perceive), and [`can_reach`](api/WyrdSpatialAdapter.md#can_reach) report that they are not implemented. `distance` returns `INF`. The others return an empty list, an empty name, or false.
- [`witnesses_of`](api/WyrdSpatialAdapter.md#witnesses_of) defaults to an empty list and does not report an error.
- [`precision`](api/WyrdSpatialAdapter.md#precision) defaults to `precise` and does not report an error. A coarse place does not spread a rumor hop.
- [`perceive`](api/WyrdSpatialAdapter.md#perceive) defaults to `saw` and does not report an error. The other answers are `heard`, `inferred`, or empty when the observer did not perceive the deed.

## WyrdTimeAdapter

Wyrd asks for whole minutes from the game epoch, and for the season symbol content reads as `time.season`. The calendar is not on this adapter. The scripted host is [`tests/fake_host/wyrd_fake_time.gd`](../tests/fake_host/wyrd_fake_time.gd).

Both methods on [WyrdTimeAdapter](api/WyrdTimeAdapter.md) report that they are not implemented. [`now_minutes`](api/WyrdTimeAdapter.md#now_minutes) returns 0. [`season`](api/WyrdTimeAdapter.md#season) returns an empty name.

## WyrdActionAdapter

Wyrd asks this adapter to run a `do` command. The scripted host is [`tests/fake_host/wyrd_fake_actions.gd`](../tests/fake_host/wyrd_fake_actions.gd).

Both methods on [WyrdActionAdapter](api/WyrdActionAdapter.md) report that they are not implemented. [`command_schema`](api/WyrdActionAdapter.md#command_schema) returns an empty [`WyrdCommandSchema`](api/WyrdCommandSchema.md). [`execute`](api/WyrdActionAdapter.md#execute) returns a failed [`WyrdCommandResult`](api/WyrdCommandResult.md) whose reason is `not_implemented`, so a stub is never a success.

## WyrdElectionAdapter

Wyrd asks the host to run an election. It does not pick the successor. This adapter is optional. When succession is `election` and no adapter is registered, [`election_needed`](api/Wyrd.md#election_needed) still fires and `start_election` is not called. No file under `tests/fake_host/` extends this base. The Gullhaven playtest uses [`example/playtest/harbor_election.gd`](../example/playtest/harbor_election.gd), whose `start_election` returns without choosing a holder. The host finishes the contest with `assign`.

[`start_election`](api/WyrdElectionAdapter.md#start_election) is the only method. The stub reports that it is not implemented.

## WyrdAIProvider

Wyrd asks a provider to start an answer and return at once. The answer comes later, on the main thread, through [`WyrdAIRequest.reply`](api/WyrdAIRequest.md#reply) or [`WyrdAI.deliver`](api/WyrdAI.md#deliver). A provider never waits, and the core has no network code. This adapter is optional. The runtime registers a null provider, [`Wyrd.ai`](api/WyrdAI.md) stays idle, and a host that does not use AI does nothing. [`request`](api/WyrdAI.md#request) returns 0 while that null provider is in place.

The scripted provider is [`tests/fake_host/wyrd_fake_ai_text.gd`](../tests/fake_host/wyrd_fake_ai_text.gd). [`tests/fake_host/wyrd_fake_ai.gd`](../tests/fake_host/wyrd_fake_ai.gd) holds further test providers.

Every method on [WyrdAIProvider](api/WyrdAIProvider.md) reports that it is not implemented. [`id`](api/WyrdAIProvider.md#id) returns an empty name, [`prompt_version`](api/WyrdAIProvider.md#prompt_version) returns 0, [`locales`](api/WyrdAIProvider.md#locales) returns an empty list, and [`request`](api/WyrdAIProvider.md#request) and [`cancel`](api/WyrdAIProvider.md#cancel) return nothing.

## WyrdSkillAdapter

Wyrd asks the host to resolve a choice's `check` before that choice's effects run. This adapter is optional until a choice has a check. With no adapter, the check fails with reason `no_adapter` and the choice diverts to `on_fail`. The scripted host is [`tests/fake_host/wyrd_fake_skills.gd`](../tests/fake_host/wyrd_fake_skills.gd). Tests register it themselves; [`WyrdFakeHost`](../tests/fake_host/wyrd_fake_host.gd) does not.

[`check`](api/WyrdSkillAdapter.md#check) is the only method. It receives a [`WyrdSkillCheck`](api/WyrdSkillCheck.md). The stub reports that it is not implemented and returns a failed [`WyrdCommandResult`](api/WyrdCommandResult.md) with reason `not_implemented`.

## Command schema

`load_content` reads `wyrd_commands.json` beside the manifest. The file is optional. A missing file skips the command-name check when a `do` exists. Gullhaven's file is [`example/content/gullhaven/wyrd_commands.json`](../example/content/gullhaven/wyrd_commands.json):

```text
{
  "commands": ["assign_lodging", "post_notice"],
  "skills": ["strength"]
}
```

`commands` are the names a `do` may call. When `skills` is present, a `check` whose skill is not in that list is `E_SKILL_UNKNOWN`. Without the key, skills are not checked. See [Commands](language.md#linking) and [skill checks](language.md#scene).

## Registered functions

[`register_function`](api/Wyrd.md#register_function) adds a pure host callable that content can call. The argument types and the return type are `.wyrd` type names: `bool`, `int`, `float`, `symbol`, `entity`, `duration`, `distance`, `set`, and `fact_key`. It returns false when the callable is missing, the name is already used, or the types do not match a signature already stored for that name.

```gdscript
Wyrd.register_function(&"coins_of", coins_of, ["entity"], &"int")
```

## Disposition formula

[`register_disposition_formula`](api/Wyrd.md#register_disposition_formula) forwards to [`WyrdSocial.register_formula`](api/WyrdSocial.md#register_formula). The callable receives `(a, b, axes)` and is not saved. The default disposition is `disposition_default + affinity / 2`, clamped to 0..100. [`disposition_default`](api/WyrdConfig.md#disposition_default) is 50 unless the host changes it.
