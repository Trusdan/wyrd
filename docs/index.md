# Wyrd

Wyrd is a standalone, game-agnostic narrative engine in typed GDScript, shipped as a Godot 4 addon (`addons/wyrd`) in its own repository. It is itself the dialogue manager. A fact store answers what is true right now, a salience director picks the most specific matching content, small scenes hold authored conversations, and quests address roles rather than people. Deeds go into an append-only log. Procedural and AI features can only propose content; the deterministic core validates it, AI only decorates authored lines, and no AI service is connected by default. Wyrd is not a world simulator, a UI, a translation pipeline, or an LLM runtime. The host simulates the world, renders the signals, and plays audio.

## Quick start

Vendor the addon into the host project. `/path/to/host-project` is the directory that will contain `addons/`.

```bash
tools/vendor_wyrd.sh /path/to/host-project
```

The editor plugin does not register an autoload. Add `res://addons/wyrd/runtime/wyrd.gd` as an autoload named `Wyrd`, or construct that node yourself. Then install a config, register an adapter for each base the content needs, load a manifest, and start a game. The calls below are the ones on [Wyrd](api/Wyrd.md). `world_adapter` and the other adapter variables are the host's subclasses.

```gdscript
extends Node

var manifest: WyrdContentManifest

func _ready() -> void:
	var config := WyrdConfig.new()
	Wyrd.configure(config)
	Wyrd.register_adapter(WyrdWorldAdapter, world_adapter)
	Wyrd.register_adapter(WyrdInventoryAdapter, inventory_adapter)
	Wyrd.register_adapter(WyrdSpatialAdapter, spatial_adapter)
	Wyrd.register_adapter(WyrdTimeAdapter, time_adapter)
	Wyrd.register_adapter(WyrdActionAdapter, action_adapter)
	var report: WyrdLoadReport = Wyrd.load_content(manifest)
	if not report.ok:
		return
	Wyrd.start_new_game(1)
	Wyrd.line_ready.connect(_on_line)
	Wyrd.choices_ready.connect(_on_choices)
	Wyrd.dialogue.open_scene("toll.offer_room")
	Wyrd.dialogue.advance()
	Wyrd.dialogue.choose(0)
	# can_save is false while that scene is open.
	if Wyrd.can_save():
		var saved := Wyrd.save_state()
		print(saved)

func _on_line(line: WyrdLineView) -> void:
	print(line)

func _on_choices(_choices: Array) -> void:
	pass
```

`configure` refuses a null config. `load_content` compiles the manifest and returns a [WyrdLoadReport](api/WyrdLoadReport.md); `ok` is false when the compiler reported an error. `start_new_game` clears play state from the seed. `line_ready` carries the line the open scene is showing, and `choices_ready` carries the choices. [Wyrd.dialogue](api/WyrdSceneRunner.md) opens a scene, leaves the current line, and runs a choice. `can_save` is false while a scene is open, and `save_state` then returns an empty dictionary. The step order for a host is [the host checklist](host-checklist.md).

## Docs

- [Language reference](language.md): grammar, built-ins, and effects.
- [Tutorial](tutorial.md): the ferry quest in the playtest.
- [API reference](api/index.md): generated from the doc comments, with Stable and Experimental marks.
- [Adapter guide](adapters.md) and the [host checklist](host-checklist.md).
- [Cookbook](cookbook/index.md): role fallbacks, topics, barks, social and reputation, epilogues, and migration.
- [Design rationale](rationale.md).
- [Stability](stability.md): the stable surface, the save promise, and deprecation.
- [Contributing](CONTRIBUTING.md).
- [AI](ai.md), [save migration](migration.md), [playtest](playtest.md), and [visual playtest](visual-playtest.md).
