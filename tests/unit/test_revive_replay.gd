extends TestCase
## A replay of a revived run shows the revive the way the player saw it.

const TEST_PATH := "user://test_revive_replay_profile.json"
const MainScript := preload("res://game/main.gd")


func _make_main() -> Node:
	SafeFile.remove(TEST_PATH)
	var main: Node = load("res://game/main.tscn").instantiate()
	main.profile_path = TEST_PATH
	main.leaderboard = SampleLeaderboard.new(Profile.new())
	main.ads = FakeAds.new()
	main.season = Seasons.NONE
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


## Runs the whole revive countdown: the paused part, then the sim's hold.
static func _count_down(main: Node) -> void:
	for i in MainScript.REVIVE_COUNTDOWN:
		main._tick_countdown(1.0)
	while main._revive_count:
		main._run._physics_process(1.0 / 60.0)
		main._tick_countdown(1.0 / 60.0)


## Watching a revived run shows the revive as it was played: the bird comes
## back out of its portal and the same 5, 4, 3, 2, 1 counts down over the
## frozen room before the replay plays on.
func test_a_replay_shows_the_revive_countdown() -> void:
	var recorded := SimBots.play_revived(5160, SimBots.gap_seeker, 4, 900, 900)
	assert_eq(recorded.revive_ticks.size(), 1)
	var main := _make_main()
	(
		main
		. play_replay(
			{
				"run": 9,
				"name": "Noor",
				"score": recorded.score,
				"gameplay_version": recorded.gameplay_version,
				"seed": recorded.seed_value,
				"taps": Array(recorded.taps),
				"revives": Array(recorded.revive_ticks),
				"loadout": {},
			}
		)
	)
	var sim: GameSim = main._run.sim
	while sim.state.revives == 0 and not sim.is_over():
		main._run.advance()
	assert_eq(sim.state.revives, 1, "the replay revived")
	var revive_tick := sim.state.tick
	assert_true(main._revive_count, "the revive countdown runs")
	assert_true(main._run.paused, "the replay waits")
	assert_eq(main._hud.countdown.text, "5")
	_count_down(main)
	assert_false(main._revive_count, "then it plays on")
	assert_eq(sim.state.tick, revive_tick + SimConfig.ARRIVAL_HOLD, "after the sim's own hold")
	while not sim.is_over():
		main._run.advance()
	assert_eq(sim.state.score, recorded.score, "and ends as the run did")
	main.free()
	SafeFile.remove(TEST_PATH)
