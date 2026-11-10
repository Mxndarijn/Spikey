extends TestCase
## Premium items on the server: its list matches the shop, and the items a
## player bought come back to the save with every sync.

const MIGRATION := "res://supabase/migrations/20261110160000_paid_items.sql"


## The "kind:id" rows the migrations add to premium_items.
func _server_list() -> Array[String]:
	var out: Array[String] = []
	var sql := FileAccess.get_file_as_string(MIGRATION)
	var rows := RegEx.create_from_string("\\('([a-z]+:[a-z0-9_]+)'\\)")
	for m in rows.search_all(sql):
		out.append(m.get_string(1))
	out.sort()
	return out


func test_the_server_knows_every_premium_item() -> void:
	var shop: Array[String] = []
	for kind in ItemKind.ALL:
		for id in Catalog.ids(kind):
			if Shop.diamond_price(kind, id) > 0:
				shop.append("%s:%s" % [kind, id])
	shop.sort()
	assert_true(not shop.is_empty())
	assert_eq(
		_server_list(),
		shop,
		"premium_items must match Shop.diamond_price(): add a migration for a new premium item"
	)


func test_bought_items_are_granted() -> void:
	var p := Profile.new()
	var paid: Array[String] = ["flyer:bolt", "world:neon", "pets:cat", "broken", "flyer:bolt"]
	assert_true(ProfileSync.grant_paid(p, paid))
	assert_true(p.owns(ItemKind.FLYER, "bolt"))
	assert_true(p.owns(ItemKind.WORLD, "neon"))
	assert_false(p.owned.has("pets"), "an unknown kind is skipped")
	assert_false(ProfileSync.grant_paid(p, paid), "nothing new the second time")


func test_the_answer_carries_the_bought_items() -> void:
	var res := {
		"ok": true,
		"data": {"status": "saved", "revision": 2, "paid": ["flyer:nova", 5]},
	}
	assert_eq(ProfileSync.parse_answer(res).paid, ["flyer:nova"], "strings only")
