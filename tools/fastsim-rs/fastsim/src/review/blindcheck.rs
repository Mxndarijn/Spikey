//! Port of RL/Review.cs `blindcheck`: `rl review blindcheck`, blind_copy must wipe what it
//! scrambles. For many states in every room: a copy scrambled with seed A must equal a copy that
//! was first scrambled with seed B and then with A (same checksum). If not, some scrambled value
//! still depends on the hidden truth. It can't find a hidden field nobody scrambles: that list is
//! kept by hand (bot-review.md).
use sim::prelude::*;

use super::room_name;
use crate::bots::{BlindPlanner, SimBots};

/// Ppo.rooms(): rooms a practice run can start in: every room but the open start room.
pub fn ppo_rooms() -> Vec<i64> {
    let all = RoomCatalog::all();
    (0..all.len() as i64).filter(|&i| i != RoomCatalog::first_index()).collect()
}

fn blind(sim: &GameSim, seed: i64) -> GameSim {
    BlindPlanner::blind_copy(sim, SimRng::new(seed), -1, 0, -1, false, false)
}

pub fn blindcheck(seeds: i32) -> i32 {
    let (mut states, mut bad) = (0i64, 0i64);
    // C# Dictionary<string, int>: keys in first-insertion order.
    let mut where_: Vec<(String, i64)> = Vec::new();
    let mut rooms = ppo_rooms();
    rooms.push(-1);
    for room in rooms {
        for i in 0..seeds as i64 {
            let mut sim = GameSim::with(31 * i + 3, Seasons::NONE, room, "");
            let mut rng = SimRng::new(i + 1);
            let mut t = 0;
            while t < 900 && !sim.is_over() {
                let tap = SimBots::gap_seeker(&sim, &mut rng);
                sim.step(tap);
                let skip = t % 15 != 0 || sim.is_over();
                t += 1;
                if skip {
                    continue;
                }
                states += 1;
                let a = blind(&sim, 111).checksum();
                let b = blind(&blind(&sim, 222), 111).checksum();
                if a == b {
                    continue;
                }
                bad += 1;
                let id = room_name(&sim);
                match where_.iter_mut().find(|w| w.0 == id) {
                    Some(w) => w.1 += 1,
                    None => where_.push((id, 1)),
                }
            }
        }
    }
    println!(
        "blindcheck: {} states, {} where a second scramble changed the copy{}",
        states,
        bad,
        if bad > 0 {
            format!(": {}", where_.iter().map(|w| format!("{} {}", w.0, w.1)).collect::<Vec<_>>().join(", "))
        } else {
            String::new()
        }
    );
    if bad == 0 {
        0
    } else {
        1
    }
}
