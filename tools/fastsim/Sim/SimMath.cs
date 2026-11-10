namespace FastSim;

public static class SimMath
{
    public static long cross(long ax, long ay, long bx, long by, long px, long py)
        => (bx - ax) * (py - ay) - (by - ay) * (px - ax);

    public static bool point_in_triangle(long px, long py, long ax, long ay, long bx, long by, long cx, long cy)
    {
        long d1 = cross(ax, ay, bx, by, px, py);
        long d2 = cross(bx, by, cx, cy, px, py);
        long d3 = cross(cx, cy, ax, ay, px, py);
        bool has_neg = d1 < 0 || d2 < 0 || d3 < 0;
        bool has_pos = d1 > 0 || d2 > 0 || d3 > 0;
        return !(has_neg && has_pos);
    }

    public static bool circle_hits_segment(long px, long py, long r, long ax, long ay, long bx, long by)
    {
        long dx = bx - ax;
        long dy = by - ay;
        long fx = px - ax;
        long fy = py - ay;
        long len2 = dx * dx + dy * dy;
        long t = fx * dx + fy * dy;
        long r2 = r * r;
        if (len2 == 0 || t <= 0) return fx * fx + fy * fy <= r2;
        if (t >= len2)
        {
            long gx = px - bx;
            long gy = py - by;
            return gx * gx + gy * gy <= r2;
        }
        long c = dx * fy - dy * fx;
        return c * c <= r2 * len2;
    }

    public static bool circle_hits_triangle(long px, long py, long r, long ax, long ay, long bx, long by, long cx, long cy)
    {
        if (point_in_triangle(px, py, ax, ay, bx, by, cx, cy)) return true;
        return circle_hits_segment(px, py, r, ax, ay, bx, by)
            || circle_hits_segment(px, py, r, bx, by, cx, cy)
            || circle_hits_segment(px, py, r, cx, cy, ax, ay);
    }
}
