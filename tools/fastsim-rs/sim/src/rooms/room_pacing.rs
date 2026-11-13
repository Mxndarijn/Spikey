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
    pub const CONTROL_FLOOR: i64 = 40;
    pub const CONTROL_ROOMS: [&'static str; 3] = ["flip", "echo", "blink"];

    pub const TIERS: &'static [(&'static str, &'static [i64])] = &[
        ("lava", Self::EASY),  // 16
        ("crowded", Self::EASY),  // 18 (Filling up, v22)
        ("cloud", Self::EASY),  // 24
        ("tide", Self::EASY),  // 26
        ("crosswind", Self::EASY),  // 31
        ("crates", Self::EASY),  // 32
        ("piston", Self::STEADY),  // 32
        ("belt", Self::STEADY),  // 33
        ("crawl", Self::STEADY),  // 34
        ("hunter", Self::STEADY),  // 37
        ("echo", Self::STEADY),  // 39
        ("flip", Self::STEADY),  // 39
        ("blink", Self::STEADY),  // 40
        ("lockexit", Self::MIDDLE),  // 41
        ("isles", Self::MIDDLE),  // 41
        ("stalker", Self::MIDDLE),  // 42
        ("bubbles", Self::MIDDLE),  // 45
        ("narrow", Self::MIDDLE),  // 47
        ("pegs", Self::HARD), // 50
        ("buttons", Self::MIDDLE), // not measured yet (provisional)
        ("rain", Self::HARD),  // 49
        ("cave", Self::HARD), // 54
        ("gates", Self::MIDDLE), // 45
        ("midnight", Self::HARD),  // 52
        ("sawring", Self::HARD),  // 54
        ("squeeze", Self::HARD),  // 56
        ("bramble", Self::HARDER),  // 56
        ("swing", Self::HARDER),  // 57
        ("stalac", Self::EASY), // 32
        ("beams", Self::HARDER),  // 61
        ("pinwheel", Self::HARDEST),  // 65
        ("updraft", Self::HARDEST),  // 74
        ("slowmo", Self::BONUS),  // 9
        ("keepy", Self::BONUS),  // 10
        ("orchard", Self::BONUS),  // 12
        ("garden", Self::BONUS),  // 19
        // Seasonal
        ("hearts", Self::EASY),  // 20
        ("crabs", Self::STEADY),  // 32
        ("eggs", Self::MIDDLE),  // 42
        ("cupid", Self::MIDDLE),  // 45
        ("gifts", Self::HARD),  // 49
        ("icicle", Self::HARD),  // 50
        ("pumpkin", Self::HARD),  // 55
        ("ghostdoors", Self::HARDER),  // 58
        ("bats", Self::HARDER),  // 60
        ("fireworks", Self::HARDEST),  // 70
        ("bees", Self::HARDEST),  // 72
        ("countdown", Self::BONUS),  // 10
        ("beachball", Self::BONUS),  // 14
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
            if Self::CONTROL_ROOMS.contains(&def.id) && pace[0] < Self::CONTROL_FLOOR {
                pace = Self::floored(&pace, Self::CONTROL_FLOOR);
            }
            def.from_score = pace[0];
            def.pace = pace;
        }
    }

    pub fn floored(pace: &[i64], floor: i64) -> Vec<i64> {
        let mut out_ = vec![floor, Self::weight(pace, floor)];
        let mut i = 0;
        while i < pace.len() {
            if pace[i] > floor {
                out_.push(pace[i]);
                out_.push(pace[i + 1]);
            }
            i += 2;
        }
        out_
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
