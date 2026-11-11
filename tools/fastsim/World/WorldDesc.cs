using System.Text;

namespace FastSim.Model;

/// The bird's own path ahead: exact (fixed, known physics plus the modelled
/// pushes), on a copy of the world model.
public readonly record struct Landing(long ticks, long y, long vy, bool alive, bool exited, long cause)
{
    public double y_px => y / (double)SimConfig.SUB;
}

public static class BirdPath
{
    public const long LIMIT = 240;

    /// Where the bird is when it reaches the wall ahead (bounces or exits) if it
    /// taps at tick `tap_at` from now (-1: never, 0: now) and waits otherwise.
    /// Stops early if a modelled hazard or edge would kill it.
    public static Landing AtWall(WorldModel w, long tap_at)
    {
        var c = w.Copy();
        for (long k = 0; k < LIMIT; k++)
        {
            c.Tick(k == tap_at);
            if (!c.bird.alive) return new Landing(k + 1, c.bird.y, c.bird.vy, false, false, c.bird.cause);
            if (c.exited) return new Landing(k + 1, c.bird.y, c.bird.vy, true, true, 0);
            if (c.bounced) return new Landing(k + 1, c.bird.y, c.bird.vy, true, false, 0);
        }
        return new Landing(LIMIT, c.bird.y, c.bird.vy, c.bird.alive, false, 0);
    }

    /// Ticks until the bird reaches the wall ahead at its sideways speed (no pushes).
    public static long TicksToWall(WorldModel w)
    {
        var r = w.room;
        long left = r.WallLeft + Physics.R, right = r.WallRight - Physics.R;
        long ahead = w.bird.vx > 0 ? right - w.bird.x : w.bird.x - left;
        long subs = Math.Max(0, ahead) / SimConfig.SPEED_X;
        long ticks = 0, done = 0;
        while (done < subs && ticks < 1000)
        {
            long n = r.StepsAt(r.ticks + ticks);
            done += n;
            ticks++;
        }
        return ticks;
    }
}

/// A gap on a wall: free slots and the band of heights the bird's centre can pass in.
public readonly record struct Gap(long first_slot, long last_slot, long top, long bottom)
{
    public long mid => (top + bottom) / 2;
}

/// The world as structured records (docs/WORLD_MODEL.md): what a bot reads.
public sealed class WorldDesc
{
    public sealed class HazardRec
    {
        public int index;
        public string type = "", kind = "", motion = "", state = "";
        public bool deadly, guess, reactive, random;
        public int bodies;
        /// Nearest body to the bird: centre relative to the bird (px), size (px), velocity (px per substep).
        public double dx, dy, w, h, vx, vy;
        public Dictionary<string, double> param = new();
    }

    public string room = "", variant = "";
    public long speed, gravity, wall_mode, score, points, tick;
    public bool flip, squeeze;
    public double bird_x, bird_y, bird_vx, bird_vy, radius;
    public long dir;
    public long ticks_to_wall;
    public Landing wait, tap_now;
    public Landing[] tap_at = Array.Empty<Landing>();
    public long[] tap_ticks = Array.Empty<long>();
    public long wall_mask, wall_shift;
    public List<Gap> gaps = new();
    public bool exit_ahead, exit_locked, exit_preview;
    public double exit_a_y, exit_b_y;
    public long exit_a_kind, exit_b_kind;
    public bool next_wall_known;
    public List<HazardRec> hazards = new();

    public static readonly long[] TAP_AT = { 4, 8, 12, 16, 20, 25, 30, 40 };

    public static List<Gap> Gaps(long mask, long shift, long half_base)
    {
        var out_ = new List<Gap>();
        long r = Physics.R;
        long slot = 0;
        while (slot < SimConfig.SLOT_COUNT)
        {
            if (RoomRules.has_slot(mask, slot))
            {
                slot++;
                continue;
            }
            long a = slot;
            while (slot < SimConfig.SLOT_COUNT && !RoomRules.has_slot(mask, slot)) slot++;
            long b = slot - 1;
            long top = a == 0 ? SimConfig.KILL_TOP + r : SimConfig.slot_center_y(a - 1) + shift + half_base + r;
            long bottom = b == SimConfig.SLOT_COUNT - 1 ? SimConfig.KILL_BOTTOM - r : SimConfig.slot_center_y(b + 1) + shift - half_base - r;
            if (bottom > top) out_.Add(new Gap(a, b, top, bottom));
        }
        return out_;
    }

