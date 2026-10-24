extends SceneTree

## Converts Godot doctool XML into docs/api. Not a GUT test.


const _CLI_DIR := "addons/wyrd/cli/"
const _PLUGIN_SCRIPT := "addons/wyrd/plugin.gd"
const _FACADE_SCRIPT := "addons/wyrd/runtime/wyrd.gd"
const _FACADE_NAME := "Wyrd"

var _class_info: Dictionary = {}
var _member_info: Dictionary = {}
var _in_member := false
var _capture := ""
var _buf := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var in_dir := ""
	var out_res := ""
	var index := 0
	while index < args.size():
		if args[index] == "--in" and index + 1 < args.size():
			index += 1
			in_dir = str(args[index])
		elif args[index] == "--out" and index + 1 < args.size():
			index += 1
			out_res = str(args[index])
		index += 1
	if in_dir.is_empty() or out_res.is_empty():
		printerr("usage: api_docs.gd -- --in <doctool-dir> --out <res://dir>")
		quit(1)
		return
	var cli_names := _cli_names()
	var pages: Array[Dictionary] = []
	var skipped := {"cli": [], "plugin": [], "inner": [], "private": []}
	var paths := _xml_paths(in_dir)
	if paths.is_empty():
		printerr("doctool directory has no XML files.")
		quit(1)
		return
	for path in paths:
		var parsed := _parse_file(path)
		if not bool(parsed["ok"]):
			printerr("XML parse failed for %s." % path.get_file())
			quit(1)
			return
		var raw_name := str(parsed["raw"])
		var decision := _classify(raw_name, cli_names)
		if str(decision["bucket"]) == "path":
			printerr("Path-named class is not the facade: %s." % decision["name"])
			quit(1)
			return
		if not bool(decision["keep"]):
			(skipped[str(decision["bucket"])] as Array).append(str(decision["name"]))
			continue
		var info: Dictionary = parsed["info"]
		info["name"] = str(decision["name"])
		info["headings"] = _headings(info)
		pages.append(info)
	var by_name := {}
	for info in pages:
		by_name[str(info["name"])] = info
	var stable: Array[Dictionary] = []
	var experimental: Array[Dictionary] = []
	for info in pages:
		if info["experimental"] == null:
			stable.append(info)
		else:
			experimental.append(info)
	stable.sort_custom(_by_name)
	experimental.sort_custom(_by_name)
	_clear_markdown(out_res)
	for info in pages:
		var page := _page(info, by_name)
		var file := FileAccess.open("%s/%s.md" % [out_res, str(info["name"])], FileAccess.WRITE)
		if file == null:
			printerr("Could not write %s.md." % str(info["name"]))
			quit(1)
			return
		file.store_string(page)
		file.close()
	var index_file := FileAccess.open("%s/index.md" % out_res, FileAccess.WRITE)
	if index_file == null:
		printerr("Could not write index.md.")
		quit(1)
		return
	index_file.store_string(_index(stable, experimental, by_name))
	index_file.close()
	print("Wrote %d API pages (%d stable, %d experimental)." % [pages.size(), stable.size(), experimental.size()])
	_print_skipped("CLI", skipped["cli"])
	_print_skipped("plugin", skipped["plugin"])
	_print_skipped("inner", skipped["inner"])
	_print_skipped("private", skipped["private"])
	quit(0)


func _by_name(left: Dictionary, right: Dictionary) -> bool:
	return str(left["name"]) < str(right["name"])


func _print_skipped(label: String, names: Array) -> void:
	names.sort()
	if names.is_empty():
		print("Skipped %s: (none)" % label)
	else:
		print("Skipped %s: %s" % [label, ", ".join(names)])


