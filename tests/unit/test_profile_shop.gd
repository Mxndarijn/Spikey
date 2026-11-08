extends TestCase

const TEST_PATH := "user://test_profile.json"


func test_new_profile_owns_only_the_default_trail() -> void:
	var p := Profile.new()
	assert_eq(p.coins, 0)
	assert_false(p.onboarded)
	assert_true(p.owns(Catalog.TRAIL, "world_ribbon"))
	assert_eq(p.equipped_id(Catalog.TRAIL), "world_ribbon")
	assert_eq(p.equipped_id(Catalog.FLYER), "")


func test_cannot_equip_what_you_dont_own() -> void:
	var p := Profile.new()
	assert_false(p.equip(Catalog.FLYER, "ember"))
	p.grant(Catalog.FLYER, "ember")
	assert_true(p.equip(Catalog.FLYER, "ember"))
	assert_eq(p.equipped_id(Catalog.FLYER), "ember")


func test_runs_earn_coins_and_track_best() -> void:
	var p := Profile.new()
	assert_eq(p.record_run(12, 3), 3, "earns the coins collected")
	p.record_run(5, 2)
	assert_eq(p.best_score, 12)
	assert_eq(p.runs, 2)
	assert_eq(p.coins, 5)


func test_save_and_load_round_trip() -> void:
	var p := Profile.new()
	p.coins = 321
	p.onboarded = true
	p.grant(Catalog.WORLD, "ice")
	p.equip(Catalog.WORLD, "ice")
	assert_true(p.save(TEST_PATH))
	var back := Profile.load_or_new(TEST_PATH)
	assert_eq(back.coins, 321)
	assert_true(back.onboarded)
	assert_eq(back.equipped_id(Catalog.WORLD), "ice")
	DirAccess.remove_absolute(TEST_PATH)


func test_bad_save_data_is_ignored() -> void:
	var p := Profile.from_dict({"coins": -50, "owned": {"flyer": [3, "dash"]}, "equipped": "x"})
	assert_eq(p.coins, 0)
	assert_true(p.owns(Catalog.FLYER, "dash"))
	assert_eq(Profile.load_or_new("user://does_not_exist.json").coins, 0)


func test_buying() -> void:
	var p := Profile.new()
	assert_eq(Shop.buy(p, Catalog.FLYER, "ember"), Shop.Result.NOT_ENOUGH_COINS)
	p.coins = Shop.price(Catalog.FLYER, "ember") + 5
	assert_eq(Shop.buy(p, Catalog.FLYER, "ember"), Shop.Result.OK)
	assert_eq(p.coins, 5)
	assert_true(p.owns(Catalog.FLYER, "ember"))
	assert_eq(Shop.buy(p, Catalog.FLYER, "ember"), Shop.Result.ALREADY_OWNED)
	assert_eq(Shop.buy(p, Catalog.FLYER, "nope"), Shop.Result.UNKNOWN_ITEM)


func test_every_item_has_a_price_and_each_kind_has_starters() -> void:
	for kind in Catalog.KINDS:
		assert_false(Shop.starters(kind).is_empty(), "%s has free starters" % kind)
		for id in Catalog.ids(kind):
			assert_true(Shop.price(kind, id) >= 0, "%s %s has a price" % [kind, id])


func test_launch_flyers_have_art() -> void:
	var ids := Catalog.ids(Catalog.FLYER)
	for id in ["buzz", "dash", "nimbus", "hoot", "fold", "ember"]:
		assert_true(id in ids, "flyer %s exists" % id)
	for f in Catalog.flyers():
		assert_true(f.idle != null and f.flap != null, "%s has idle and flap art" % f.id)
		assert_false(f.display_name.is_empty(), "%s has a name" % f.id)


func test_bird_tilts_nose_up_when_rising_and_down_when_falling() -> void:
	assert_true(BirdView.tilt_for(SimConfig.FLAP_VY) < -0.5, "nose up after a flap")
	assert_true(BirdView.tilt_for(SimConfig.MAX_FALL_VY) > 1.0, "nose down at full fall")
	assert_eq(BirdView.tilt_for(0), 0.0)


func test_new_flyers_have_art_and_fit_real_worlds() -> void:
	var ids := Catalog.ids(Catalog.FLYER)
	for id in ["pip", "mochi", "tock", "lulu", "puff", "bubbles"]:
		assert_true(id in ids, "flyer %s is in the catalog" % id)
	var worlds := Catalog.ids(Catalog.WORLD)
	for f in Catalog.flyers():
		assert_true(f.idle != null and f.flap != null, "%s has idle and flap art" % f.id)
		for w in f.fits_worlds:
			assert_true(w in worlds, "%s fits %s, which exists" % [f.id, w])
	var orders := {}
	for f in Catalog.flyers():
		assert_false(orders.has(f.order), "%s has its own order" % f.id)
		orders[f.order] = true


func test_trail_styles_are_complete() -> void:
	var seen := {}
	for t in Catalog.trails():
		assert_false(seen.has(t.id), "trail id %s is unique" % t.id)
		seen[t.id] = true
		assert_true(t.lifetime > 0.0 and t.width > 0.0, "%s has a size and lifetime" % t.id)
		if t.kind in [TrailStyle.Kind.STRIPES, TrailStyle.Kind.STAMPS, TrailStyle.Kind.COMET]:
			assert_true(t.colors.size() > 0, "%s has colours" % t.id)
		assert_true(Shop.price(Catalog.TRAIL, t.id) >= 0, "%s has a price" % t.id)
	assert_eq(Catalog.trails().size(), 10, "two launch trails plus eight new ones")
