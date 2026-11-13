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
    pub const OTHERS_SCALE: i64 = 5;
    pub const SEASON_BOOST: i64 = 3;
    pub const CONTROL_FLOOR: i64 = 40;
    pub const CONTROL_ROOMS: [&'static str; 3] = ["flip", "echo", "blink"];

    pub const TIERS: &'static [(&'static str, &'static [i64])] = &[
        ("crosswind", Self::EASY), // 14
        ("crowded", Self::EASY), // 15
        ("lava", Self::EASY), // 19
        ("tide", Self::EASY), // 23
        ("belt", Self::EASY), // 25
        ("stalac", Self::EASY), // 25 (alternating 40)
        ("crates", Self::EASY), // 30
        ("echo", Self::STEADY), // 39
        ("cloud", Self::STEADY), // 44 (bots clear it like Steady: skill 26 / 35; analytic 54 / 59)
        ("stalker", Self::STEADY), // 34 (slide at half speed; 41 before)
        ("piston", Self::MIDDLE), // 41 (generated)
        ("lockexit", Self::MIDDLE), // 42 (trio 38, quad 43, chain 45, since classic and orbit went)
        ("blink", Self::MIDDLE), // 43
        ("crawl", Self::MIDDLE), // 44
        ("pegs", Self::MIDDLE), // 44
        ("isles", Self::MIDDLE), // 45
        ("gates", Self::MIDDLE), // 46 (single 53, classic 39)
        ("flip", Self::MIDDLE), // 47
        ("hunter", Self::MIDDLE), // 60 (human bots 78-90, analytic 33-37: one step until a playtest)
        ("bubbles", Self::HARD), // 50
        ("buttons", Self::HARD), // 50 (classic, slim, apart 50; measured on its own at 162437a, 72 entries)
        ("midnight", Self::HARD), // 51
        ("squeeze", Self::HARD), // 52
        ("beams", Self::HARD), // 53
        ("bramble", Self::HARD), // 54 (heavy 34 .. curious 77, still being fixed)
        ("cave", Self::STEADY), // 32 (drips 40, bats 32 with one slow bat, fork 24)
        ("rain", Self::HARDER), // 57
        ("swing", Self::HARDER), // 58
        ("sawring", Self::HARDER), // 59
        ("updraft", Self::HARDER), // 55 (gust 90, chimney 69; gust still being fixed)
        ("narrow", Self::HARDEST), // 70
        ("pinwheel", Self::HARDEST), // 70
        ("slowmo", Self::BONUS), // 0
        ("keepy", Self::BONUS), // 4
        ("orchard", Self::BONUS), // 6
        ("garden", Self::BONUS), // 14
        // Seasonal
        ("eggs", Self::MIDDLE), // 42
        ("crabs", Self::MIDDLE), // 41
        ("hearts", Self::MIDDLE), // 44
        ("gifts", Self::MIDDLE), // 48
        ("pumpkin", Self::HARD), // 56
        ("cupid", Self::HARD), // 63 (human bots 54-97, analytic 43-51: one step until a playtest)
        ("bats", Self::HARDER), // 58
        ("ghostdoors", Self::HARDER), // 59
        ("bees", Self::HARDER), // 62
        ("icicle", Self::HARDEST), // 65
        ("fireworks", Self::HARDEST), // 86
        ("countdown", Self::BONUS), // 4
        ("beachball", Self::BONUS), // 1
    ];

    pub fn apply(defs: &mut Vec<RoomDef>) {
        for def in defs.iter_mut() {
            let tier = match Self::TIERS.iter().find(|t| t.0 == def.id) {
                Some(t) => t.1,
                None => continue,
            };
            let mut pace = Vec::new();
            let boost = def.season != Seasons::NONE && def.group != "bonus";
            let scale = if tier == Self::BONUS { 1 } else { Self::OTHERS_SCALE };
            for i in 0..tier.len() {
                let mut v = tier[i];
                if i % 2 == 1 {
                    v *= scale;
                }
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
