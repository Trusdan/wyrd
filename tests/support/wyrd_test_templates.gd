class_name WyrdTestTemplates
extends RefCounted

## Opens the instance fixture and moves [code]errand[/code] out of [code]quests[/code].
##
## @experimental
## [param install_template] stores that def on [code]content.templates[/code].
## The quest is erased either way, then [method WyrdQuestRunner.reset] and
## [method WyrdRoles.bind_content] run before [method WyrdRuntime.start_new_game].


const MANIFEST := "res://tests/support/m9_instances.wyrdmanifest.tres"


static func open(seed: int, install_template: bool = true) -> Dictionary:
	var runtime := WyrdRuntime.new()
	var host := WyrdFakeHost.new()
	host.register_into(runtime)
	var manifest := load(MANIFEST) as WyrdContentManifest
	var report := runtime.load_content(manifest)
	var content := runtime.content()
	if content != null and content.quests.has("errand"):
		var quest: WyrdQuestDef = content.quests["errand"]
		content.quests.erase("errand")
		if install_template:
			content.templates["errand"] = quest
		runtime.quests.reset()
		runtime.roles.bind_content(content)
	runtime.start_new_game(seed)
	return {"host": host, "manifest": manifest, "report": report, "runtime": runtime}
