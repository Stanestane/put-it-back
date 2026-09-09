extends RefCounted
const Manager = preload("res://scripts/ads/ad_manager.gd")
const Settings = preload("res://scripts/ads/ad_settings.gd")
class FakeAds extends Node:
	signal shown
	signal closed
	var ready_ad = true
	var pending_consent = false
	var presentations = 0
	func configure(_settings): pass
	func available(): return ready_ad
	func consent_pending(): return pending_consent
	func privacy_required(): return false
	func show_consent(): pending_consent = false
	func show_ad(): presentations += 1
	func show_privacy(): pass

var errors: Array[String] = []
func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func run(game) -> bool:
	var config = Settings.new()
	config.rounds_between_ads = 3
	config.minimum_gameplay_seconds = 10.0
	var fake = FakeAds.new()
	var manager = Manager.new()
	game.add_child(manager)
	manager.break_finished.connect(game._on_ad_break_finished)
	manager.configure(config, fake)
	manager.complete_round(true)
	manager.tick_gameplay(100.0, true)
	check(manager.rounds == 0 and manager.gameplay_seconds == 0, "Practice excluded")
	for i in 3: manager.complete_round(false)
	check(not manager.between_rounds(false), "Time threshold required")
	manager.tick_gameplay(10.0, false)
	fake.ready_ad = false
	check(not manager.between_rounds(false) and manager.rounds == 3, "Offline skips without reset")
	fake.ready_ad = true
	check(manager.between_rounds(false), "Both thresholds allow ad")
	manager.between_rounds(false)
	await game.get_tree().process_frame
	check(fake.presentations == 1, "No duplicate presentation")
	fake.closed.emit() # Failed to show: no shown callback.
	check(manager.rounds == 3 and not manager.busy, "Show failure retains interval")
	check(manager.between_rounds(false), "Retry at next boundary")
	await game.get_tree().process_frame
	fake.shown.emit()
	fake.shown.emit()
	check(manager.rounds == 0 and manager.gameplay_seconds == 0, "Reset on actual show")
	manager.tick_gameplay(50.0, false)
	check(manager.gameplay_seconds == 0, "Ad time not gameplay")
	fake.closed.emit()
	fake.closed.emit()
	check(not manager.busy and not manager.between_rounds(false), "Duplicate close harmless")
	fake.pending_consent = true
	manager.rounds = 1
	check(manager.between_rounds(true), "Required consent can use a safe boundary")
	await game.get_tree().process_frame
	manager.tick_gameplay(30.0, false)
	fake.closed.emit()
	check(manager.rounds == 1 and manager.gameplay_seconds == 0 and not manager.busy, "Consent does not count as an ad or gameplay")
	manager.rounds = 0
	var disabled = Manager.new()
	game.add_child(disabled)
	var off = Settings.new()
	off.enabled = false
	disabled.configure(off)
	check(disabled.provider == null and not disabled.between_rounds(false), "Master switch disables ads")
	disabled.free()
	if OS.get_name() == "Windows":
		var desktop = Manager.new()
		game.add_child(desktop)
		desktop.configure(config)
		check(desktop.provider == null, "Windows never initializes SDK")
		desktop.free()
	check(not config.permits_live_ads("ca-app-pub-3940256099942544~3347511713"), "Test IDs cannot enable live ads")
	config.production_interstitial_id = "ca-app-pub-1234567890123456/1234567890"
	check(not config.permits_live_ads("ca-app-pub-1234567890123456~1234567890"), "Unconfirmed audience blocks live ads")
	config.general_audience_confirmed = true
	check(config.permits_live_ads("ca-app-pub-1234567890123456~1234567890"), "Complete production configuration")
	# Exercise the real game transition, including losing focus behind an ad.
	game.ads = manager
	game.testing = false
	game.practice = false
	game.start_round(1)
	game.finish(false)
	game.finish(false)
	check(manager.rounds == 1, "Count timeout once")
	game.testing = true
	manager.rounds = 3
	manager.gameplay_seconds = 10
	game._advance_after_result()
	await game.get_tree().process_frame
	var before: float = game.remaining
	game._process(2.0)
	check(game.remaining == before and game.state == "ad", "Game frozen during ad")
	fake.shown.emit()
	game._notification(game.NOTIFICATION_APPLICATION_FOCUS_OUT)
	fake.closed.emit()
	game._process(2.0)
	check(game.state == "ad", "Dismissal cannot start background round")
	game._notification(game.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._process(0.1)
	check(game.state == "play" and game.remaining == 5.0, "Resume with full round timer")
	fake.closed.emit()
	check(not game.resume_after_ad, "Late dismissal cannot restart round")
	game.ads = null
	manager.free()
	for error in errors: push_error("Ad test: " + error)
	if errors.is_empty(): print("AD TESTS PASSED")
	return errors.is_empty()
