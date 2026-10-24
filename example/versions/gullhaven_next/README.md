# Gullhaven next

A later version of the Gullhaven `harbor` pack. It reuses the Gullhaven files and replaces only `ferry_toll.wyrd`, which renames stage `pay_toll` to `toll_due` with `was:`.

`tests/migration/test_gullhaven_next.gd` loads a Gullhaven save into `harbor_next.wyrdmanifest.tres`.
