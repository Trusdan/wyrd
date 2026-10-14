# scenes

`WyrdSceneRunner` is the facade's `dialogue` object. One conversation is a stack of scene frames.

`line_ready` carries a `WyrdLineView`: `id`, `speaker`, `display_name`, `text`, `tags`, `audio`. Text is interpolated, then passed through `TranslationServer.translate` with the line id. `register_line_audio(line_id, locale)` supplies `audio`, which may be null. The line stays until `advance()`.

`choices_ready` carries `WyrdChoiceView` rows. A false condition hides the choice. `disabled_when` shows it disabled with the quoted reason. `choose(index)` uses the index in that list. A disabled choose logs an error and stays.

`-> scene` pushes a sub-scene and returns. `-> end` finishes the frame. `abort(reason)` runs `on_abort` from the inner frame outward and emits `scene_ended` for the root scene. A bound holder who dies or leaves the role aborts the same way.

`can_save()` is false while any frame is open.
