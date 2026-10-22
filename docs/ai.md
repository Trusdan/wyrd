# Local AI flavor

The reference provider in `example/ai/` is an example. It is not part of `addons/wyrd`, and it is not vendored into a host. Wyrd's default provider is still the null provider, which answers nothing. Gullhaven opts six lines in (see `example/README.md`). With the toggle off, nothing on screen changes. With it on, the `toll.depart` narrator line is the one on the playtest's routes, so it is the line that can show ` (AI)`.

The provider talks to an OpenAI-compatible server on this machine. It allows `http://127.0.0.1` and `http://localhost` only. Any other host, including a public address or a name that only looks like loopback, is refused before a socket opens. It has no API-key setting and sends no auth header, so it cannot be pointed at a paid service. A model name containing `cloud` is refused as well, because some local servers forward those names to a hosted service.

Redirects are not followed. A 3xx response is an error, and the line falls back to the authored text. Nothing the model returns is edited. Wyrd's validator still checks limits, names, banned terms, spoilers, and an optional classifier. A failure, including a provider error, shows the authored line. Dialogue never waits on the server.

No model file and no server binary are in this repo. CI does not download or run a model. Tests use a fake loopback server.

## Turn it on

Open the Gullhaven playtest and tick **Local AI flavor**. It starts off. On, the status line checks the server and then reads either `Local AI flavor on: <model> at <base>.` or `Local AI flavor: server not reachable at <base>.` The provider stays registered when the server is down, and every line falls back. Off registers the null provider again and cancels open requests.

A speaker label gains ` (AI)` only when the line on screen is validated cached text. With the toggle off that does not happen.

Two environment variables override the defaults when they are set:

| Variable | Default |
|---|---|
| `WYRD_LOCAL_AI_URL` | `http://127.0.0.1:8080` |
| `WYRD_LOCAL_AI_MODEL` | `smollm2-360m-instruct-q4_k_m` |

A URL that is not loopback, or a model name that contains `cloud`, is refused and the provider is not registered.

## Free setup with llama.cpp

A real-model run is a manual check. It is informational only and never part of CI.

[llama.cpp](https://github.com/ggml-org/llama.cpp) is MIT. Its `llama-server` speaks the chat-completions API. Install it with one of:

- Windows: `winget install llama.cpp`
- macOS or Linux: `brew install llama.cpp`
- A release zip from [github.com/ggml-org/llama.cpp/releases](https://github.com/ggml-org/llama.cpp/releases)

Then run:

```bash
llama-server -hf bartowski/SmolLM2-360M-Instruct-GGUF:Q4_K_M --host 127.0.0.1 --port 8080
```

The first run downloads `SmolLM2-360M-Instruct-Q4_K_M.gguf` (271 MB, Apache-2.0) from Hugging Face into the llama.cpp cache. That download is yours. Do not commit the file. `*.gguf` is gitignored.

Always pass `--port 8080`. The current `llama-server` default port is 9931, not 8080 (`--port` in the [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)). `--host 127.0.0.1` keeps the socket on loopback.

Confirm the server is up:

```bash
curl http://127.0.0.1:8080/v1/models
```

SmolLM2-360M-Instruct is English only, so `locales()` is `["en"]`. A 360M model can rephrase a short line and will often invent a name, break the one-line rule, or run past the character cap. The validator rejects those answers and the authored line shows. That is the point of the fallback.

Prompt version is 1. Each kind has one fixed prompt. The request asks for `{"text": "..."}` with a JSON schema, temperature 0.7, and a seed taken from the cache key, so the same packet, model, and locale send the same seed. The HTTP call uses `stream: false` and a 10 second timeout.

## Trace lines

These are printed only when the bound runtime's trace is on. They are not replay inputs. With the toggle off, none of them appears.

| Line | When |
|---|---|
| `wyrd ai_local op=refused id=<n or -> reason=not_loopback\|bad_url\|cloud_model\|no_transport key=<hex or -> path=<path or ->` | a send, a probe, or `set_base_url` stopped before any connection |
| `wyrd ai_local op=error id=<n> reason=timeout\|connect\|redirect\|too_large\|http_<status>\|parse\|schema key=<hex> path=<path or ->` | an HTTP request ended without a usable reply |
| `wyrd ai_local op=probe ok=true\|false reason=<- or reason>` | each probe result |

`ai_provider`, `ai_request`, `ai_result`, `ai_validate`, `ai_cache`, and `ai_cancel` are unchanged. A successful send does not add an `ai_local` line; those rows already cover it.
