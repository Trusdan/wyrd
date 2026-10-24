# Test fixture. Never loaded by the add-on.
extends RefCounted


func sample(label: int = 1) -> void:
	var _keep := label
