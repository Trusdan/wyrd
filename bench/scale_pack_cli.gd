extends SceneTree

## Writes one scale pack and prints its hash. The directory is not committed.


func _init() -> void:
	var profile_name := "full"
	var out_dir := ""
	var check := false
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var arg := str(args[index])
		if arg == "--profile" and index + 1 < args.size():
			profile_name = str(args[index + 1])
			index += 2
		elif arg == "--out" and index + 1 < args.size():
			out_dir = str(args[index + 1])
			index += 2
		elif arg == "--check":
			check = true
			index += 1
		else:
			push_error("scale pack: unknown argument %s" % arg)
			quit(1)
			return
	if out_dir.is_empty():
		push_error("scale pack: --out is required")
		quit(1)
		return
	var digest := WyrdScalePack.write(out_dir, profile_name)
	if digest.is_empty():
		quit(1)
		return
	WyrdScalePack.write_rumors(out_dir, profile_name)
	WyrdScalePack.write_templates(out_dir, profile_name)
	print("hash=%s" % digest)
	print("dir=%s" % out_dir)
	print("profile=%s" % profile_name)
	print("rumors=%s" % WyrdScalePack.rumors_root(out_dir))
	print("templates=%s" % WyrdScalePack.templates_root(out_dir))
	if not check:
		quit(0)
		return
	var result := WyrdCli.execute(PackedStringArray(["check", "--strict", out_dir]))
	if int(result["exit_code"]) != 0:
		push_error(str(result["output"]))
		quit(1)
		return
	var rumors := WyrdCli.execute(PackedStringArray([
		"check", "--strict", WyrdScalePack.rumors_root(out_dir),
	]))
	if int(rumors["exit_code"]) != 0:
		push_error(str(rumors["output"]))
		quit(1)
		return
	var templates := WyrdCli.execute(PackedStringArray([
		"check", "--strict", "--pressure-tiers", "low,mid,high,dire",
		WyrdScalePack.templates_root(out_dir),
	]))
	if int(templates["exit_code"]) != 0:
		push_error(str(templates["output"]))
		quit(1)
		return
	print("strict=ok")
	quit(0)
