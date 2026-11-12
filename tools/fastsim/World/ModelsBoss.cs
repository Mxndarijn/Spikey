namespace FastSim.Model;

/// Boss rooms (every 100 points): the Watcher, the Crusher and the Saw King.
/// A boss runs a visible rhythm (cycles from the phase start; the phase
/// follows the room's points, a new phase starts STAGGER substeps late) and
/// shows each attack before it lands: lit beam rows, a dashed dart lane, the
/// slam height, the next jaw lane, a crate's column, the king's next height.
/// The model reads what is on screen and plays the rhythm forward. An attack
/// not yet shown is a hidden random choice: the model leaves it out (beams,
/// darts are aimed at the bird and so are exact, crates) or guesses it
/// (slam: the deepest one; jaws and king: they stay where they are).
/// Boss models are reactive: the phase follows the points the bird scores,
/// and the Watcher's gaze aims at the bird.
public abstract class BossM : HazardModel
{
    protected long tier, phase, phase_start, down_at;

    protected BossM(Boss h)
    {
        kind = h.kind;
        t = h.t;
        tier = h.tier;
        phase = h.phase;
        phase_start = h.phase_start;
        down_at = h.down_at;
        reactive = true;
        random = true;
    }

    protected long Clock => t - phase_start;

    public override void Step(WorldModel w)
    {
        if (down_at < 0 && (w.room.exit_open || w.room.exit_preview)) down_at = t;
        if (down_at >= 0)
        {
            DownStep(w);
            Place(w);
            return;
        }
        long p = Boss.phase_of(w.room.points);
        if (p != phase)
        {
            phase = p;
            phase_start = t + Boss.STAGGER;
            OnPhase();
        }
        BossStep(w);
        Place(w);
    }

    protected abstract void BossStep(WorldModel w);
    protected abstract void DownStep(WorldModel w);
    protected virtual void OnPhase() { }
    protected abstract void Place(WorldModel w);

    public override string Motion => "boss";
    public override string State => down_at >= 0 ? "down" : "phase " + phase;

    public override void Params(Dictionary<string, double> p)
    {
        p["tier"] = tier;
        p["phase"] = phase;
        p["clock"] = Clock;
    }

    protected static long Toward(long from, long to, long down, long up) =>
        to > from ? G.mini(from + down, to) : G.maxi(from - up, to);
}

/// The Watcher: beam rows light up after a BEAM_TELL (2 s) warning (which rows is
/// drawn per cycle: known once warned), and in phases 2 and 3 a gaze marks a
/// dart lane at the bird's height, then the dart flies across.
public sealed class WatcherM : BossM
{
    long lit, lit_k, beam, beam_t;
    bool lit_known;
    long dart, dart_lane, dart_side, dart_x, dart_t;
    readonly long gaze_every;

    public WatcherM(BossWatcher h) : base(h)
    {
        lit = h.lit;
        lit_k = h._lit_k;
        // The rows of the current cycle are on screen from its warning on.
        lit_known = h.beam != BossWatcher.Beam.OFF || h.down_at >= 0 || Clock >= 0 && phase != 2;
        beam = h.beam;
        beam_t = h.beam_t;
        dart = h.dart;
        dart_lane = h.dart_lane;
        dart_side = h.dart_side;
        dart_x = h.dart_x;
        dart_t = h.dart_t;
        gaze_every = tier >= 3 ? BossWatcher.GAZE_FAST : BossWatcher.GAZE;
        bodies = new Body[BossWatcher.ROWS.Length + 1];
        Place(null);
    }

    protected override void BossStep(WorldModel w)
    {
        beam = BossWatcher.Beam.OFF;
        long c = Clock;
        if (c < 0)
        {
            dart = BossWatcher.Dart.NONE;
            return;
        }
        if (phase != 2)
        {
            long k = c / BossWatcher.CYCLE;
            beam_t = c % BossWatcher.CYCLE;
            if (lit_k != k)
            {
                // New rows, drawn by the boss: not known until they warn.
                lit_k = k;
                lit = 0;
                lit_known = false;
            }
            if (beam_t < BossWatcher.BEAM_TELL) beam = BossWatcher.Beam.WARN;
            else if (beam_t < BossWatcher.BEAM_TELL + BossWatcher.BEAM_ON) beam = BossWatcher.Beam.ON;
        }
        long g = phase == 2 ? c % gaze_every : (c % BossWatcher.CYCLE) - BossWatcher.GAZE_AT;
        if (phase != 1) Gaze(w, g);
    }

