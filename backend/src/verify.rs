//! The replay check: every submitted run is played again with the sim and its
//! claimed score, coins and end tick compared, the way server/run_checker.gd
//! does it (RunChecker, Replay.verify), here with the Rust sim
//! (tools/fastsim-rs/sim, which the check holds tick for tick to sim/).
//!
//! `ok` and `outdated` are written at once. A run the Rust check rejects stays
//! `pending` and goes to `backend.godot_queue`: headless Godot (the godot-check
//! CronJob, server/verify_batch.gd) has the last word, so a difference between
//! the two sims can never hide an honest score. Runs from a newer gameplay
//! version than this server stay pending until it has that sim.

use chrono::{Datelike, Duration, NaiveDate};
use serde_json::{json, Value};
use sim::game_sim::GameSim;
use sim::rooms::seasons::Seasons;
use sim::sim_config::SimConfig;
use sqlx::PgPool;

pub const OK: &str = "ok";
pub const REJECTED: &str = "rejected";
pub const OUTDATED: &str = "outdated";

/// One stored run, as worker_pending_runs gives it.
#[derive(Clone, Debug, Default)]
pub struct Run {
    pub id: i64,
    pub gameplay_version: i64,
    pub seed: i64,
    pub season: Option<i64>,
    pub taps: Option<Vec<i64>>,
    pub revives: Option<Vec<i64>>,
    pub score: i64,
    pub coins: Option<i64>,
    pub end_tick: Option<i64>,
    pub day: String,
}

/// A run's verdict: `None` when the run is newer than this checker.
#[derive(Clone, Debug, PartialEq)]
pub struct Verdict {
    pub id: i64,
    pub status: &'static str,
    pub reason: String,
}

fn ints(v: Option<&Value>) -> Option<Vec<i64>> {
    match v {
        None | Some(Value::Null) => Some(vec![]),
        Some(Value::Array(a)) => a.iter().map(|x| x.as_f64().filter(|f| f.fract() == 0.0).map(|f| f as i64)).collect(),
        _ => None,
    }
}

impl Run {
    pub fn from_json(v: &Value) -> Run {
        let i = |k: &str| v.get(k).and_then(|x| x.as_f64()).map(|f| f as i64);
        Run {
            id: i("id").unwrap_or(0),
            gameplay_version: i("gameplay_version").unwrap_or(-1),
            seed: i("seed").unwrap_or(0),
            season: i("season"),
            taps: ints(v.get("taps")),
            revives: ints(v.get("revives")),
            score: i("score").unwrap_or(-1),
            coins: i("coins"),
            end_tick: i("end_tick"),
            day: v.get("day").and_then(|d| d.as_str()).unwrap_or("").to_string(),
        }
    }
}

/// SeasonCalendar.for_date (meta/season_calendar.gd).
pub fn season_for(month: u32, day: u32) -> i64 {
    match (month, day) {
        (10, _) => Seasons::HALLOWEEN,
        (12, _) => Seasons::WINTER,
        (1, d) if d <= 7 => Seasons::NEW_YEAR,
        (2, d) if d <= 14 => Seasons::VALENTINE,
        (3, _) | (4, _) => Seasons::SPRING,
        (7, _) | (8, _) => Seasons::SUMMER,
        _ => Seasons::NONE,
    }
}

/// The seasons in play the day before, on and after `day` ("YYYY-MM-DD"):
/// phones use their own date, which can be a day off. Empty for a bad day.
pub fn seasons_around(day: &str) -> Vec<i64> {
    let Ok(d) = NaiveDate::parse_from_str(day, "%Y-%m-%d") else {
        return vec![];
    };
    let mut out = vec![];
    for off in [-1, 0, 1] {
        let x = d + Duration::days(off);
        let s = season_for(x.month(), x.day());
        if !out.contains(&s) {
            out.push(s);
        }
    }
    out
}

