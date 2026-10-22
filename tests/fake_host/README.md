# Fake host

Scripted implementations of the five adapter base classes. Each returns values a test configured. `WyrdFakeHost` registers them by the base script's path. `register_into(runtime)` copies that map onto a runtime.

`test_fake_host.gd` is the GUT test that the harness is wired. The other scripts are the adapters, not tests.

`WyrdFakeLocalServer` is a loopback HTTP/1.1 server. The reference provider's real `HTTPRequest` talks to it in tests. `start()` listens on `127.0.0.1` and returns the port. Each accepted request is recorded, and a FIFO of replies decides the answer: a normal body, silence (so the client times out), a close, or a 302 to another port. An empty queue answers 200 with a chat completion whose content is `{"text": "<auto_text>"}`. It is not a test file.
