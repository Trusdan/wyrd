# Design rationale

## What Wyrd is

Wyrd is a standalone, game-agnostic narrative engine in typed GDScript, shipped as a Godot 4 addon (`addons/wyrd`) in its own MIT-licensed repository. It is itself the dialogue manager.

It is a hybrid of four parts. A fact store answers every "what is true right now" question, and each fact has one declared source: a value Wyrd stores, or a live read from the host through a resolver. A salience-based storylet director picks the most specific matching content. Small explicit branching scenes hold authored conversations. Role casting and quest state machines address roles, not people, and authored fallbacks cover empty, hostile, replaced, or departed holders.

Deeds go into an append-only log with time decay. Wyrd computes relationships, disposition, and reputation from an authored baseline plus the deeds each character knows about.

Procedural and AI features can only propose content, which the deterministic core validates. AI only decorates authored content. It never decides game state, it always has a deterministic fallback, and no AI service is connected by default.

Wyrd is not a world simulator. The host simulates needs, jobs, economy, combat, and the like. Wyrd reads results through adapters and records deeds. It is not a UI: Wyrd emits signals and data, and the host renders. It is not a translation or voice pipeline: stable line ids plug into Godot's translation system, and the host plays audio. It is not an LLM runtime.

## Why it is built this way

The core stays game-agnostic. The engine has no host names, lore, factions, calendar, or rules. Everything that belongs to the host game comes in through content files, configuration Resources, registered functions, and adapters.

A text language (`.wyrd`) is the source of truth because it diffs well, and humans and coding agents can edit and review it in pull requests. Small `.tres` Resources are used only for configuration and manifests, because `.tres` diffs poorly and is awkward for prose.

The compiler is a plain GDScript library with no editor dependency, shared by the CLI and the runtime, so CI and agents run the same compile and link step as the game. Linking happens at load and reports errors with file and line.

The compiled form is plain data: instruction arrays, StringNames, and constants, with no stored lambdas or Callables. It saves, replays, and snapshots cleanly. JSON export is for debugging and golden tests.

Wyrd owns dialogue state instead of sitting on a third-party dialogue plugin, because roles, deeds, and salience would be custom work anyway, and one owner keeps saves and determinism in one place.

Saves and determinism have a defined scope. All engine state serializes to a versioned Dictionary that the host stores in its own save, and a recorded trace replays the same decisions.

The runtime is built for a large open world: indexed lookups, dirty tracking, a fixed-work scheduler, and a split between near-player detail and distant summary simulation.

It is pure typed GDScript. There is no C#, no .NET, and no native extension, so any Godot 4 build can use it.

A marked stable surface uses semantic versioning and a deprecation policy ([stability](stability.md)), so a host that pins a 1.x tag does not break inside 1.x.

The editor screens (graph view, inspector, and console screens) come after 1.0. The two-way editor and the Asset Library come after 1.0 as well. Tools and coding agents can use Wyrd fully through its text files and API without those screens.