/// Replay.simulate: the sim with these taps until it ends, a death at the next
/// revive tick revived.
pub fn simulate(seed: i64, taps: &[i64], season: i64, revives: &[i64]) -> GameSim {
    let mut sim = GameSim::with(seed, season, -1, "");
    let (mut next, mut next_revive) = (0usize, 0usize);
    while sim.state.tick < SimConfig::MAX_TICKS {
        if sim.is_over() {
            let due = next_revive < revives.len() && revives[next_revive] == sim.state.tick;
            if !due || !sim.revive() {
                break;
            }
            next_revive += 1;
        }
        let tap = next < taps.len() && taps[next] == sim.state.tick;
        if tap {
            next += 1;
        }
        sim.step(tap);
    }
    sim
}

fn ascending(list: &[i64]) -> bool {
    list.iter().enumerate().all(|(i, t)| *t >= 0 && (i == 0 || *t > list[i - 1]))
}

/// Replay.verify for one season: "" when it matches, else why not.
pub fn verify(run: &Run, taps: &[i64], season: i64, revives: &[i64]) -> String {
    if !ascending(taps) {
        return "taps must be ascending and non-negative".into();
    }
    if revives.len() as i64 > SimConfig::MAX_REVIVES {
        return "too many revives".into();
    }
    if !ascending(revives) {
        return "revives must be ascending and non-negative".into();
    }
    if !(Seasons::NONE..Seasons::COUNT).contains(&season) {
        return format!("unknown season {season}");
    }
    let sim = simulate(run.seed, taps, season, revives);
    let (score, coins, tick) = (sim.state.score, sim.state.coins, sim.state.tick);
    if !sim.is_over() {
        "run did not end".into()
    } else if sim.state.revives != revives.len() as i64 {
        "revive without a death".into()
    } else if taps.last().is_some_and(|t| *t >= tick) {
        "taps after death".into()
    } else if score != run.score {
        format!("score mismatch (claimed {}, replayed {score})", run.score)
    } else if run.coins.is_some_and(|c| c != coins) {
        format!("coins mismatch (claimed {}, replayed {coins})", run.coins.unwrap())
    } else if run.end_tick.is_some_and(|t| t != tick) {
        "end_tick mismatch".into()
    } else {
        String::new()
    }
}

/// RunChecker.check: the verdict for one stored run.
pub fn check(run: &Run) -> Option<Verdict> {
    let v = |status: &'static str, reason: String| Some(Verdict { id: run.id, status, reason });
    if run.gameplay_version > SimConfig::GAMEPLAY_VERSION {
        return None;
    }
    if run.gameplay_version < SimConfig::GAMEPLAY_VERSION {
        return v(
            OUTDATED,
            format!("gameplay_version {}, checker has {}", run.gameplay_version, SimConfig::GAMEPLAY_VERSION),
        );
    }
    let Some(taps) = &run.taps else {
        return v(REJECTED, "invalid taps".into());
    };
    let Some(revives) = &run.revives else {
        return v(REJECTED, "invalid revives".into());
    };
    let allowed = seasons_around(&run.day);
    if allowed.is_empty() {
        return v(REJECTED, format!("unknown day '{}'", run.day));
    }
    let candidates = match run.season {
        Some(s) if !allowed.contains(&s) => {
            return v(REJECTED, format!("season {s} not in play on {}", run.day));
        }
        Some(s) => vec![s],
        None => allowed,
    };
    let mut reason = String::new();
    for season in candidates {
        reason = verify(run, taps, season, revives);
        if reason.is_empty() {
            return v(OK, String::new());
        }
    }
    v(REJECTED, reason)
}