func _xml_paths(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".xml"):
			out.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _gd_files(root: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var path := root.path_join(entry)
			if dir.current_is_dir():
				out.append_array(_gd_files(path))
			elif entry.ends_with(".gd"):
				out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _cli_names() -> Dictionary:
	var found := {}
	var pattern := RegEx.new()
	if pattern.compile("(?m)^class_name\\s+(\\w+)") != OK:
		return found
	for path in _gd_files("res://addons/wyrd/cli"):
		var text := FileAccess.get_file_as_string(path)
		for found_match in pattern.search_all(text):
			found[found_match.get_string(1)] = true
	return found


func _script_of(raw_name: String) -> String:
	var text := raw_name
	if text.begins_with("\"") and text.ends_with("\"") and text.length() >= 2:
		text = text.substr(1, text.length() - 2)
	return text


func _path_named(raw_name: String) -> bool:
	var text := _script_of(raw_name)
	return text.ends_with(".gd") or text.contains("/")


func _classify(raw_name: String, cli_names: Dictionary) -> Dictionary:
	var script := _script_of(raw_name)
	if _path_named(raw_name):
		if script.begins_with(_CLI_DIR):
			return {"keep": false, "bucket": "cli", "name": script}
		if script == _PLUGIN_SCRIPT:
			return {"keep": false, "bucket": "plugin", "name": script}
		if script == _FACADE_SCRIPT:
			return {"keep": true, "bucket": "", "name": _FACADE_NAME}
		return {"keep": false, "bucket": "path", "name": script}
	if cli_names.has(raw_name):
		return {"keep": false, "bucket": "cli", "name": raw_name}
	if raw_name.contains("."):
		return {"keep": false, "bucket": "inner", "name": raw_name}
	if raw_name.begins_with("_"):
		return {"keep": false, "bucket": "private", "name": raw_name}
	return {"keep": true, "bucket": "", "name": raw_name}


func _parse_file(path: String) -> Dictionary:
	_class_info = {}
	_member_info = {}
	_in_member = false
	_capture = ""
	_buf = ""
	var parser := XMLParser.new()
	if parser.open(path) != OK:
		return {"ok": false}
	while true:
		var err := parser.read()
		if err == ERR_FILE_EOF:
			break
		if err != OK:
			return {"ok": false}
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				_on_start(parser)
			XMLParser.NODE_ELEMENT_END:
				_on_end(parser.get_node_name())
			XMLParser.NODE_TEXT:
				if not _capture.is_empty():
					_buf += parser.get_node_data()
	if _class_info.is_empty():
		return {"ok": false}
	return {"ok": true, "raw": str(_class_info["raw"]), "info": _class_info}


func _attrs(parser: XMLParser) -> Dictionary:
	var out := {}
	for index in parser.get_attribute_count():
		out[parser.get_attribute_name(index)] = parser.get_attribute_value(index)
	return out


func _exp(attrs: Dictionary) -> Variant:
	if not attrs.has("experimental"):
		return null
	return str(attrs["experimental"])


func _on_start(parser: XMLParser) -> void:
	var node := parser.get_node_name()
	var attrs := _attrs(parser)
	var empty := parser.is_empty()
	if node == "class":
		_class_info = {
			"raw": str(attrs.get("name", "")),
			"inherits": str(attrs.get("inherits", "")),
			"experimental": _exp(attrs),
			"brief": "",
			"description": "",
			"properties": [],
			"methods": [],
			"signals": [],
			"constants": [],
		}
	elif node == "brief_description":
		_capture = "brief"
		_buf = ""
	elif node == "description":
		_capture = "desc"
		_buf = ""
	elif node == "method" or node == "signal" or node == "member" or node == "constant":
		_begin_member(node, attrs)
		if node == "member" or node == "constant":
			_capture = "body"
			_buf = ""
	elif node == "param":
		_add_param(attrs)
	elif node == "return":
		if not _member_info.is_empty():
			_member_info["return"] = str(attrs.get("type", "void"))
	if empty:
		_on_end(node)


func _on_end(node: String) -> void:
	if node == "brief_description":
		_class_info["brief"] = _clean_text(_buf)
		_capture = ""
		_buf = ""
	elif node == "description":
		var text := _clean_text(_buf)
		if _in_member:
			_member_info["description"] = text
		else:
			_class_info["description"] = text
		_capture = ""
		_buf = ""
	elif node == "method" or node == "signal" or node == "member" or node == "constant":
		if _capture == "body":
			var body := _clean_text(_buf)
			if not body.is_empty():
				_member_info["description"] = body
		_finish_member(node)
		_capture = ""
		_buf = ""
		_in_member = false
		_member_info = {}


func _begin_member(node: String, attrs: Dictionary) -> void:
	_in_member = true
	_member_info = {
		"kind": node,
		"name": str(attrs.get("name", "")),
		"experimental": _exp(attrs),
		"description": "",
		"qualifiers": str(attrs.get("qualifiers", "")),
		"return": "void",
		"params": [],
		"type": str(attrs.get("type", "")),
		"enum_name": str(attrs.get("enum", "")),
		"has_default": attrs.has("default"),
		"default": str(attrs.get("default", "")),
		"value": str(attrs.get("value", "")),
	}


func _add_param(attrs: Dictionary) -> void:
	if _member_info.is_empty():
		return
	(_member_info["params"] as Array).append({
		"name": str(attrs.get("name", "")),
		"type": str(attrs.get("type", "")),
		"has_default": attrs.has("default"),
		"default": str(attrs.get("default", "")),
	})


func _finish_member(node: String) -> void:
	var member_name := str(_member_info.get("name", ""))
	if member_name.is_empty() or member_name.begins_with("_") or member_name.begins_with("@"):
		return
	var stored: Dictionary = _member_info.duplicate(true)
	if node == "method":
		(_class_info["methods"] as Array).append(stored)
	elif node == "signal":
		(_class_info["signals"] as Array).append(stored)
	elif node == "member":
		(_class_info["properties"] as Array).append(stored)
	elif node == "constant":
		(_class_info["constants"] as Array).append(stored)


func _headings(info: Dictionary) -> Dictionary:
	var headings := {}
	for key in ["properties", "methods", "signals", "constants"]:
		for member in info[key]:
			headings[str(member["name"])] = true
	return headings


func _clear_markdown(out_res: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_res))
	var dir := DirAccess.open(out_res)
	if dir == null:
		return
	var names: PackedStringArray = PackedStringArray()
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".md"):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	var index := 0
	while index < names.size():
		dir.remove(names[index])
		index += 1


