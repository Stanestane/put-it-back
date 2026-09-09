extends SceneTree
## Parse the Android adapter and its SDK types in a real tree so upstream
## editor mock nodes are attached and cleaned up (check-only cannot do that).
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var script = load("res://scripts/ads/android_ads.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var adapter = script.new()
	adapter.free()
	await process_frame
	print("ANDROID ADAPTER PARSED")
	quit()
