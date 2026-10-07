extends RefCounted
## One logical event per SDK callback kind, scoped to an opt-in period.
const Client = preload("res://scripts/telemetry/telemetry.gd")
var id = Client.uuid()
var test_ad: bool
var epoch: int
var active: bool
var emitted: Dictionary = {}
var client

func _init(telemetry, is_test: bool) -> void:
	client = telemetry
	test_ad = is_test
	epoch = client.collection_epoch
	active = client.collecting()

func event(name: String, extra: Dictionary = {}) -> void:
	if not active or not client.collecting() or epoch != client.collection_epoch or emitted.has(name): return
	emitted[name] = true
	var payload = {"name":name, "attempt_id":id, "placement":"between_rounds", "test_ad":test_ad}
	payload.merge(extra)
	client.record(payload)

func paid(value_micros: int, currency: String, precision: int) -> void:
	if value_micros < 0 or value_micros > 1000000000 or precision < 0 or precision > 3: return
	var expression = RegEx.new()
	expression.compile("^[A-Z]{3}$")
	if expression.search(currency) == null: return
	event("ad_revenue", {"value_micros":value_micros, "currency":currency,
		"precision":["unknown","estimated","publisher_provided","precise"][precision]})

static func error_category(error) -> String:
	if error == null: return "unknown"
	if error.domain != "com.google.android.gms.ads": return "unknown"
	return {0:"internal",1:"invalid_request",2:"network",3:"no_fill"}.get(error.code,"unknown")
