# Reference local AI provider

Example only. This directory is not part of `addons/wyrd` and it is not vendored into a host. A host that wants the same shape copies these files.

Three scripts, none with a `class_name`. Preload them by path.

- `wyrd_local_prompts.gd` builds one fixed prompt per kind (prompt version 1), the JSON request body, and the reply parser. It has no node and no network.
- `wyrd_local_provider.gd` extends `WyrdAIProvider`. It checks the URL and the model name, then asks the transport to send. It has no API-key field and sends no auth header.
- `wyrd_local_transport.gd` extends `Node` and owns one `HTTPRequest` per open call. A `RefCounted` provider cannot own scene-tree nodes, so the host adds the transport to the tree and calls `provider.attach(transport)`.

Register it only when you want local flavor. The default stays the null provider.

```gdscript
var transport = preload("res://example/ai/wyrd_local_transport.gd").new()
add_child(transport)
var provider = preload("res://example/ai/wyrd_local_provider.gd").new()
provider.attach(transport)
provider.bind_trace(runtime)
runtime.register_adapter(WyrdAIProvider, provider)
```

`set_base_url` accepts `http://127.0.0.1` or `http://localhost` and nothing else. Any other host is refused before a connection is opened. Redirects are not followed. The playtest toggle "Local AI flavor" does this registration and starts off.

The free setup, the two environment variables, and the trace lines are in [docs/ai.md](../../docs/ai.md).
