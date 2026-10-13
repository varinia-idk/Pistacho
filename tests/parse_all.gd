extends SceneTree
const SCRIPTS := ["res://scripts/ui/main.gd", "res://scripts/network/session.gd"]
func _initialize() -> void:
	for path: String in SCRIPTS:
		var script: Script = load(path)
		if script == null or not script.can_instantiate():
			push_error("Cannot compile " + path)
			quit(1)
			return
	print("Scripts loaded: ", SCRIPTS.size())
	quit()
