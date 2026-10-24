# Test fixture. Never loaded by the add-on.
extends RefCounted


func sample(label: String = "c") -> void:
	var _keep := label