    void Gaze(WorldModel w, long g)
    {
        if (g == 0)
        {
            dart = BossWatcher.Dart.MARK;
            dart_lane = G.clampi(w.bird.y, BossWatcher.LANE_MIN, BossWatcher.LANE_MAX);
            dart_side = w.bird.vx > 0 ? 1 : 0;
        }
        if (dart == BossWatcher.Dart.MARK)
        {
            dart_t = g;
            if (g >= BossWatcher.GAZE_TELL)
            {
                dart = BossWatcher.Dart.FLY;
                dart_x = dart_side == 1 ? w.room.WallRight : w.room.WallLeft;
            }
        }
        else if (dart == BossWatcher.Dart.FLY)
        {
            dart_x += dart_side == 1 ? -BossWatcher.DART_SPEED : BossWatcher.DART_SPEED;
            if (dart_x < -BossWatcher.DART_LEN || dart_x > SimConfig.WORLD_W + BossWatcher.DART_LEN)
                dart = BossWatcher.Dart.NONE;
        }
    }

    protected override void DownStep(WorldModel w)
    {
        beam = BossWatcher.Beam.OFF;
        dart = BossWatcher.Dart.NONE;
    }

    protected override void Place(WorldModel w)
    {
        long left = w?.room.WallLeft ?? 0, right = w?.room.WallRight ?? SimConfig.WORLD_W;
        bool on = beam == BossWatcher.Beam.ON && down_at < 0;
        for (int i = 0; i < BossWatcher.ROWS.Length; i++)
        {
            long y = BossWatcher.ROWS[i];
            bodies[i] = Body.Kill(Shape.Rect(left, y - BossWatcher.HALF_H, right, y + BossWatcher.HALF_H),
                on && ((lit >> i) & 1) == 1);
        }
        long back = dart_side == 1 ? dart_x + BossWatcher.DART_LEN : dart_x - BossWatcher.DART_LEN;
        bodies[^1] = Body.Kill(
            Shape.Rect(G.mini(dart_x, back), dart_lane - BossWatcher.DART_HALF, G.maxi(dart_x, back),
                dart_lane + BossWatcher.DART_HALF),
            dart == BossWatcher.Dart.FLY && down_at < 0);
    }

    public override string State => beam == BossWatcher.Beam.WARN ? "warning" : base.State;

    public override void Params(Dictionary<string, double> p)
    {
        base.Params(p);
        p["lit_known"] = lit_known ? 1 : 0;
        p["dart"] = dart;
    }
}

/// The Crusher: a press from the ceiling and a plate from the floor. Phase 1
/// the press slams to a height shown while it shakes; phases 2 and 3 both
/// jaws move to a lane shown TELL (2 s) ahead; phase 3 also drops crates
/// from columns marked before they fall.
public sealed class CrusherM : BossM
{
    long press_y, plate_y, slam_y, slam_k, lane_from, lane_to, k_seen;
    bool jaw, telling, lane_guess, slam_guess;
    long[] crate_x, crate_y, crate;
    readonly long lane_half, deepest;

    public CrusherM(BossCrusher h) : base(h)
    {
        press_y = h.press_y;
        plate_y = h.plate_y;
        slam_y = h.slam_y;
        lane_from = h.lane_from;
        lane_to = h.lane_to;
        jaw = h.jaw;
        telling = h.telling;
        k_seen = h._k;
        long c = Clock;
        // Phase 1 shows the slam height while the press shakes, then the press is at it.
        slam_k = c >= 0 && phase == 1 ? c / BossCrusher.CYCLE : -1;
        crate_x = (long[])h.crate_x.Clone();
        crate_y = (long[])h.crate_y.Clone();
        crate = (long[])h.crate.Clone();
        lane_half = h.lane_half();
        deepest = BossCrusher.SLAMS.Max() + (tier >= 2 ? BossCrusher.SLAM_TIER : 0) - BossCrusher.TEETH;
        bodies = new Body[4];
        Place(null);
    }

    protected override void CopyLists(HazardModel c)
    {
        var m = (CrusherM)c;
        m.crate_x = (long[])crate_x.Clone();
        m.crate_y = (long[])crate_y.Clone();
        m.crate = (long[])crate.Clone();
    }

