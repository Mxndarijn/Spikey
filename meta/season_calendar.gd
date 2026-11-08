class_name SeasonCalendar
extends RefCounted
## Which seasonal rooms are in play on a date. The game passes the result into
## each run (GameSim / Replay `season`); the server checks it against its own
## date before accepting a leaderboard run.


## Seasons.* for a calendar date (month 1-12, day 1-31).
static func for_date(month: int, day: int) -> int:
	if month == 10:
		return Seasons.HALLOWEEN
	if month == 12:
		return Seasons.WINTER
	if month == 1 and day <= 7:
		return Seasons.NEW_YEAR
	if month == 2 and day <= 14:
		return Seasons.VALENTINE
	if month == 3 or month == 4:
		return Seasons.SPRING
	if month == 7 or month == 8:
		return Seasons.SUMMER
	return Seasons.NONE


static func today() -> int:
	var d := Time.get_date_dict_from_system()
	return for_date(int(d.month), int(d.day))


static func display_name(season: int) -> String:
	match season:
		Seasons.HALLOWEEN:
			return "Halloween"
		Seasons.WINTER:
			return "Winter"
		Seasons.VALENTINE:
			return "Valentine's"
		Seasons.SPRING:
			return "Spring"
		Seasons.SUMMER:
			return "Summer"
		Seasons.NEW_YEAR:
			return "New Year"
	return ""
