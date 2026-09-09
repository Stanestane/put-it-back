extends Resource
## Edit resources/ads_settings.tres in the Inspector. Changes apply on next launch.
@export var enabled: bool = true
@export_range(1, 1000) var rounds_between_ads: int = 10
@export_range(0.0, 3600.0) var minimum_gameplay_seconds: float = 90.0
@export var show_in_practice: bool = false
@export var test_ads: bool = true
@export var production_interstitial_id: String = ""
## Live ads stay disabled until audience classification has been reviewed.
@export var general_audience_confirmed: bool = false

func permits_live_ads(app_id: String) -> bool:
	return general_audience_confirmed and valid_id(app_id, "~") and valid_id(production_interstitial_id, "/")

func valid_id(value: String, separator: String) -> bool:
	var expression = RegEx.new()
	expression.compile("^ca-app-pub-[0-9]{16}" + separator + "[0-9]{10}$")
	return expression.search(value) != null and not value.contains("3940256099942544")