    public static WorldDesc Of(WorldModel w)
    {
        var r = w.room;
        var b = w.bird;
        long side = b.vx > 0 ? 1 : 0;
        var d = new WorldDesc
        {
            room = r.id,
            variant = r.variant,
            speed = r.speed,
            gravity = r.gravity,
            wall_mode = r.wall_mode,
            score = r.score,
            points = r.points,
            tick = w.tick,
            flip = r.flip_flop,
            squeeze = r.squeeze,
            bird_x = b.x / (double)SimConfig.SUB,
            bird_y = b.y / (double)SimConfig.SUB,
            bird_vx = b.vx / (double)SimConfig.SUB,
            bird_vy = b.vy / (double)SimConfig.SUB,
            radius = Physics.R / (double)SimConfig.SUB,
            dir = b.vx > 0 ? 1 : -1,
            ticks_to_wall = BirdPath.TicksToWall(w),
            wait = BirdPath.AtWall(w, -1),
            tap_now = BirdPath.AtWall(w, 0),
            tap_ticks = TAP_AT,
            tap_at = TAP_AT.Select(t => BirdPath.AtWall(w, t)).ToArray(),
            wall_mask = r.Mask(side),
            wall_shift = Physics.Shift(w.hz, null, side),
            exit_ahead = r.ExitAhead(side),
            exit_locked = w.hz.Any(h => h.alive && h.Locks),
            exit_preview = r.exit_preview,
            exit_a_y = r.exit_a_y / (double)SimConfig.SUB,
            exit_b_y = r.exit_b_y / (double)SimConfig.SUB,
            exit_a_kind = r.exit_a_kind,
            exit_b_kind = r.exit_b_kind,
            next_wall_known = false,
        };
        d.gaps = Gaps(d.wall_mask, d.wall_shift, r.half_base);
        foreach (var h in w.hz)
        {
            if (!h.alive) continue;
            var rec = new HazardRec
            {
                index = h.index,
                type = h.GetType().Name.TrimEnd('M'),
                kind = h.kind,
                motion = h.Motion,
                state = h.State,
                reactive = h.reactive,
                random = h.random,
                bodies = h.bodies.Count(x => x.on),
                deadly = h.bodies.Any(x => x.deadly),
                guess = h.bodies.Any(x => x.on && x.guess),
            };
            h.Params(rec.param);
            // Nearest body now, and its velocity from one substep of the model.
            int best = -1;
            double bd = double.MaxValue;
            for (int i = 0; i < h.bodies.Length; i++)
            {
                if (!h.bodies[i].on) continue;
                double dd = h.bodies[i].s.Gap(b.x, b.y);
                if (dd < bd)
                {
                    bd = dd;
                    best = i;
                }
            }
            if (best >= 0)
            {
                var s = h.bodies[best].s;
                rec.dx = (s.Cx - b.x) / (double)SimConfig.SUB;
                rec.dy = (s.Cy - b.y) / (double)SimConfig.SUB;
                rec.w = Math.Min(s.W, SimConfig.WORLD_W) / (double)SimConfig.SUB;
                rec.h = Math.Min(s.H, SimConfig.WORLD_H) / (double)SimConfig.SUB;
                var c = w.Copy();
                var hc = c.Find(h.index);
                hc.t = c.room.t + 1;
                c.room.t += 1;
                hc.Step(c);
                if (best < hc.bodies.Length)
                {
                    rec.vx = (hc.bodies[best].s.Cx - s.Cx) / (double)SimConfig.SUB;
                    rec.vy = (hc.bodies[best].s.Cy - s.Cy) / (double)SimConfig.SUB;
                }
            }
            d.hazards.Add(rec);
        }
        return d;
    }

    static string L(Landing l) => $"{l.ticks}t y {l.y_px:F0}{(l.exited ? " exit" : l.alive ? "" : " dies (" + DeathCause.NAMES[l.cause] + ")")}";

    public string ToText()
    {
        var sb = new StringBuilder();
        sb.AppendLine($"room {room}{(variant != "" ? "/" + variant : "")}  score {score} (points here {points})  tick {tick}  speed {(speed == 1 ? "fast" : speed == 2 ? "slow" : "normal")}  gravity {gravity}{(flip ? " flips at each wall" : "")}");
        sb.AppendLine($"bird  x {bird_x:F1} y {bird_y:F1}  vx {bird_vx:F2} vy {bird_vy:F2} px/substep  dir {dir}  radius {radius}");
        sb.AppendLine($"wall ahead in {ticks_to_wall} ticks: spikes {Convert.ToString(wall_mask, 2).PadLeft(13, '0')} (slot 12..0) shift {wall_shift / (double)SimConfig.SUB:F1}px" +
            (exit_ahead ? $"  EXIT at {exit_a_y:F0}{(exit_b_kind != 0 ? $" / {exit_b_y:F0}" : "")}{(exit_locked ? " (locked)" : "")}" : "") + (exit_preview ? $"  exit preview at {exit_a_y:F0}" : ""));
        sb.AppendLine("  gaps (bird centre band, px): " + string.Join(", ", gaps.Select(g => $"{g.top / (double)SimConfig.SUB:F0}-{g.bottom / (double)SimConfig.SUB:F0}")));
        sb.AppendLine($"  next wall after: {(next_wall_known ? "known" : "not drawn yet")}");
        sb.AppendLine($"own path at the wall: wait {L(wait)} | tap now {L(tap_now)} | " + string.Join(" | ", tap_ticks.Select((t, i) => $"tap at {t}: {L(tap_at[i])}")));
        foreach (var h in hazards)
        {
            sb.Append($"  #{h.index} {h.type}/{h.kind} {h.motion} [{h.state}]{(h.deadly ? " deadly" : "")}{(h.reactive ? " reacts" : "")}{(h.random ? " random" : "")}{(h.guess ? " GUESS" : "")}");
            sb.Append($"  bodies {h.bodies}, nearest at ({h.dx:F0},{h.dy:F0}) size {h.w:F0}x{h.h:F0} v ({h.vx:F2},{h.vy:F2})");
            if (h.param.Count > 0) sb.Append("  " + string.Join(" ", h.param.Select(p => $"{p.Key}={p.Value:0.##}")));
            sb.AppendLine();
        }
        return sb.ToString();
    }
}
