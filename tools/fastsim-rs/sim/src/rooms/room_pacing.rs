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

    /// By rank (rule B, 2026-11-15, clear moves only): see room_pacing.gd TIERS.
    pub const TIERS: &'static [(&'static str, &'static [i64])] = &[
        ("crowded", Self::EASY), // 16 (storm 23 .. lopsided 7)
        ("belt", Self::EASY), // 21 (switchback 24 .. counter 16)
        ("crosswind", Self::EASY), // 24 (gusty 27 .. split 22)
        ("lava", Self::EASY), // 24 (rafts 32 .. lava 20)
        ("stalac", Self::EASY), // 24 (alternating 33 .. floor 16)
        ("tide", Self::EASY), // 25 (small 33 .. big 15)
        ("crates", Self::EASY), // 28 (pairs 29 .. wide 26)
        ("piston", Self::STEADY), // 29, was Middle
        ("cloud", Self::STEADY), // 30 (one 31 .. two 28)
        ("cave", Self::STEADY), // 32 (drips 36 .. fork 29)
        ("stalker", Self::STEADY), // 32, ranks Middle: kept, within the noise
        ("pegs", Self::STEADY), // 33 (drift 34 .. classic 32), ranks Middle: kept, within the noise
        ("isles", Self::MIDDLE), // 32 (classic 32 .. drifting 31), ranks Steady: kept, within the noise
        ("lockexit", Self::MIDDLE), // 32 (chain 33 .. quad 29), ranks Steady: kept, within the noise
        ("eggs", Self::MIDDLE), // 32 (classic 32 .. drifting 31), ranks Steady: kept, within the noise
        ("blink", Self::MIDDLE), // 32 (classic 34 .. fast 30)
        ("updraft", Self::MIDDLE), // 32 (gust 49 .. drift 22), was Harder
        ("hunter", Self::MIDDLE), // 34 (twin 37 .. classic 31)
        ("hearts", Self::MIDDLE), // 35 (orbit 36 .. classic 34)
        ("gifts", Self::MIDDLE), // 35 (pairs 40 .. classic 33)
        ("flip", Self::MIDDLE), // 35 (flip-flop 38 .. classic 33)
        ("crawl", Self::MIDDLE), // 36 (swarm 37 .. sprinters 36)
        ("icicle", Self::MIDDLE), // 36, was Hardest
        ("squeeze", Self::HARD), // 35 (breathing 36 .. left-only 33), ranks Middle: kept, within the noise
        ("bramble", Self::HARD), // 36 (curious 41 .. heavy 27), ranks Middle: kept, within the noise
        ("cupid", Self::HARD), // 36 (slow-volley 38 .. classic 34)
        ("pumpkin", Self::HARD), // 37 (splitting 39 .. classic 36)
        ("echo", Self::HARD), // 37 (echo 40 .. mirror 34), was Steady
        ("midnight", Self::HARD), // 38 (classic 38 .. classic 38)
        ("bubbles", Self::HARD), // 38 (spiky 44 .. classic 34), ranks Harder: kept, within the noise
        ("rain", Self::HARDER), // 37 (classic 41 .. stake 32), ranks Hard: kept, within the noise
        ("sawring", Self::HARDER), // 37 (two-rings 43 .. pair 31), ranks Hard: kept, within the noise
        ("bats", Self::HARDER), // 37 (classic 39 .. wide 36), ranks Hard: kept, within the noise
        ("swing", Self::HARDER), // 38 (big 41 .. winch 35)
        ("gates", Self::HARDER), // 39 (single 43 .. classic 35), was Steady
        ("crabs", Self::HARDER), // 39 (swarm 44 .. classic 35), was Middle
        ("bees", Self::HARDER), // 40
        ("ghostdoors", Self::HARDER), // 40 (classic 46 .. row 36)
        ("narrow", Self::HARDEST), // 42, ranks Harder: kept, within the noise
        ("beams", Self::HARDEST), // 42, was Hard
        ("pinwheel", Self::HARDEST), // 44 (rock 47 .. twin 42)
        ("buttons", Self::HARDEST), // 45 (classic 46 .. apart 44), was Middle
        ("fireworks", Self::HARDEST), // 57 (classic 59 .. double 53)
        // Bonus rooms (not ranked)
        ("slowmo", Self::BONUS),
        ("keepy", Self::BONUS),
        ("orchard", Self::BONUS),
        ("garden", Self::BONUS),
        ("countdown", Self::BONUS),
        ("beachball", Self::BONUS),
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