/// One checker round: every pending run not waiting for Godot. Returns how
/// many it decided.
pub async fn round(pool: &PgPool) -> Result<usize, sqlx::Error> {
    let pending: Value = sqlx::query_scalar(
        "select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(public.worker_pending_runs(200)) r
         where not exists (select 1 from backend.godot_queue q where q.run_id = (r ->> 'id')::bigint)",
    )
    .fetch_one(pool)
    .await?;
    let runs: Vec<Run> = pending.as_array().map(|a| a.iter().map(Run::from_json).collect()).unwrap_or_default();
    if runs.is_empty() {
        return Ok(0);
    }
    let verdicts = tokio::task::spawn_blocking(move || runs.iter().filter_map(check).collect::<Vec<_>>())
        .await
        .unwrap_or_default();
    let mut decided = vec![];
    for v in &verdicts {
        if v.status == REJECTED {
            tracing::info!("run {} rejected by the Rust check ({}), Godot will confirm", v.id, v.reason);
            sqlx::query("insert into backend.godot_queue (run_id, rust_reason) values ($1, $2) on conflict do nothing")
                .bind(v.id)
                .bind(&v.reason)
                .execute(pool)
                .await?;
        } else {
            decided.push(json!({"id": v.id, "status": v.status, "reason": v.reason}));
        }
    }
    if !decided.is_empty() {
        sqlx::query("select public.worker_record_results($1)").bind(Value::Array(decided)).execute(pool).await?;
    }
    Ok(verdicts.len())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A golden replay of the sim's current gameplay version ("seed_11.json" ->
    /// tests/replay/golden/g<version>_seed_11.json), so a version bump needs no edit here.
    fn golden(name: &str) -> (Run, Vec<i64>, Vec<i64>) {
        let path =
            format!("{}/../tests/replay/golden/g{}_{name}", env!("CARGO_MANIFEST_DIR"), SimConfig::GAMEPLAY_VERSION);
        let v: Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        let mut run = Run::from_json(&v);
        run.day = "2026-11-15".into();
        let (taps, revives) = (run.taps.clone().unwrap(), run.revives.clone().unwrap());
        (run, taps, revives)
    }

    #[test]
    fn the_golden_replays_pass() {
        for name in ["seed_2024.json", "seed_11.json", "revived_seed_2024.json"] {
            let (run, _, _) = golden(name);
            assert_eq!(check(&run).unwrap().status, OK, "{name}: {:?}", check(&run));
        }
    }

    #[test]
    fn a_changed_score_or_tap_is_rejected() {
        let (mut run, _, _) = golden("seed_2024.json");
        run.score += 1;
        let v = check(&run).unwrap();
        assert_eq!(v.status, REJECTED);
        assert!(v.reason.starts_with("score mismatch"), "{}", v.reason);
        let (mut run, _, _) = golden("seed_2024.json");
        run.taps.as_mut().unwrap().pop();
        assert_eq!(check(&run).unwrap().status, REJECTED, "one tap less plays out differently");
    }

    #[test]
    fn versions_decide_first() {
        let (mut run, _, _) = golden("seed_11.json");
        run.gameplay_version = SimConfig::GAMEPLAY_VERSION - 1;
        assert_eq!(check(&run).unwrap().status, OUTDATED);
        run.gameplay_version = SimConfig::GAMEPLAY_VERSION + 1;
        assert!(check(&run).is_none(), "newer than this server: stays pending");
    }

    #[test]
    fn the_season_must_be_in_play_that_day() {
        let (mut run, _, _) = golden("seed_11.json");
        run.season = Some(Seasons::HALLOWEEN);
        let v = check(&run).unwrap();
        assert_eq!(v.status, REJECTED);
        assert!(v.reason.contains("not in play"), "{}", v.reason);
        run.day = "nonsense".into();
        assert!(check(&run).unwrap().reason.starts_with("unknown day"));
    }

    #[test]
    fn seasons_match_the_calendar() {
        assert_eq!(seasons_around("2026-10-15"), vec![Seasons::HALLOWEEN]);
        assert_eq!(seasons_around("2026-11-01"), vec![Seasons::HALLOWEEN, Seasons::NONE]);
        assert_eq!(seasons_around("2027-01-07"), vec![Seasons::NEW_YEAR, Seasons::NONE]);
        assert_eq!(season_for(2, 14), Seasons::VALENTINE);
        assert_eq!(season_for(2, 15), Seasons::NONE);
    }

    #[test]
    fn broken_taps_are_rejected() {
        let mut run = Run { gameplay_version: SimConfig::GAMEPLAY_VERSION, day: "2026-11-15".into(), ..Run::default() };
        run.taps = None;
        run.revives = Some(vec![]);
        assert_eq!(check(&run).unwrap().reason, "invalid taps");
        let v = Run::from_json(&json!({"taps": [1, "x"]}));
        assert!(v.taps.is_none());
        let v = Run::from_json(&json!({"taps": [3, 2]}));
        assert!(!ascending(v.taps.as_ref().unwrap()));
    }
}
