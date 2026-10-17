class_name WyrdDocumentDef
extends WyrdStmtSpan

## One compiled periodic document.
##
## @experimental
## Built from a top-level [code]document[/code] block. [member period_minutes]
## and [member delay_minutes] are game minutes. [member fragments] are the
## slant rules, in source order. The first fragment whose condition is true
## supplies [code]slant[/code]. There is no page or read-effect record here.

var id: String = ""
var title: String = ""
var group: String = ""
var period_minutes: int = 0
var delay_minutes: int = 0
var claim_key: String = ""
var fact_key: String = ""
var verb_filter: String = ""
var fragments: Array[Dictionary] = []