func _page(info: Dictionary, pages: Dictionary) -> String:
	var lines: Array[String] = []
	var page_name := str(info["name"])
	lines.append("# %s" % page_name)
	lines.append("Generated by tools/gen_api_docs.sh from the ## doc comments. Do not edit by hand.")
	lines.append("")
	lines.append(_badge(info["experimental"], null))
	lines.append("")
	lines.append("Inherits: `%s`" % str(info["inherits"]))
	lines.append("")
	var brief := _markdown(str(info["brief"]), page_name, pages)
	var description := _markdown(str(info["description"]), page_name, pages)
	if not brief.is_empty():
		lines.append(brief)
		lines.append("")
	if not description.is_empty() and description != brief:
		lines.append(description)
		lines.append("")
	_section(lines, "Properties", info["properties"], info, pages)
	_section(lines, "Methods", info["methods"], info, pages)
	_section(lines, "Signals", info["signals"], info, pages)
	_section(lines, "Constants", info["constants"], info, pages)
	return _finish(lines)


func _section(lines: Array[String], title: String, members: Array, info: Dictionary, pages: Dictionary) -> void:
	if members.is_empty():
		return
	lines.append("## %s" % title)
	lines.append("")
	var page_name := str(info["name"])
	for member in members:
		lines.append("### `%s`" % str(member["name"]))
		lines.append("")
		lines.append(_badge(info["experimental"], member["experimental"]))
		lines.append("")
		lines.append("```gdscript")
		lines.append(_signature(member))
		lines.append("```")
		var body := _markdown(str(member["description"]), page_name, pages)
		if not body.is_empty():
			lines.append("")
			lines.append(body)
		lines.append("")


