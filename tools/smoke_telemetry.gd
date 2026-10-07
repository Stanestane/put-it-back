extends SceneTree
## Explicit opt-in QA smoke: real Godot HTTPS, then replay original events for dedupe.
const Attempt = preload("res://scripts/telemetry/ad_attempt.gd")
var receipt: Dictionary = {}
var response_code = 0

func _initialize() -> void:
	_run.call_deferred()

func _response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	response_code = code
	var parsed = preload("res://scripts/telemetry/event_store.gd").parse(body.get_string_from_utf8())
	receipt = parsed if parsed is Dictionary else {}

func wait_upload(client) -> void:
	var deadline = Time.get_ticks_msec() + 20000
	while not client.in_flight.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame

func _run() -> void:
	var client = root.get_node("Telemetry")
	if not client.available or client.environment != "test" or client.collecting():
		push_error("Smoke requires configured --telemetry-test with collection initially off.")
		quit(1)
		return
	client.http.request_completed.connect(_response)
	client.set_collection(true)
	client.start_round(23,true,2)
	client._accumulate(1.0,0.75)
	client.action(true)
	client.action(false)
	client.finish_round("win")
	client.checkpoint()
	var attempt = Attempt.new(client,true)
	for name in ["ad_requested","ad_loaded","ad_impression"]: attempt.event(name)
	attempt.paid(123456,"USD",3)
	attempt.event("ad_closed")
	var failed = Attempt.new(client,true)
	failed.event("ad_requested")
	failed.event("ad_failed",{"error_category":"no_fill"})
	var original: Array = client.store.events.duplicate(true)
	client.next_flush = 0
	client.flush()
	await wait_upload(client)
	var first = receipt.duplicate(true)
	var ok = response_code == 200 and first.get("accepted",[]).size() == original.size() and first.get("rejected",[1]).is_empty() and client.store.events.is_empty()
	if ok:
		# Emulate a lost ACK followed by restart: reload the original persisted events.
		client.store.events = original
		client.store.save()
		client.store = preload("res://scripts/telemetry/event_store.gd").new(client.store.prefix)
		receipt = {}
		client.next_flush = 0
		client.flush()
		await wait_upload(client)
		ok = response_code == 200 and receipt.get("duplicates",[]).size() == original.size() and receipt.get("rejected",[1]).is_empty() and client.store.events.is_empty()
	var evidence = {"passed":ok,"environment":"test","install_id":client.store.install_id,
		"events":original.size(),"http_status":response_code,"first_response":first,"replay_response":receipt,
		"checked_at":Time.get_datetime_string_from_system(true)+"Z"}
	var file = FileAccess.open("res://verification/telemetry-live-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"  "))
	file.close()
	client.set_collection(false)
	print("GODOT HTTPS TELEMETRY SMOKE PASSED" if ok else "GODOT HTTPS TELEMETRY SMOKE FAILED (see verification/telemetry-live-result.json)")
	quit(0 if ok else 1)
