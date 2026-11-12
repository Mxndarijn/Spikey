namespace FastSim.Yard;

/// One run as the yardstick keeps it: where it was played and when it tapped.
/// Bots and humans give the same thing, so both are measured by one replay
/// (Run.analyze). Revives are not played: a run ends at its first death.
public sealed record RunInput(long seed, long season, long[] taps, string source = "");

/// What one replayed run tells the yardstick.
public sealed class Run
{
    public const int BANDS = 8;
    public static readonly long BAND_H = (SimConfig.KILL_BOTTOM - SimConfig.KILL_TOP) / BANDS;
    /// A first tap more than this many ticks after a new thing is not a reaction to it.
    public const int REACT_WINDOW = 60;

    public RunInput input;
    public long points, ticks, start_tick;
    public bool dead;
    public string room = "", cause = "";
    /// Ticks between taps after the start tap.
    public List<int> intervals = new();
    /// Ticks spent in each of 8 height bands (KILL_TOP at band 0 .. KILL_BOTTOM).
    public long[] bands = new long[BANDS];
    /// Ticks from a wall bounce (a new wall ahead) to the next tap.
    public List<int> react_bounce = new();
    /// Ticks from a new room or a new hazard in the room to the next tap.
    public List<int> react_new = new();
    /// Rooms entered ("id" or "id/variant"), the first one included.
    public Dictionary<string, int> visits = new();
    public int taps_played;
    /// Taps made while the bird waits at a portal, which the game ignores.
    public int taps_held;

    public double seconds => Math.Max(1, ticks - start_tick) / (double)SimConfig.TICKS_PER_SECOND;
    public double taps_per_s => Math.Max(0, taps_played - 1) / seconds;

    public static string room_name(GameSim sim)
    {
        string v = sim.room.variant_id();
        return v == "" ? sim.room.def.id : sim.room.def.id + "/" + v;
    }

    /// Plays `bot` from a fresh sim of `seed` to death or `cap` ticks and
    /// returns the taps it made.
    public static RunInput play(BotSpec bot, long seed, long cap)
    {
        var decide = bot.make(seed);
        var sim = new GameSim(seed);
        var taps = new List<long>();
        while (sim.state.tick < cap && !sim.is_over())
        {
            bool tap = decide(sim);
            if (tap) taps.Add(sim.state.tick);
            sim.step(tap);
        }
        return new RunInput(seed, Seasons.NONE, taps.ToArray(), bot.name);
    }

    /// Replays `r` to its first death or `cap` ticks and measures it.
    public static Run analyze(RunInput r, long cap)
    {
        var run = new Run { input = r };
        var sim = new GameSim(r.seed, r.season);
        long start_score = sim.state.score;
        int next = 0;
        long last_tap = -1;
        var pending_bounce = new List<long>();
        var pending_new = new List<long>();
        int hazards = sim.room.hazards.Count;
        run.visits[room_name(sim)] = 1;
        run.start_tick = -1;
        while (sim.state.tick < cap && !sim.is_over())
        {
            long t = sim.state.tick;
            bool tap = next < r.taps.Length && r.taps[next] == t;
            if (tap) next++;
            if (sim.state.started)
            {
                long b = (sim.state.y - SimConfig.KILL_TOP) / BAND_H;
                run.bands[Math.Clamp(b, 0, BANDS - 1)]++;
            }
            // A tap during the portal wait (arrival_hold) does nothing in the game: not counted.
            if (tap && sim.state.arrival_hold > 0) run.taps_held++;
            else if (tap)
            {
                run.taps_played++;
                if (last_tap >= 0 && sim.state.started) run.intervals.Add((int)(t - last_tap));
                last_tap = t;
                foreach (var e in pending_bounce) if (t - e <= REACT_WINDOW) run.react_bounce.Add((int)(t - e));
                foreach (var e in pending_new) if (t - e <= REACT_WINDOW) run.react_new.Add((int)(t - e));
                pending_bounce.Clear();
                pending_new.Clear();
            }
            bool was_started = sim.state.started;
            sim.step(tap);
            if (!was_started && sim.state.started) run.start_tick = sim.state.tick;
            bool room_change = false;
            foreach (int ev in sim.events)
            {
                if (ev == Event.BOUNCE) pending_bounce.Add(sim.state.tick);
                if (ev == Event.ROOM_CHANGE) room_change = true;
            }
            int now = sim.room.hazards.Count;
            if (room_change)
            {
                string name = room_name(sim);
                run.visits[name] = run.visits.GetValueOrDefault(name) + 1;
                pending_new.Add(sim.state.tick);
            }
            else if (now > hazards) pending_new.Add(sim.state.tick);
            hazards = now;
        }
        if (run.start_tick < 0) run.start_tick = sim.state.tick;
        run.points = sim.state.score - start_score;
        run.ticks = sim.state.tick;
        run.dead = sim.is_over();
        run.room = room_name(sim);
        run.cause = run.dead ? DeathCause.NAMES[sim.state.death_cause] : "";
        return run;
    }
}
