class_name RoomSkins
extends RefCounted
## Which rooms draw their hazards in a different look (a seasonal room that
## reuses a year-round hazard). Cosmetic only: the sim never sees these, so a
## skin can be renamed or added without touching gameplay.

## Room id -> skin name the painters and RoomView know.
const SKINS: Dictionary[String, String] = {
	"midnight": "midnight",
	"orchard": "pinecone",
	"pumpkin": "pumpkin",
	"ghostdoors": "ghost",
	"bats": "bat",
	"icicle": "icicle",
	"gifts": "gift",
	"hearts": "heart",
	"cupid": "cupid",
	"eggs": "egg",
	"bees": "bee",
	"beachball": "beachball",
	"crabs": "crab",
	"cave": "bat",
}


## The skin of room `id`, or "" for the usual look.
static func of(id: String) -> String:
	return SKINS.get(id, "")
