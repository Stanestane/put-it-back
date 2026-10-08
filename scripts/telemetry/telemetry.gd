extends Node
## Optional first-party analytics. No network or identity before collection is enabled.
const Store = preload("res://scripts/telemetry/event_store.gd")
const CONFIG = "res://resources/telemetry_config.json"
const ENDPOINT = "https://putitback.vdsolution.com/v1/events/batch"
var store
var http: HTTPRequest
var endpoint = ENDPOINT
var ingestion_key = ""
var environment = "production"
var platform = "windows"
var available = false
var session_id = ""
var sequence = 0
var round_data: Dictionary = {}
var round_session = ""
var foreground_seconds = 0.0
var gameplay_seconds = 0.0
var background_at = -1
var next_flush = 0
var retry_seconds = 5
var batch_limit = 100
var in_flight: Array = []
var suspended = false
var disk_ok = true
var last_status = "disabled"
var collection_epoch = 0
var last_tick = 0

static func uuid() -> String:
	var bytes = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0,8),hex.substr(8,4),hex.substr(12,4),hex.substr(16,4),hex.substr(20,12)]

func _ready() -> void:
	var args = OS.get_cmdline_user_args()
	if Engine.is_editor_hint() or "--self-test" in args or "--gallery" in args or "--telemetry-unit-tests" in args: return
	if OS.has_feature("web") or OS.get_name() not in ["Windows", "Android", "iOS"]: return
	var qa = "--telemetry-test" in args
	if (OS.has_feature("editor") or OS.is_debug_build() or DisplayServer.get_name() == "headless") and not qa: return
	if not FileAccess.file_exists(CONFIG): return
	var config = Store.parse(FileAccess.get_file_as_string(CONFIG))
	if not config is Dictionary: return
	endpoint = str(config.get("endpoint", ENDPOINT))
	ingestion_key = str(config.get("ingestion_key", ""))
	# Pin the destination so build config cannot forward this key to another host.
	if endpoint != ENDPOINT or ingestion_key.length() < 16 or "REPLACE" in ingestion_key: return
	platform = {"Windows":"windows", "Android":"android", "iOS":"ios"}[OS.get_name()]
	environment = "test" if qa else "production"
	store = Store.new("user://telemetry-test-" if qa else "user://telemetry-")
	http = HTTPRequest.new()
	http.timeout = 10.0
	http.body_size_limit = 65536
	http.max_redirects = 0
	http.accept_gzip = false
	add_child(http)
	http.request_completed.connect(_completed)
	available = true
	if store.enabled: _begin_session("launch")

func collecting() -> bool:
	return available and store != null and store.enabled

func set_collection(value: bool) -> void:
	if not available or store.enabled == value: return
	collection_epoch += 1
	store.enabled = value
	suspended = false
	if value:
		_begin_session("launch")
	else:
		http.cancel_request()
		in_flight.clear()
		store.events.clear()
		round_data.clear()
		foreground_seconds = 0.0
		gameplay_seconds = 0.0
		session_id = ""
		last_status = "disabled"
		# Overwrite both snapshots so queued history does not remain in the fallback.
		disk_ok = store.save()
		disk_ok = store.save() and disk_ok

func _begin_session(entry: String) -> void:
	last_tick = Time.get_ticks_msec()
	if store.install_id.is_empty(): store.install_id = uuid()
	session_id = uuid()
	if not store.first_open_recorded:
		store.first_open_recorded = true
		record({"name":"first_open"})
	record({"name":"session_started", "entry_point":entry})
	next_flush = Time.get_ticks_msec() + 20000

func record(payload: Dictionary, original_session: String = "") -> void:
	if not collecting(): return
	sequence += 1
	store.events.append({"event_id":uuid(), "schema_version":1, "install_id":store.install_id,
		"session_id":session_id if original_session.is_empty() else original_session,
		"sequence":sequence, "occurred_at":Time.get_datetime_string_from_system(true) + "Z",
		"build_version":str(ProjectSettings.get_setting("application/config/version", "1.5.0")),
		"platform":platform, "environment":environment, "payload":payload.duplicate(true)})
	disk_ok = store.save()
	last_status = "queued" if disk_ok else "storage unavailable"

func tick(seconds: float, playing_seconds: float, now: int = Time.get_ticks_msec()) -> void:
	if not collecting(): return
	var monotonic_delta = (now - last_tick) / 1000.0
	last_tick = now
	# Use the same clock for both counters. Taking min(frame delta, tick delta)
	# each frame systematically loses time on high-refresh-rate phones.
	var playing_fraction = clampf(playing_seconds / seconds, 0.0, 1.0) if seconds > 0 else 0.0
	_accumulate(monotonic_delta, monotonic_delta * playing_fraction)
	if now >= next_flush: flush()

