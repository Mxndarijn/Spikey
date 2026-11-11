namespace FastSim.Model;

/// The kinds of shape a hazard body can have.
public enum ShapeKind : byte { Circle, Rect, Tri }

/// One body's outline in sub-units: a circle (x0, y0, radius x1), an
/// axis-aligned rectangle (x0, y0)-(x1, y1), or a triangle with three corners.
/// Hit tests are the sim's own (bird_touches_circle, bird_touches_rect,
/// circle_hits_triangle), so a body here kills exactly where the hazard does.
public struct Shape
{
    public ShapeKind k;
    public long x0, y0, x1, y1, x2, y2;

    public static Shape Circle(long x, long y, long r) => new() { k = ShapeKind.Circle, x0 = x, y0 = y, x1 = r };

    public static Shape Rect(long ax, long ay, long bx, long by) => new()
    {
        k = ShapeKind.Rect, x0 = Math.Min(ax, bx), y0 = Math.Min(ay, by), x1 = Math.Max(ax, bx), y1 = Math.Max(ay, by),
    };

    public static Shape Tri(long ax, long ay, long bx, long by, long cx, long cy) => new()
    {
        k = ShapeKind.Tri, x0 = ax, y0 = ay, x1 = bx, y1 = by, x2 = cx, y2 = cy,
    };

    public long Top => k switch
    {
        ShapeKind.Circle => y0 - x1,
        ShapeKind.Rect => y0,
        _ => Math.Min(y0, Math.Min(y1, y2)),
    };

    public long Bottom => k switch
    {
        ShapeKind.Circle => y0 + x1,
        ShapeKind.Rect => y1,
        _ => Math.Max(y0, Math.Max(y1, y2)),
    };

    public long Left => k switch
    {
        ShapeKind.Circle => x0 - x1,
        ShapeKind.Rect => x0,
        _ => Math.Min(x0, Math.Min(x1, x2)),
    };

    public long Right => k switch
    {
        ShapeKind.Circle => x0 + x1,
        ShapeKind.Rect => x1,
        _ => Math.Max(x0, Math.Max(x1, x2)),
    };

    public long Cx => k switch
    {
        ShapeKind.Circle => x0,
        ShapeKind.Rect => (x0 + x1) / 2,
        _ => (x0 + x1 + x2) / 3,
    };

    public long Cy => k switch
    {
        ShapeKind.Circle => y0,
        ShapeKind.Rect => (y0 + y1) / 2,
        _ => (y0 + y1 + y2) / 3,
    };

    /// Width/height (circle: the diameter), for descriptions.
    public long W => Right - Left;
    public long H => Bottom - Top;

    /// True when a circle of radius `r` at (bx, by) touches this shape.
    public readonly bool Hits(long bx, long by, long r)
    {
        switch (k)
        {
            case ShapeKind.Circle:
            {
                long dx = bx - x0, dy = by - y0, reach = r + x1;
                return dx * dx + dy * dy <= reach * reach;
            }
            case ShapeKind.Rect:
            {
                long nx = bx < x0 ? x0 : (bx > x1 ? x1 : bx);
                long ny = by < y0 ? y0 : (by > y1 ? y1 : by);
                long dx = bx - nx, dy = by - ny;
                return dx * dx + dy * dy <= r * r;
            }
            default:
                return SimMath.circle_hits_triangle(bx, by, r, x0, y0, x1, y1, x2, y2);
        }
    }

    /// Distance from (bx, by) to the shape's outline, in sub-units (0 inside), for clearances.
    public readonly long Gap(long bx, long by)
    {
        switch (k)
        {
            case ShapeKind.Circle:
            {
                double d = Math.Sqrt((double)(bx - x0) * (bx - x0) + (double)(by - y0) * (by - y0)) - x1;
                return d <= 0 ? 0 : (long)d;
            }
            case ShapeKind.Rect:
            {
                long nx = bx < x0 ? x0 : (bx > x1 ? x1 : bx);
                long ny = by < y0 ? y0 : (by > y1 ? y1 : by);
                return (long)Math.Sqrt((double)(bx - nx) * (bx - nx) + (double)(by - ny) * (by - ny));
            }
            default:
            {
                long lo = 0, hi = 1 << 20;
                if (Hits(bx, by, 0)) return 0;
                while (hi - lo > 64)
                {
                    long mid = (lo + hi) / 2;
                    if (Hits(bx, by, mid)) hi = mid; else lo = mid;
                }
                return lo;
            }
        }
    }
}

/// One part of a hazard: a saw, a blade sample, a crate, a gate half, a beam.
/// `on`: there now (a crate still waiting to drop is off). `deadly`: touching it
/// kills (coins and bumpers are not). `guess`: the model only guesses where it
/// is, because what decides it is hidden (a random column, a slide target).
public struct Body
{
    public bool on;
    public bool deadly;
    public bool guess;
    public Shape s;

    public static Body Kill(Shape s, bool on = true) => new() { on = on, deadly = true, s = s };
    public static Body Soft(Shape s, bool on = true) => new() { on = on, deadly = false, s = s };
}

/// The bird: position and speed in sub-units per substep.
public struct Bird
{
    public long x, y, vx, vy;
    public bool alive;
    public long cause;

    public readonly long dir => vx > 0 ? 1 : -1;
}
