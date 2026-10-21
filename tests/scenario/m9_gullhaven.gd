extends RefCounted

const _Harness := preload("res://tests/scenario/s2c_harness.gd")


func boot_generated(seed: int = 1) -> Dictionary:
	var harness := _Harness.new()
	var opened: Dictionary = harness.boot_gullhaven()
	var runtime: WyrdRuntime = opened["runtime"]
	var host: WyrdFakeHost = opened["host"]
	if seed != 1:
		runtime.start_new_game(seed)
		runtime.roles.assign(&"tavern_owner", &"tavern_owner")
		runtime.roles.assign(&"ferry_master", &"ferry_master")
		runtime.roles.assign(&"storm_watcher", &"storm_watcher")
		runtime.facts.set(&"player.coins", 4)
		runtime.facts.set(&"world.storm_heard", true)
		runtime.deeds.record(&"arrived", &"player", &"", &"gullhaven")
		runtime.tick(0)
	runtime.config().pressure_tiers = PackedStringArray(["low", "mid", "high"])
	var world: WyrdFakeWorld = host.world
	world.add_entity(&"dock_apprentice", &"person", "Nia", PackedStringArray(["dock"]), true)
	world.add_entity(&"line_fisher", &"person", "fisher", PackedStringArray(["fisher"]), true)
	world.add_entity(&"pier_fisher", &"person", "pier fisher", PackedStringArray(["fisher"]), true)
	world.add_entity(&"net_mender", &"person", "net mender", PackedStringArray(), true)
	world.add_entity(&"visitor", &"person", "visitor", PackedStringArray(["visitor"]), true)
	world.add_entity(&"net.mended", &"item", "mended net", PackedStringArray(["net"]), true)
	world.add_entity(&"catch.day", &"item", "day's catch", PackedStringArray(["catch"]), true)
	world.add_entity(&"fish.one", &"item", "fish", PackedStringArray(["fish"]), true)
	world.add_entity(&"fish.two", &"item", "fish", PackedStringArray(["fish"]), true)
	world.add_entity(&"fish.three", &"item", "fish", PackedStringArray(["fish"]), true)
	world.add_entity(&"dock.bollard_north", &"object", "north bollard", PackedStringArray(["bollard"]), true)
	world.add_entity(&"harbor.north_steps", &"place", "north steps", PackedStringArray(["steps"]), true)
	host.inventory.set_owner(&"net.mended", &"line_fisher")
	host.inventory.set_owner(&"catch.day", &"storm_watcher")
	runtime.roles.assign(&"harbor_factor", &"net_mender")
	opened["harness"] = harness
	return opened


func offer(runtime: WyrdRuntime, source: StringName, key: String, tier: StringName = &"") -> bool:
	return runtime.generator.offer(source, key, tier)


func run(runtime: WyrdRuntime, minutes: int) -> void:
	runtime.tick(minutes)


func stew_tier(runtime: WyrdRuntime) -> String:
	var value: Variant = runtime.facts.get(&"harbor.stew_tier")
	if value == null:
		return "low"
	return String(value)