    protected override void BossStep(WorldModel w)
    {
        telling = false;
        long c = Clock;
        long press_to = jaw ? press_y : BossCrusher.PRESS_REST;
        long plate_to = plate_y;
        if (c >= 0 && phase == 1)
        {
            long k = c / BossCrusher.CYCLE;
            long lt = c % BossCrusher.CYCLE;
            if (k != slam_k)
            {
                // Not shown yet: expect the deepest slam.
                slam_k = k;
                slam_y = deepest;
                slam_guess = true;
            }
            telling = lt < BossCrusher.SLAM_AT;
            press_to = lt >= BossCrusher.SLAM_AT && lt < BossCrusher.LIFT_AT ? slam_y : BossCrusher.PRESS_REST;
        }
        else if (c >= 0)
        {
            long k = c / BossCrusher.CYCLE;
            long lt = c % BossCrusher.CYCLE;
            if (k_seen != k)
            {
                k_seen = k;
                lane_from = jaw ? lane_to : -1;
                // The first lane is fixed; later ones are drawn: guess the jaws stay.
                lane_guess = jaw;
                lane_to = jaw ? lane_from : BossCrusher.LANE_FIRST;
                jaw = true;
            }
            telling = lt < BossCrusher.TELL;
            long lane = lt >= BossCrusher.TELL ? lane_to : lane_from;
            if (lane >= 0)
            {
                press_to = lane - lane_half - BossCrusher.TEETH;
                plate_to = lane + lane_half + BossCrusher.TEETH;
            }
            if (phase == 3) Crates(lt);
        }
        press_y = Toward(press_y, press_to, phase == 1 ? BossCrusher.SLAM_DOWN : BossCrusher.JAW_SPEED,
            BossCrusher.LIFT);
        plate_y = Toward(plate_y, plate_to, BossCrusher.JAW_SPEED, BossCrusher.JAW_SPEED);
    }

    protected override void OnPhase()
    {
        k_seen = -1;
        crate = new long[] { BossCrusher.Crate.NONE, BossCrusher.Crate.NONE };
    }

    void Crates(long lt)
    {
        // New crates' columns are drawn (and keep away from the bird): unknown until marked.
        if (lt == BossCrusher.CRATE_AT)
            for (int i = 0; i < 2; i++) crate[i] = BossCrusher.Crate.NONE;
        for (int i = 0; i < 2; i++)
        {
            if (crate[i] == BossCrusher.Crate.NONE) continue;
            if (crate[i] == BossCrusher.Crate.MARK)
            {
                crate_y[i] = press_y + BossCrusher.TEETH + BossCrusher.CRATE_HALF;
                if (lt >= BossCrusher.CRATE_FALL) crate[i] = BossCrusher.Crate.FALL;
            }
            else
            {
                crate_y[i] += BossCrusher.CRATE_SPEED;
                if (crate_y[i] + BossCrusher.CRATE_HALF >= plate_y - BossCrusher.TEETH)
                    crate[i] = BossCrusher.Crate.NONE;
            }
        }
    }

    protected override void DownStep(WorldModel w)
    {
        telling = false;
        crate = new long[] { BossCrusher.Crate.NONE, BossCrusher.Crate.NONE };
        press_y = Toward(press_y, BossCrusher.PRESS_REST, BossCrusher.LIFT, BossCrusher.LIFT);
        plate_y = Toward(plate_y, BossCrusher.PLATE_REST, BossCrusher.LIFT, BossCrusher.LIFT);
    }

    protected override void Place(WorldModel w)
    {
        const long FAR = 4 * SimConfig.WORLD_W;
        bool on = down_at < 0;
        // The kill test is height only (bird top at the press's bite, bottom at the plate's).
        bodies[0] = Body.Kill(Shape.Rect(-FAR, -FAR, FAR, press_y + BossCrusher.BITE), on);
        bodies[0].guess = slam_guess && phase == 1 || lane_guess;
        bodies[1] = Body.Kill(Shape.Rect(-FAR, plate_y - BossCrusher.BITE, FAR, FAR), on);
        bodies[1].guess = lane_guess;
        for (int i = 0; i < 2; i++)
        {
            long x = crate_x[i], y = crate_y[i], r = BossCrusher.CRATE_HALF;
            bodies[2 + i] = Body.Kill(Shape.Rect(x - r, y - r, x + r, y + r),
                on && crate[i] == BossCrusher.Crate.FALL);
        }
    }

    public override string State => telling ? "warning" : base.State;

    public override void Params(Dictionary<string, double> p)
    {
        base.Params(p);
        p["press_y"] = Px(press_y);
        p["plate_y"] = Px(plate_y);
    }
}

