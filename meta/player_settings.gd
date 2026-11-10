class_name PlayerSettings
extends RefCounted
## The Settings sheet: sound, and the switches under Play. Saved with the
## Profile (same flat keys as before, so old saves keep their settings).

## The switches under Settings > Play, in screen order.
enum Switch { HAPTICS, REDUCED_FLASHING, COLOR_BLIND_SPIKES, LARGE_BUTTONS, BOARD_ALERTS }

## Volumes 0..100 and on/off switches.
var music_volume := 80
var sfx_volume := 100
var music_on := true
var sfx_on := true
## A little buzz on flap and crash.
var haptics := true
## No room flash or shake, slow sky fades (RoomView.flash_enabled follows it).
var reduced_flashing := false
## Spikes turn dark with a white edge (RoomView, HazardLayer).
var color_blind_spikes := false
## Pause and other HUD icon buttons grow to 56px (UiKit.large_buttons).
var large_buttons := false
## A notification when someone takes the player's prize spot on the daily
## board (PushService).
var board_alerts := true
## The debug screen's switch: ask for Google's test ads instead of real ones.
var test_ads := false


func is_on(which: Switch) -> bool:
	match which:
		Switch.HAPTICS:
			return haptics
		Switch.REDUCED_FLASHING:
			return reduced_flashing
		Switch.COLOR_BLIND_SPIKES:
			return color_blind_spikes
		Switch.LARGE_BUTTONS:
			return large_buttons
		_:
			return board_alerts


func set_on(which: Switch, on: bool) -> void:
	match which:
		Switch.HAPTICS:
			haptics = on
		Switch.REDUCED_FLASHING:
			reduced_flashing = on
		Switch.COLOR_BLIND_SPIKES:
			color_blind_spikes = on
		Switch.LARGE_BUTTONS:
			large_buttons = on
		Switch.BOARD_ALERTS:
			board_alerts = on


## Adds the settings to a save dictionary.
func write_to(d: Dictionary) -> void:
	d["music_volume"] = music_volume
	d["sfx_volume"] = sfx_volume
	d["music_on"] = music_on
	d["sfx_on"] = sfx_on
	d["haptics"] = haptics
	d["reduced_flashing"] = reduced_flashing
	d["color_blind_spikes"] = color_blind_spikes
	d["large_buttons"] = large_buttons
	d["board_alerts"] = board_alerts
	d["test_ads"] = test_ads


## Reads the settings from a save, keeping the default for anything missing.
func read_from(d: Dictionary) -> void:
	music_volume = clampi(int(d.get("music_volume", music_volume)), 0, 100)
	sfx_volume = clampi(int(d.get("sfx_volume", sfx_volume)), 0, 100)
	music_on = bool(d.get("music_on", music_on))
	sfx_on = bool(d.get("sfx_on", sfx_on))
	haptics = bool(d.get("haptics", haptics))
	reduced_flashing = bool(d.get("reduced_flashing", reduced_flashing))
	color_blind_spikes = bool(d.get("color_blind_spikes", color_blind_spikes))
	large_buttons = bool(d.get("large_buttons", large_buttons))
	board_alerts = bool(d.get("board_alerts", board_alerts))
	test_ads = bool(d.get("test_ads", test_ads))
