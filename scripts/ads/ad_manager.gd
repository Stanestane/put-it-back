extends Node
## Scheduling is independent of the SDK, allowing deterministic offline tests.
signal break_finished
var settings: Resource
var provider
var rounds: int = 0
var gameplay_seconds: float = 0.0
var busy: bool = false
var _shown: bool = false

func configure(config: Resource, adapter = null) -> void:
	settings = config
	if not settings.enabled: return
	if adapter == null:
		if OS.get_name() != "Android": return
		if not settings.test_ads and not settings.permits_live_ads(str(ProjectSettings.get_setting("admob/general/android/app_id", ""))):
			print("Ads: live configuration incomplete; ads disabled.")
			return
		if not Engine.has_singleton("PoingGodotAdMob"): return
		adapter = load("res://scripts/ads/android_ads.gd").new()
	provider = adapter
	add_child(provider)
	provider.shown.connect(_on_shown)
	provider.closed.connect(_on_closed)
	provider.configure(settings)

func tick_gameplay(seconds: float, practice: bool) -> void:
	if provider != null and not busy and (not practice or settings.show_in_practice):
		gameplay_seconds += maxf(0.0, seconds)

func complete_round(practice: bool) -> void:
	if provider != null and (not practice or settings.show_in_practice): rounds += 1

func between_rounds(practice: bool) -> bool:
	if provider == null or busy: return busy
	if provider.consent_pending():
		busy = true
		provider.show_consent.call_deferred()
		return true
	if practice and not settings.show_in_practice: return false
	if rounds < maxi(1, settings.rounds_between_ads) or gameplay_seconds < maxf(0.0, settings.minimum_gameplay_seconds): return false
	if not provider.available(): return false
	busy = true
	_shown = false
	provider.show_ad.call_deferred()
	return true

func show_menu_consent() -> void:
	if provider != null and not busy and provider.consent_pending():
		busy = true
		provider.show_consent.call_deferred()

func privacy_required() -> bool:
	return provider != null and provider.privacy_required()

func show_privacy() -> void:
	if busy or not privacy_required(): return
	busy = true
	provider.show_privacy.call_deferred()

func _on_shown() -> void:
	if not busy or _shown: return
	_shown = true
	rounds = 0
	gameplay_seconds = 0.0

func _on_closed() -> void:
	if not busy: return
	busy = false
	_shown = false
	break_finished.emit()
