extends GutTest


func test_harness_wires_five_adapters() -> void:
	var host := WyrdFakeHost.new()
	assert_eq(host.adapter_count(), 5)
	assert_same(host.adapter_for(WyrdWorldAdapter), host.world)
	assert_same(host.adapter_for(WyrdInventoryAdapter), host.inventory)
	assert_same(host.adapter_for(WyrdSpatialAdapter), host.spatial)
	assert_same(host.adapter_for(WyrdTimeAdapter), host.clock)
	assert_same(host.adapter_for(WyrdActionAdapter), host.actions)

	var ana := &"fisher_ana"
	host.world.add_entity(ana, &"person", "Ana", PackedStringArray([&"fisher"]), true)
	host.world.set_attr(ana, &"home", &"gullhaven")
	var world := host.adapter_for(WyrdWorldAdapter) as WyrdWorldAdapter
	assert_true(world.exists(ana))
	assert_eq(world.kind(ana), &"person")
	assert_eq(world.display_name(ana), "Ana")
	assert_true(world.is_alive(ana))
	assert_eq(world.tags(ana), PackedStringArray([&"fisher"]))
	assert_eq(world.attr(ana, &"home"), &"gullhaven")
	assert_false(world.exists(&"missing"))

	host.inventory.set_count(ana, &"coin", 2)
	host.inventory.set_items(ana, &"", PackedStringArray([&"coin"]))
	host.inventory.set_owner(&"coin", ana)
	var inventory := host.adapter_for(WyrdInventoryAdapter) as WyrdInventoryAdapter
	assert_eq(inventory.count(ana, &"coin"), 2)
	assert_eq(inventory.items(ana, &""), PackedStringArray([&"coin"]))
	assert_eq(inventory.owner_of(&"coin"), ana)

	host.spatial.set_place(ana, &"gullhaven.dock")
	host.spatial.set_distance(ana, &"player", 3.0)
	host.spatial.set_can_perceive(ana, &"player", true)
	host.spatial.set_can_reach(&"player", &"gullhaven.dock", true)
	host.spatial.set_nearby(&"player", 6.0, &"fisher", PackedStringArray([ana]))
	var spatial := host.adapter_for(WyrdSpatialAdapter) as WyrdSpatialAdapter
	assert_eq(spatial.place_of(ana), &"gullhaven.dock")
	assert_eq(spatial.distance(&"player", ana), 3.0)
	assert_true(spatial.can_perceive(ana, &"player"))
	assert_true(spatial.can_reach(&"player", &"gullhaven.dock"))
	assert_eq(spatial.nearby(&"player", 6.0, WyrdEntityFilter.new(&"fisher")), PackedStringArray([ana]))
	assert_eq(spatial.distance(ana, &"nobody"), INF)

	host.clock.set_minutes(480)
	var clock := host.adapter_for(WyrdTimeAdapter) as WyrdTimeAdapter
	assert_eq(clock.now_minutes(), 480)

	host.actions.schema.add_command(&"assign_lodging")
	host.actions.set_result(WyrdCommandResult.failed(&"no_room"))
	var actions := host.adapter_for(WyrdActionAdapter) as WyrdActionAdapter
	assert_true(actions.command_schema().has_command(&"assign_lodging"))
	var outcome := actions.execute(WyrdCommand.new(&"assign_lodging", {"place": &"gullhaven.tavern"}))
	assert_false(outcome.is_ok())
	assert_eq(outcome.reason, &"no_room")
	assert_eq(host.actions.executed, [&"assign_lodging"])
