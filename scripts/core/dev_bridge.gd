extends Node
## Preserve editor MCP tooling while keeping it out of Android exports/tests.
func _ready() -> void:
	if not OS.has_feature("editor") or DisplayServer.get_name() == "headless":
		return
	var runtime_path := "res://addons/godot_mcp/runtime/mcp_runtime.gd"
	if FileAccess.file_exists(runtime_path):
		var runtime = load(runtime_path).new()
		runtime.name = "EditorRuntime"
		add_child(runtime)