/// The Saw King: a big saw in the middle that hops between three heights
/// (from the top or bottom always back to the middle; from the middle up or
/// down, shown TELL (2 s) ahead), with a spinning ring of blades in phase 2
/// (at a height shown while it tells) and a small ring in phase 3.
public sealed class SawKingM : BossM
{
    long king_y, from_y, to_y, ring, angle, k_seen;
    bool telling, to_guess;
    readonly long blades, ring_max;

    public SawKingM(BossSaw h) : base(h)
    {
        king_y = h.king_y;
        from_y = h.from_y;
        to_y = h.to_y;
        ring = h.ring;
        angle = h.angle;
        k_seen = h._k;
        telling = h.telling;
        blades = h.blades;
        ring_max = tier >= 3 ? BossSaw.RING_MAX_TIER3 : BossSaw.RING_MAX;
        bodies = new Body[1 + blades];
        Place(null);
    }

    long Cycle => phase == 3 && tier >= 2 ? BossSaw.CYCLE_FAST : BossSaw.CYCLE;

    protected override void OnPhase() => k_seen = -1;

    protected override void BossStep(WorldModel w)
    {
        angle = G.posmod(angle + BossSaw.SPIN, SimTrig.TURN);
        telling = false;
        long c = Clock;
        long ring_to = ring;
        if (c < 0)
        {
            ring_to = phase == 3 ? BossSaw.RING_HOP : 0;
            if (phase != 2) king_y = Toward(king_y, BossSaw.HEIGHTS[BossSaw.nearest(king_y)], BossSaw.SLIDE, BossSaw.SLIDE);
        }
        else if (phase == 2)
        {
            long k = c / BossSaw.CYCLE;
            long lt = c % BossSaw.CYCLE;
            if (k_seen != k)
            {
                k_seen = k;
                from_y = king_y;
                // One of two ring heights, drawn: guess the nearer.
                to_y = G.absi(BossSaw.RING_YS[0] - from_y) <= G.absi(BossSaw.RING_YS[1] - from_y)
                    ? BossSaw.RING_YS[0]
                    : BossSaw.RING_YS[1];
                to_guess = true;
            }
            telling = lt < BossSaw.RING_OUT;
            king_y = Jump(lt);
            ring_to = lt >= BossSaw.RING_OUT && lt < BossSaw.RING_IN ? ring_max : 0;
        }
        else
        {
            long k = c / Cycle;
            long lt = c % Cycle;
            if (k_seen != k)
            {
                k_seen = k;
                from_y = king_y;
                // From the top or bottom it always comes back to the middle.
                to_guess = BossSaw.nearest(from_y) == 1;
                to_y = to_guess ? from_y : BossSaw.HEIGHTS[1];
            }
            telling = lt < BossSaw.TELL;
            king_y = Jump(lt);
            ring_to = phase == 3 ? BossSaw.RING_HOP : 0;
        }
        ring = Toward(ring, ring_to, BossSaw.RING_SPEED, BossSaw.RING_SPEED);
    }

    long Jump(long lt)
    {
        if (lt < BossSaw.TELL) return from_y;
        if (lt < BossSaw.TELL + BossSaw.JUMP) return from_y + (to_y - from_y) * (lt - BossSaw.TELL) / BossSaw.JUMP;
        return to_y;
    }

    protected override void DownStep(WorldModel w)
    {
        telling = false;
        ring = Toward(ring, 0, BossSaw.RING_SPEED, BossSaw.RING_SPEED);
    }

    protected override void Place(WorldModel w)
    {
        bool on = down_at < 0;
        bodies[0] = Body.Kill(Shape.Circle(BossSaw.KING_X, king_y, BossSaw.KING_R), on);
        bodies[0].guess = to_guess;
        for (int i = 0; i < blades; i++)
        {
            long a = angle + i * SimTrig.TURN / blades;
            long x = BossSaw.KING_X + ring * SimTrig.cos_t(a) / SimTrig.ONE;
            long y = king_y + ring * SimTrig.sin_t(a) / SimTrig.ONE;
            bodies[1 + i] = Body.Kill(Shape.Circle(x, y, BossSaw.BLADE_R), on && ring >= BossSaw.RING_SHOW);
            bodies[1 + i].guess = to_guess;
        }
    }

    public override string Motion => "boss hop";
    public override string State => telling ? "warning" : base.State;

    public override void Params(Dictionary<string, double> p)
    {
        base.Params(p);
        p["king_y"] = Px(king_y);
        p["ring"] = Px(ring);
    }
}
