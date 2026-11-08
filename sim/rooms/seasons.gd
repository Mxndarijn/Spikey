class_name Seasons
extends RefCounted
## Seasonal rooms. The season is a run input (stored in the replay), because
## the sim can't read the date: the game passes it in, the server checks it.

const NONE := -1
const HALLOWEEN := 0
const WINTER := 1
const VALENTINE := 2
const SPRING := 3
const SUMMER := 4
const NEW_YEAR := 5
const COUNT := 6
