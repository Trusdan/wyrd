class_name WyrdFileDef
extends WyrdStmtSpan

## Compiled quests, templates, scenes, roles, storylets, sequences, and documents from one file.
##
## @experimental

var quests: Array[WyrdQuestDef] = []
var templates: Array[WyrdTemplateDef] = []
var scenes: Array[WyrdSceneDef] = []
var roles: Array[WyrdRoleDef] = []
var storylets: Array[WyrdStoryletDef] = []
var sequences: Array[WyrdSequenceDef] = []
var documents: Array[WyrdDocumentDef] = []


## Quests, then templates, in file order. Lint passes that walk quest bodies use this.
func quest_bodies() -> Array[WyrdQuestDef]:
	var rows: Array[WyrdQuestDef] = []
	for quest in quests:
		rows.append(quest)
	for template in templates:
		rows.append(template)
	return rows
