class_name SunsetPalette
extends RefCounted
## Sunset Glow art direction: each room is a different time of day.
## Purely cosmetic. Later this moves into data/themes/*.tres per world.

const SPIKE_DARK_SHADE := 0.16

static var rooms: Array[Dictionary] = [
	{
		"name": "Dusk",
		"sky": [Color("#FF8A5B"), Color("#FF5E9C"), Color("#7B5CFF")],
		"sun": Color("#FFE3A3"),
		"spike": Color("#2B1B5C"),
	},
	{
		"name": "Dawn",
		"sky": [Color("#FFC94D"), Color("#FF8A5B"), Color("#FF5E9C")],
		"sun": Color("#FFF1C9"),
		"spike": Color("#4A1D4F"),
	},
	{
		"name": "Noon",
		"sky": [Color("#2EC4F1"), Color("#7FD8F5"), Color("#FFE3A3")],
		"sun": Color("#FFFFFF"),
		"spike": Color("#1D3B6B"),
	},
	{
		"name": "Golden Hour",
		"sky": [Color("#3FD9A3"), Color("#2EC4F1"), Color("#7B5CFF")],
		"sun": Color("#FFE3A3"),
		"spike": Color("#1B2A4F"),
	},
	{
		"name": "Twilight",
		"sky": [Color("#7B5CFF"), Color("#3B2A8C"), Color("#1B1240")],
		"sun": Color("#FFD0E8"),
		"spike": Color("#0B0620"),
	},
]

static var bird := {
	"body": Color("#FF5E7E"),
	"belly": Color("#FFD0D9"),
	"wing": Color("#D83A63"),
	"beak": Color("#FFB52E"),
	"beak_dark": Color("#E58F0C"),
	"blush": Color("#FFB0C0"),
	"eye": Color("#1E1B2E"),
}

static var ui := {
	"panel": Color("#2B1B5C"),
	"text": Color("#FFFFFF"),
	"accent": Color("#FFC21A"),
}


static func for_room(room_index: int) -> Dictionary:
	return rooms[room_index % rooms.size()]
