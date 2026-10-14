# Fake host

Scripted implementations of the five adapter base classes. Each returns values a test configured. `WyrdFakeHost` registers them by the base script's path. `register_into(runtime)` copies that map onto a runtime.

`test_fake_host.gd` is the GUT test that the harness is wired. The other scripts are the adapters, not tests.
