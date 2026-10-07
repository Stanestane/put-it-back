extends RefCounted
## Two checksummed snapshots: a torn write leaves the previous generation readable.
const MAX_EVENTS = 512
const MAX_BYTES = 512000
const MAX_AGE = 7 * 86400
var prefix: String
var generation = 0
var enabled = false
var install_id = ""
var first_open_recorded = false
var events: Array = []
var dropped = 0

func _init(path: String) -> void:
	prefix = path
	for slot in 2:
		var file = FileAccess.open(prefix + str(slot) + ".json", FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES * 3: continue
		var envelope = parse(file.get_as_text())
		if not envelope is Dictionary or not envelope.get("data") is String: continue
		if envelope.data.sha256_text() != envelope.get("sha256", ""): continue
		var data = parse(envelope.data)
		if not data is Dictionary or data.get("version") != 1: continue
		if not data.get("events") is Array or not data.get("enabled") is bool: continue
		if not data.get("install_id") is String or not data.get("first_open_recorded") is bool: continue
		if data.get("generation", 0) <= generation: continue
		generation = int(data.generation)
		enabled = data.enabled
		install_id = data.install_id
		first_open_recorded = data.first_open_recorded
		events = data.events if enabled else []
		dropped = int(data.get("dropped", 0))
	prune()

static func parse(value: String) -> Variant:
	var json = JSON.new()
	if json.parse(value) != OK: return null
	return json.data

func prune(now: float = Time.get_unix_time_from_system()) -> void:
	var retained: Array = []
	var bytes = 0
	# Newest events survive overflow. Never alter the contents of retained events.
	for i in range(events.size()-1, -1, -1):
		var event = events[i]
		if not event is Dictionary or not event.get("event_id") is String or not event.get("occurred_at") is String:
			dropped += 1
			continue
		var age = now - Time.get_unix_time_from_datetime_string(event.occurred_at.trim_suffix("Z"))
		var size = JSON.stringify(event).to_utf8_buffer().size()
		if age > MAX_AGE or retained.size() >= MAX_EVENTS or bytes + size > MAX_BYTES:
			dropped += 1
			continue
		bytes += size
		retained.push_front(event)
	events = retained

func save() -> bool:
	prune()
	var next = generation + 1
	var data = JSON.stringify({"version":1, "generation":next, "enabled":enabled,
		"install_id":install_id, "first_open_recorded":first_open_recorded,
		"events":events, "dropped":dropped})
	var file = FileAccess.open(prefix + str(next % 2) + ".json", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"data":data, "sha256":data.sha256_text()}))
	file.flush()
	var success = file.get_error() == OK
	file.close()
	if success: generation = next
	return success

func batch(limit: int = 100) -> Array:
	var result: Array = []
	for event in events:
		if result.size() >= limit: break
		result.append(event)
		if JSON.stringify({"events":result}).to_utf8_buffer().size() >= 250000:
			result.pop_back()
			break
	return result.duplicate(true)

func acknowledge(sent: Array, response: Variant) -> bool:
	# Validate the ENTIRE receipt before mutating. Missing IDs remain queued.
	if not response is Dictionary: return false
	for key in ["accepted", "duplicates", "rejected"]:
		if not response.get(key) is Array: return false
	var ids: Array = sent.map(func(event): return event.event_id)
	var remove: Array = []
	for id in response.accepted + response.duplicates:
		if not id is String or id not in ids or id in remove: return false
		remove.append(id)
	var rejected_count = 0
	for rejection in response.rejected:
		if not rejection is Dictionary: return false
		var index = rejection.get("index", -1)
		if not (index is int or index is float) or index != int(index) or index < 0 or index >= sent.size(): return false
		if rejection.get("code") not in ["invalid_event", "timestamp_out_of_range", "event_id_conflict"]: return false
		if ids[int(index)] in remove: return false
		remove.append(ids[int(index)])
		rejected_count += 1
	if remove.is_empty(): return false
	events = events.filter(func(event): return event.event_id not in remove)
	dropped += rejected_count
	return true