func _accumulate(seconds: float, playing_seconds: float) -> void:
	# Cap suspension/hitch catch-up; clock changes cannot inflate durations.
	var foreground = clampf(seconds, 0.0, 1.0)
	var playing = clampf(playing_seconds, 0.0, foreground)
	foreground_seconds += foreground
	gameplay_seconds += playing
	if not round_data.is_empty(): round_data.active_seconds = minf(3600, round_data.active_seconds + playing)
	if foreground_seconds >= 30: checkpoint()

func checkpoint() -> void:
	if not collecting() or foreground_seconds <= 0: return
	record({"name":"activity_checkpoint", "foreground_seconds":minf(300,foreground_seconds),
		"gameplay_seconds":minf(gameplay_seconds,foreground_seconds)})
	foreground_seconds = 0.0
	gameplay_seconds = 0.0

func background() -> void:
	if background_at >= 0: return
	background_at = Time.get_ticks_msec()
	checkpoint()
	flush()

func foreground(now: int = Time.get_ticks_msec()) -> void:
	if background_at < 0: return
	if collecting() and now - background_at >= 30 * 60 * 1000:
		_begin_session("resume")
	background_at = -1
	last_tick = Time.get_ticks_msec()

func start_round(level_id: int, practice: bool, faults: int) -> void:
	if not collecting(): return
	finish_round("abandoned")
	round_session = session_id
	round_data = {"round_id":uuid(), "level_id":level_id, "mode":"practice" if practice else "random", "puzzle_revision":"1.5.0"}
	var payload = round_data.duplicate()
	payload.name = "round_started"
	record(payload)
	round_data.merge({"active_seconds":0.0, "actions":0, "incorrect_actions":0, "starting_faults":clampi(faults,0,1000)})

func action(correct: bool) -> void:
	if not collecting() or round_data.is_empty() or round_data.actions >= 10000: return
	round_data.actions += 1
	if not correct: round_data.incorrect_actions += 1

func finish_round(outcome: String) -> void:
	if not collecting() or round_data.is_empty(): return
	var payload = round_data.duplicate()
	payload.name = "round_finished"
	payload.outcome = outcome
	record(payload, round_session)
	round_data.clear()

func flush() -> void:
	if not collecting() or suspended or not in_flight.is_empty(): return
	var now = Time.get_ticks_msec()
	if now < next_flush: return
	next_flush = now + 20000
	store.prune()
	if store.events.is_empty(): return
	# Failed disk writes must never turn into memory-only uploads.
	disk_ok = store.save()
	if not disk_ok: return
	in_flight = store.batch(batch_limit)
	if in_flight.is_empty(): return
	var headers = PackedStringArray(["Content-Type: application/json", "User-Agent: PutItBackTelemetry/1.0", "Authorization: Bearer " + ingestion_key])
	var error = http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify({"events":in_flight}))
	if error != OK:
		in_flight.clear()
		_backoff()

func _backoff(minimum: float = 0) -> void:
	last_status = "retry pending"
	next_flush = Time.get_ticks_msec() + int(maxf(minimum, retry_seconds + randf_range(0, retry_seconds * 0.25)) * 1000)
	retry_seconds = mini(300, retry_seconds * 2)

func _completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if not collecting() or in_flight.is_empty(): return
	var sent = in_flight
	in_flight = []
	if result != HTTPRequest.RESULT_SUCCESS:
		_backoff()
	elif code == 200 and store.acknowledge(sent, Store.parse(body.get_string_from_utf8())):
		disk_ok = store.save()
		retry_seconds = 5
		last_status = "delivered"
		next_flush = Time.get_ticks_msec() + 20000
	elif code == 413:
		if sent.size() > 1: batch_limit = maxi(1, sent.size()/2)
		else:
			store.events = store.events.filter(func(event): return event.event_id != sent[0].event_id)
			store.dropped += 1
			disk_ok = store.save()
		_backoff()
	elif code in [401,403,404,405,415,422]:
		suspended = true
		last_status = "configuration error %d" % code
	elif code == 429:
		var delay = 60.0
		for header in headers:
			if header.to_lower().begins_with("retry-after:"):
				var value = header.split(":",true,1)[1].strip_edges()
				if value.is_valid_float(): delay = maxf(delay, value.to_float())
		_backoff(delay)
	else:
		_backoff()

func _exit_tree() -> void:
	checkpoint()
