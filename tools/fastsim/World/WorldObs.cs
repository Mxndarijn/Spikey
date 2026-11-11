namespace FastSim.Model;

/// The world model as a fixed-size vector for a learned policy (the RL bots):
/// structured inputs instead of a danger picture. All values are scaled to
/// about -1..1. Heights and distances are relative to the bird. Layout:
///
///   [0..11]    bird and room: y, vy, dir, gravity, ticks to wall, x, insets (2),
///              speed fast, speed slow, gravity flips, arrival hold
///   [12..29]   own path at the wall ahead (exact): for wait, tap now and tap at
///              4, 8, 12, 16, 20, 25, 30 ticks: landing height (rel.) and lives (1/0)
///   [30..42]   the 13 spike slots of the wall ahead (1 = spike)
///   [43..50]   gaps: nearest gap band top/bottom, second gap top/bottom (rel.),
///              exit ahead (1/0), exit height (rel.), exit locked, wall shift
///   [51..146]  the 8 nearest deadly bodies (by distance to their outline):
///              dx, dy, half width, half height, vx, vy (per tick), dx and dy 30
///              ticks ahead (by the model, waiting), guess, reacts, gap to the
///              bird, live (1/0 for a real entry)
///   [147..151] forces at the bird: wind push, updraft lift, nearest bumper dx, dy,
///              under an edge pad
public static class WorldObs
{
    public const int NEAREST = 8;
    public const int PER_BODY = 12;
    public const int HEAD = 51;
    public const int SIZE = HEAD + NEAREST * PER_BODY + 5;
    public const long AHEAD = 30;
    static readonly long[] TAP_AT = { 4, 8, 12, 16, 20, 25, 30 };

    const double PX = SimConfig.SUB;
    const double H = 320 * PX;
    const double W = 360 * PX;

    static float F(double v) => (float)Math.Clamp(v, -4.0, 4.0);

    /// Fills `x` (length SIZE) from the world model `w`. Costs about ten model
    /// copies run to the wall, so it is slower than the danger-grid observer.
    public static void Fill(WorldModel w, float[] x)
    {
        Array.Clear(x);
        var r = w.room;
        var b = w.bird;
        long side = b.vx > 0 ? 1 : 0;
        x[0] = F((b.y - 320 * PX) / H);
        x[1] = F(b.vy / (double)SimConfig.MAX_FALL_VY);
        x[2] = b.vx > 0 ? 1 : -1;
        x[3] = r.gravity;
        x[4] = F(BirdPath.TicksToWall(w) / 100.0);
        x[5] = F((b.x - 180 * PX) / (180 * PX));
        x[6] = F(r.WallLeft / (100 * PX));
        x[7] = F((SimConfig.WORLD_W - r.WallRight) / (100 * PX));
        x[8] = r.speed == RoomDef.Speed.FAST ? 1 : 0;
        x[9] = r.speed == RoomDef.Speed.SLOW ? 1 : 0;
        x[10] = r.flip_flop ? 1 : 0;
        x[11] = r.hold > 0 ? 1 : 0;

        int i = 12;
        void Land(Landing l)
        {
            x[i++] = F((l.y - b.y) / H);
            x[i++] = l.alive ? 1 : 0;
        }
        Land(BirdPath.AtWall(w, -1));
        Land(BirdPath.AtWall(w, 0));
        foreach (long t in TAP_AT) Land(BirdPath.AtWall(w, t));

        long mask = r.Mask(side);
        for (int s = 0; s < SimConfig.SLOT_COUNT; s++) x[30 + s] = RoomRules.has_slot(mask, s) ? 1 : 0;

        long shift = Physics.Shift(w.hz, null, side);
        var gaps = WorldDesc.Gaps(mask, shift, r.half_base).OrderBy(g => Math.Abs(g.mid - b.y)).ToList();
        if (gaps.Count > 0)
        {
            x[43] = F((gaps[0].top - b.y) / H);
            x[44] = F((gaps[0].bottom - b.y) / H);
        }
        if (gaps.Count > 1)
        {
            x[45] = F((gaps[1].top - b.y) / H);
            x[46] = F((gaps[1].bottom - b.y) / H);
        }
        if (r.ExitAhead(side))
        {
            x[47] = 1;
            long ey = r.exit_b_kind == ExitKind.WILD ? r.exit_b_y : r.exit_a_y;
            x[48] = F((ey - b.y) / H);
        }
        x[49] = w.hz.Any(h => h.alive && h.Locks) ? 1 : 0;
        x[50] = F(shift / (80 * PX));

        // The nearest deadly bodies, now and AHEAD ticks later.
        var later = w.Copy();
        for (long k = 0; k < AHEAD; k++) later.Tick(false);
        var picks = new List<(double gap, HazardModel h, int j)>();
        foreach (var h in w.hz)
        {
            if (!h.alive) continue;
            for (int j = 0; j < h.bodies.Length; j++)
            {
                var body = h.bodies[j];
                if (!body.on || !body.deadly) continue;
                picks.Add((body.s.Gap(b.x, b.y), h, j));
            }
        }
        picks.Sort((p, q) => p.gap.CompareTo(q.gap));
        long steps = r.SpeedQuarters;
        for (int n = 0; n < NEAREST && n < picks.Count; n++)
        {
            var (gap, h, j) = picks[n];
            var s = h.bodies[j].s;
            int o = HEAD + n * PER_BODY;
            x[o + 0] = F((s.Cx - b.x) / W);
            x[o + 1] = F((s.Cy - b.y) / H);
            x[o + 2] = F(Math.Min(s.W, SimConfig.WORLD_W) / (200 * PX));
            x[o + 3] = F(Math.Min(s.H, SimConfig.WORLD_H) / (200 * PX));
            var one = h.Copy();
            var c = w.Copy();
            c.room.t += 1;
            one.t = c.room.t;
            one.Step(c);
            if (j < one.bodies.Length)
            {
                x[o + 4] = F((one.bodies[j].s.Cx - s.Cx) * steps / 4.0 / (8 * PX));
                x[o + 5] = F((one.bodies[j].s.Cy - s.Cy) * steps / 4.0 / (8 * PX));
            }
            var hl = later.Find(h.index);
            if (hl != null && j < hl.bodies.Length && hl.bodies[j].on)
            {
                x[o + 6] = F((hl.bodies[j].s.Cx - b.x) / W);
                x[o + 7] = F((hl.bodies[j].s.Cy - b.y) / H);
            }
            x[o + 8] = h.bodies[j].guess ? 1 : 0;
            x[o + 9] = h.reactive ? 1 : 0;
            x[o + 10] = F(gap / (100 * PX));
            x[o + 11] = 1;
        }

        // Pushes at the bird.
        int f = HEAD + NEAREST * PER_BODY;
        var probe = b;
        foreach (var h in w.hz)
        {
            if (!h.alive) continue;
            if (h is WindM)
            {
                var p = probe;
                h.Touch(w, ref p);
                x[f] = F((p.x - probe.x) / (double)Wind.PUSH);
            }
            else if (h is UpdraftM)
            {
                var p = probe;
                h.Touch(w, ref p);
                x[f + 1] = F((probe.vy - p.vy) / (double)SimConfig.GRAVITY);
            }
            else if (h is BumperM && h.bodies.Length > 0)
            {
                x[f + 2] = F((h.bodies[0].s.Cx - b.x) / W);
                x[f + 3] = F((h.bodies[0].s.Cy - b.y) / H);
            }
            else if (h is EdgePadM pad && pad.Covers(b.x)) x[f + 4] = pad.top ? -1 : 1;
        }
    }
}
