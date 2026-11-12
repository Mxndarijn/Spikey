//! Port of sim/rooms/room_pacing.gd (Sim/Rooms/RoomPacing.cs).
use crate::rooms::room_def::RoomDef;
use crate::rooms::seasons::Seasons;

pub struct RoomPacing;

impl RoomPacing {
    pub const EASY: &'static [i64] = &[10, 10, 60, 10, 150, 1];
    pub const STEADY: &'static [i64] = &[20, 6, 40, 10, 100, 10, 250, 2];
    pub const MIDDLE: &'static [i64] = &[30, 5, 60, 10, 160, 10, 400, 4];
    pub const HARD: &'static [i64] = &[50, 4, 100, 12, 200, 14];
    pub const HARDER: &'static [i64] = &[70, 4, 130, 14, 250, 18];
    pub const HARDEST: &'static [i64] = &[90, 4, 160, 16, 300, 20];
    pub const BONUS: &'static [i64] = &[20, 3];
    pub const SEASON_BOOST: i64 = 3;

    pub const TIERS: &'static [(&'static str, &'static [i64])] = &[
        ("lava", Self::EASY),  // 16
        ("cloud", Self::EASY),  // 25
        ("tide", Self::EASY),  // 25
        ("crosswind", Self::EASY),  // 29
        ("court", Self::EASY),  // 31
        ("belt", Self::STEADY),  // 33
        ("piston", Self::STEADY),  // 33
        ("crawl", Self::STEADY),  // 33
        ("hunter", Self::STEADY),  // 36
        ("crowded", Self::STEADY),  // 37
        ("echo", Self::STEADY),  // 38
        ("blink", Self::STEADY),  // 39
        ("flip", Self::STEADY),  // 40
        ("lockexit", Self::STEADY),  // 40
        ("isles", Self::MIDDLE),  // 42
        ("stalker", Self::MIDDLE),  // 42
        ("narrow", Self::MIDDLE),  // 43
        ("midnight", Self::MIDDLE),  // 43
        ("bubbles", Self::MIDDLE),  // 45
        ("beams", Self::MIDDLE),  // 46
        ("rain", Self::HARD),  // 49
        ("stalac", Self::HARD),  // 51
        ("gates", Self::HARD),  // 52
        ("swing", Self::HARD),  // 52
        ("double", Self::HARD),  // 51
        ("bramble", Self::HARD),  // 54
        ("crates", Self::HARD),  // 54
        ("sawring", Self::HARD),  // 55
        ("updraft", Self::HARDER),  // 57
        ("squeeze", Self::HARDER),  // 60
        ("pinwheel", Self::HARDEST),  // 66
        ("garden", Self::BONUS),  // 19
        ("orchard", Self::BONUS),  // 11
        ("keepy", Self::BONUS),  // 9
        ("slowmo", Self::BONUS),  // 7
        // Seasonal
        ("hearts", Self::EASY),  // 21
        ("crabs", Self::STEADY),  // 32
        ("eggs", Self::MIDDLE),  // 43
        ("cupid", Self::MIDDLE),  // 45
        ("icicle", Self::HARD),  // 51
        ("pumpkin", Self::HARD),  // 56
        ("bats", Self::HARDER),  // 60
        ("ghostdoors", Self::HARDER),  // 61
        ("gifts", Self::HARDEST),  // 67
        ("fireworks", Self::HARDEST),  // 70
        ("bees", Self::HARDEST),  // 72
        ("beachball", Self::BONUS),  // 14
        ("countdown", Self::BONUS),  // 9
    ];

    pub fn apply(defs: &mut Vec<RoomDef>) {
        for def in defs.iter_mut() {
            let tier = match Self::TIERS.iter().find(|t| t.0 == def.id) {
                Some(t) => t.1,
                None => continue,
            };
            let mut pace = Vec::new();
            let boost = def.season != Seasons::NONE && def.group != "bonus";
            for i in 0..tier.len() {
                let mut v = tier[i];
                if boost && i % 2 == 1 {
                    v = v * Self::SEASON_BOOST / 2;
                }
                pace.push(v);
            }
            def.from_score = pace[0];
            def.pace = pace;
        }
    }

    pub fn weight(pace: &[i64], score: i64) -> i64 {
        if pace.is_empty() || score < pace[0] {
            return 0;
        }
        let mut i = 0;
        while i + 2 < pace.len() {
            let a = pace[i];
            let b = pace[i + 2];
            if score < b {
                let wa = pace[i + 1];
                return wa + (pace[i + 3] - wa) * (score - a) / (b - a);
            }
            i += 2;
        }
        pace[pace.len() - 1]
    }
}
