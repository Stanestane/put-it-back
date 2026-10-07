extends Node
signal shown
signal closed
const TEST_UNIT = "ca-app-pub-3940256099942544/1033173712"
const AdAttempt = preload("res://scripts/telemetry/ad_attempt.gd")
var attempt
var settings: Resource
var ad
var loader
var consent_form
var initialized: bool = false
var allowed: bool = false
var loading: bool = false
var presenting: bool = false
var generation: int = 0
var loaded_at: int = 0
var retry_at: int = 0
var retry_seconds: int = 15

func configure(config: Resource) -> void:
	settings = config
	# Google's sample app/unit IDs never serve live inventory. UMP messages must
	# be configured against the publisher's own app before enabling live ads.
	if settings.test_ads:
		allowed = true
		_initialize()
	else:
		var parameters = ConsentRequestParameters.new()
		UserMessagingPlatform.consent_information.update(parameters, _consent_updated, _consent_failed)

func _consent_updated() -> void:
	_refresh_permission()
	if UserMessagingPlatform.consent_information.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED:
		UserMessagingPlatform.load_consent_form(func(form): consent_form = form, _consent_failed)
	elif allowed:
		_initialize()

func _refresh_permission() -> void:
	allowed = UserMessagingPlatform.consent_information.get_consent_status() in [ConsentInformation.ConsentStatus.NOT_REQUIRED, ConsentInformation.ConsentStatus.OBTAINED]

func _consent_failed(_error) -> void:
	# Retry consent next launch; never block gameplay or infer consent on error.
	allowed = false
	consent_form = null

func consent_pending() -> bool:
	return consent_form != null

func show_consent() -> void:
	if consent_form == null:
		closed.emit()
		return
	presenting = true
	consent_form.show(_form_closed)

func privacy_required() -> bool:
	return not settings.test_ads and UserMessagingPlatform.consent_information.get_privacy_options_requirement_status() == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED

func show_privacy() -> void:
	presenting = true
	_discard()
	UserMessagingPlatform.show_privacy_options_form(_form_closed)

func _form_closed(error) -> void:
	if not presenting: return
	presenting = false
	consent_form = null
	_refresh_permission()
	if error != null: allowed = false
	if allowed: _initialize()
	closed.emit()

func _initialize() -> void:
	if initialized:
		_preload()
		return
	var configuration = RequestConfiguration.new()
	configuration.max_ad_content_rating = RequestConfiguration.MAX_AD_CONTENT_RATING_G
	MobileAds.set_request_configuration(configuration)
	var listener = OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status):
		initialized = true
		_preload()
	MobileAds.initialize(listener)

func _process(_dt: float) -> void:
	if presenting: return
	if ad != null and Time.get_ticks_msec() - loaded_at >= 55 * 60 * 1000: _discard()
	if initialized and allowed and not loading and ad == null and Time.get_ticks_msec() >= retry_at: _preload()

func _preload() -> void:
	if not allowed or not initialized or loading or ad != null or presenting: return
	loading = true
	generation += 1
	var token = generation
	attempt = AdAttempt.new(get_node("/root/Telemetry"), settings.test_ads)
	var load_attempt = attempt
	load_attempt.event("ad_requested")
	loader = InterstitialAdLoader.new()
	var callback = InterstitialAdLoadCallback.new()
	callback.on_ad_loaded = func(value):
		if token != generation or not allowed:
			value.destroy()
			return
		loading = false
		ad = value
		load_attempt.event("ad_loaded")
		ad.on_ad_paid = func(payment): load_attempt.paid(payment.value_micros, payment.currency_code, payment.precision)
		loaded_at = Time.get_ticks_msec()
		retry_seconds = 15
	callback.on_ad_failed_to_load = func(_error):
		if token != generation: return
		load_attempt.event("ad_failed", {"error_category":AdAttempt.error_category(_error)})
		loading = false
		_retry_later()
	loader.load(TEST_UNIT if settings.test_ads else settings.production_interstitial_id, AdRequest.new(), callback)

func available() -> bool:
	return allowed and ad != null and not presenting and Time.get_ticks_msec() - loaded_at < 55 * 60 * 1000

func show_ad() -> void:
	if not available():
		closed.emit()
		return
	presenting = true
	var token = generation
	var callback = FullScreenContentCallback.new()
	var show_attempt = attempt
	callback.on_ad_impression = func(): show_attempt.event("ad_impression")
	callback.on_ad_showed_full_screen_content = func():
		if token == generation and presenting: shown.emit()
	callback.on_ad_dismissed_full_screen_content = func(): _ad_closed(token, false)
	callback.on_ad_failed_to_show_full_screen_content = func(_error):
		if token != generation: return
		show_attempt.event("ad_failed", {"error_category":AdAttempt.error_category(_error)})
		_ad_closed(token, true)
	ad.full_screen_content_callback = callback
	ad.show()

func _ad_closed(token: int, failed: bool) -> void:
	if token != generation or not presenting: return
	if not failed: attempt.event("ad_closed")
	presenting = false
	_discard()
	if failed: _retry_later()
	closed.emit()

func _retry_later() -> void:
	retry_at = Time.get_ticks_msec() + retry_seconds * 1000
	retry_seconds = mini(120, retry_seconds * 2)

func _discard() -> void:
	generation += 1
	loading = false
	if ad != null:
		ad.destroy()
		ad = null

func _exit_tree() -> void:
	_discard()