func _index(stable: Array[Dictionary], experimental: Array[Dictionary], pages: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Generated by tools/gen_api_docs.sh from the ## doc comments. Do not edit by hand.")
	lines.append("")
	lines.append("## Stable")
	lines.append("")
	lines.append("| Class | Status | Summary |")
	lines.append("| --- | --- | --- |")
	for info in stable:
		lines.append(_row(info, "Stable", pages))
	lines.append("")
	lines.append("## Experimental")
	lines.append("")
	lines.append("| Class | Status | Summary |")
	lines.append("| --- | --- | --- |")
	for info in experimental:
		lines.append(_row(info, "Experimental", pages))
	return _finish(lines)


func _row(info: Dictionary, status: String, pages: Dictionary) -> String:
	var summary := str(info["brief"]).strip_edges()
	if summary.is_empty():
		summary = str(info["description"])
	summary = _markdown(summary, str(info["name"]), pages)
	summary = summary.replace("](#", "](%s.md#" % str(info["name"]))
	var flat: PackedStringArray = PackedStringArray()
	for part in summary.split(" ", false):
		if not part.is_empty():
			flat.append(part)
	summary = " ".join(flat).replace("|", "\\|")
	return "| [%s](%s.md) | %s | %s |" % [str(info["name"]), str(info["name"]), status, summary]


func _badge(class_exp: Variant, member_exp: Variant) -> String:
	var experimental := false
	var reason := ""
	if class_exp != null:
		experimental = true
		reason = str(class_exp).strip_edges()
	if member_exp != null:
		experimental = true
		if reason.is_empty():
			reason = str(member_exp).strip_edges()
	if not experimental:
		return "**Stable**"
	if reason.is_empty():
		return "**Experimental**"
	return "**Experimental**: %s" % reason


func _signature(member: Dictionary) -> String:
	var kind := str(member["kind"])
	if kind == "method":
		var prefix := "func"
		var quals := str(member["qualifiers"])
		if quals.contains("static"):
			prefix = "static func"
		var args := _args(member)
		if quals.contains("vararg"):
			args = "..." if args.is_empty() else args + ", ..."
		return "%s %s(%s) -> %s" % [prefix, str(member["name"]), args, str(member["return"])]
	if kind == "signal":
		return "signal %s(%s)" % [str(member["name"]), _args(member)]
	if kind == "member":
		var line := "var %s: %s" % [str(member["name"]), str(member["type"])]
		if bool(member["has_default"]):
			line += " = %s" % str(member["default"])
		if not str(member["enum_name"]).is_empty():
			line += " # enum %s" % str(member["enum_name"])
		return line
	var constant := "const %s = %s" % [str(member["name"]), str(member["value"])]
	if not str(member["enum_name"]).is_empty():
		constant += " # enum %s" % str(member["enum_name"])
	return constant


func _args(member: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for param in member["params"]:
		var piece := "%s: %s" % [str(param["name"]), str(param["type"])]
		if bool(param["has_default"]):
			piece += " = %s" % str(param["default"])
		parts.append(piece)
	return ", ".join(parts)


func _markdown(text: String, current: String, pages: Dictionary) -> String:
	var cleaned := _clean_text(text)
	if cleaned.is_empty():
		return ""
	return _convert(cleaned, current, pages).strip_edges()


func _clean_text(raw: String) -> String:
	var kept: PackedStringArray = PackedStringArray()
	for line in raw.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
		kept.append(line.strip_edges())
	while kept.size() > 0 and kept[0].is_empty():
		kept.remove_at(0)
	while kept.size() > 0 and kept[kept.size() - 1].is_empty():
		kept.remove_at(kept.size() - 1)
	return "\n".join(kept)


func _convert(text: String, current: String, pages: Dictionary) -> String:
	var out := ""
	var index := 0
	while index < text.length():
		if text.unicode_at(index) != 91:
			out += text.substr(index, 1)
			index += 1
			continue
		var hit := _tag_at(text, index, current, pages)
		if not bool(hit.get("ok", false)):
			out += "["
			index += 1
			continue
		out += str(hit["text"])
		index = int(hit["next"])
	return out


func _tag_at(text: String, index: int, current: String, pages: Dictionary) -> Dictionary:
	if text.substr(index, 11) == "[codeblock]":
		return _literal_block(text, index, "[codeblock]", "[/codeblock]")
	if text.substr(index, 6) == "[code]":
		return _literal_inline(text, index, "[code]", "[/code]")
	if text.substr(index, 3) == "[b]":
		return _wrap(text, index, "[b]", "[/b]", "**", "**", current, pages)
	if text.substr(index, 3) == "[i]":
		return _wrap(text, index, "[i]", "[/i]", "*", "*", current, pages)
	if text.substr(index, 6) == "[br /]":
		return {"ok": true, "text": "\n", "next": index + 6}
	if text.substr(index, 5) == "[br/]":
		return {"ok": true, "text": "\n", "next": index + 5}
	if text.substr(index, 4) == "[br]":
		return {"ok": true, "text": "\n", "next": index + 4}
	for tag in ["method", "member", "signal", "constant", "param"]:
		var open := "[%s " % tag
		if text.substr(index, open.length()) == open:
			return _ref(text, index, open, current, pages)
	return {"ok": false}


func _literal_inline(text: String, index: int, open: String, close: String) -> Dictionary:
	var end := text.find(close, index + open.length())
	if end < 0:
		return {"ok": false}
	var inner := text.substr(index + open.length(), end - (index + open.length()))
	return {"ok": true, "text": "`%s`" % inner, "next": end + close.length()}


func _literal_block(text: String, index: int, open: String, close: String) -> Dictionary:
	var end := text.find(close, index + open.length())
	if end < 0:
		return {"ok": false}
	var inner := text.substr(index + open.length(), end - (index + open.length())).strip_edges()
	return {"ok": true, "text": "\n```\n%s\n```\n" % inner, "next": end + close.length()}


func _wrap(text: String, index: int, open: String, close: String, left: String, right: String, current: String, pages: Dictionary) -> Dictionary:
	var end := _match_close(text, index + open.length(), open, close)
	if end < 0:
		return {"ok": false}
	var inner := text.substr(index + open.length(), end - (index + open.length()))
	return {
		"ok": true,
		"text": left + _convert(inner, current, pages) + right,
		"next": end + close.length(),
	}


func _match_close(text: String, start: int, open: String, close: String) -> int:
	var depth := 1
	var index := start
	while index < text.length():
		if text.substr(index, open.length()) == open:
			depth += 1
			index += open.length()
			continue
		if text.substr(index, close.length()) == close:
			depth -= 1
			if depth == 0:
				return index
			index += close.length()
			continue
		index += 1
	return -1


func _ref(text: String, index: int, open: String, current: String, pages: Dictionary) -> Dictionary:
	var end := text.find("]", index + open.length())
	if end < 0:
		return {"ok": false}
	var target := text.substr(index + open.length(), end - (index + open.length())).strip_edges()
	return {"ok": true, "text": _link(target, current, pages), "next": end + 1}


func _link(target: String, current: String, pages: Dictionary) -> String:
	var page := current
	var member := target
	var dot := target.find(".")
	if dot > 0:
		page = target.substr(0, dot)
		member = target.substr(dot + 1)
	if not pages.has(page):
		return "`%s`" % target
	var headings: Dictionary = pages[page]["headings"]
	if not headings.has(member):
		return "`%s`" % target
	var anchor := member.to_lower()
	if page == current:
		return "[`%s`](#%s)" % [target, anchor]
	return "[`%s`](%s.md#%s)" % [target, page, anchor]


func _finish(lines: Array) -> String:
	var out: PackedStringArray = PackedStringArray()
	for line in lines:
		for part in str(line).replace("\r", "").split("\n"):
			out.append(part.rstrip(" \t"))
	while out.size() > 0 and out[out.size() - 1].is_empty():
		out.remove_at(out.size() - 1)
	return "\n".join(out) + "\n"
