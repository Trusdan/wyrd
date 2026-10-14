# adapters

Typed adapter base classes a host implements. Unimplemented methods `push_error` and return a typed fallback. The fake host in `tests/fake_host` overrides them. `WyrdTimeAdapter.season` answers a `time.season` resolver.
