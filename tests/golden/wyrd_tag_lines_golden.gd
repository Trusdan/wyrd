class_name WyrdTagLinesGolden
extends RefCounted

## Gullhaven-named tag-lines golden.
##
## @experimental
## The source is untagged. The notes and tagged text are tag_text's output.


const SOURCE := "res://tests/golden/tag_lines/harbor_ids.wyrd"
const NOTES := "res://tests/golden/tag_lines/harbor_ids.notes"
const TAGGED := "res://tests/golden/tag_lines/harbor_ids.tagged"


static func write_expected() -> int:
	DirAccess.make_dir_recursive_absolute("res://tests/golden/tag_lines")
	var rendered := render()
	var notes_file := FileAccess.open(NOTES, FileAccess.WRITE)
	notes_file.store_string(str(rendered["notes"]))
	var tagged_file := FileAccess.open(TAGGED, FileAccess.WRITE)
	tagged_file.store_string(str(rendered["text"]))
	return 1


static func render() -> Dictionary:
	var raw := FileAccess.get_file_as_string(SOURCE)
	var result: Dictionary = WyrdTagLines.tag_text(raw, SOURCE, "harbor", {})
	var notes: PackedStringArray = result["notes"]
	var notes_text := ""
	if not notes.is_empty():
		notes_text = "\n".join(notes) + "\n"
	return {"notes": notes_text, "text": str(result["text"])}
