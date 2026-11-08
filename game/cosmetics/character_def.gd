class_name CharacterDef
extends Resource
## One flyer the player can pick. Art only: every flyer uses the same sim
## hitbox, so no flyer plays better than another. Files live in data/flyers/.

@export var id := ""
@export var display_name := ""
@export_multiline var blurb := ""
## Position in the picker and the shop.
@export var order := 0
## Art on a 120 x 120 canvas, facing right.
@export var idle: Texture2D
@export var flap: Texture2D
## Worlds this flyer looks especially good in (shown as a hint).
@export var fits_worlds: PackedStringArray = []
