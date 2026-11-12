namespace FastSim;

/// What a player can and cannot know about a boss (research/planner-review/07-bosses.md).
/// Every attack is drawn from `Boss.seed` (hidden). The attack being told is on
/// screen (dashed rows, a dashed slam line or lane, a marked crate column, a
/// dashed landing ring); every later one is not. Tool only.
public static class BossBlind
{
    /// Replaces the boss's seed in a planner's copy. The attack on screen stays
    /// as it is, unless `unseen` (its tell appeared less than a reaction ago):
    /// then it is a guess too.
    public static void scramble(Boss b, SimRng own, bool unseen)
    {
        long old = b.seed;
        b.seed = own.next_u32();
        switch (b)
        {
            case BossWatcher w:
                // `lit` is kept for the cycle it was drawn in (on screen while it warns and fires).
                if (unseen && w.beam == BossWatcher.Beam.WARN && w._lit_k >= 0) w.lit = w.lit_rows(w.phase, w._lit_k);
                break;
            case BossCrusher cr:
            {
                long c = cr.clock();
                if (c >= 0 && cr.phase == 1 && !unseen)
                {
                    // The slam height is drawn again every step from the seed: keep the one on screen.
                    long k = c / BossCrusher.CYCLE;
                    long want = slam_with(cr, old, k);
                    for (int i = 0; i < 64 && cr.slam_of(k) != want; i++) cr.seed = own.next_u32();
                    if (cr.slam_of(k) != want) cr.seed = old;
                }
                if (unseen && cr.telling && cr.phase > 1 && cr.lane_from >= 0) cr.lane_to = cr._next_lane(cr._k);
                if (unseen)
                    for (int i = 0; i < 2; i++)
                        if (cr.crate[i] == BossCrusher.Crate.MARK)
                            cr.crate_x[i] = BossCrusher.COLUMN_X0 + own.next_below(BossCrusher.COLUMNS) * BossCrusher.COLUMN_STEP;
                break;
            }
            case BossSaw s:
                if (unseen && s.telling && s._k >= 0)
                    s.to_y = s.phase == 2 ? BossSaw.RING_YS[s.draw(s._k, 2) % 2] : s.hop_to(s.from_y, s._k);
                break;
        }
    }

    static long slam_with(BossCrusher cr, long seed, long k)
    {
        long keep = cr.seed;
        cr.seed = seed;
        long v = cr.slam_of(k);
        cr.seed = keep;
        return v;
    }

    /// Changes whenever a new tell starts (what a player has to take in).
    public static long tell_key(Boss b)
    {
        long h = SimHash.mix(SimHash.SEED, b.phase);
        switch (b)
        {
            case BossWatcher w:
                h = SimHash.mix(h, w.phase != 2 ? w._lit_k : -1);
                h = SimHash.mix(h, w.dart == BossWatcher.Dart.NONE ? -1 : w.dart_lane * 4 + w.dart_side);
                break;
            case BossCrusher cr:
            {
                long c = cr.clock();
                h = SimHash.mix(h, c >= 0 && cr.phase == 1 ? c / BossCrusher.CYCLE : cr._k);
                for (int i = 0; i < 2; i++) h = SimHash.mix(h, cr.crate[i] == BossCrusher.Crate.NONE ? -1 : cr.crate_x[i]);
                break;
            }
            case BossSaw s:
                h = SimHash.mix(h, s._k);
                break;
        }
        return SimHash.mix(h, b.down_at >= 0 ? 1 : 0);
    }
}
