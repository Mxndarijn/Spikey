//! Battle (migrations/0110_battles.sql) against a real Postgres, through the
//! HTTP routes: invites and random battles, turns, blind rounds, the copied
//! taps check, lost runs, resign, close, nudges and the alert outbox.
//!
//! Needs DATABASE_URL (tools/backend_test.ps1 starts a throwaway Postgres in
//! Docker). Without it every test here says so and passes. The checker is
//! stood in for by setting a run's status: the replay check itself is tested
//! in api.rs.

use std::net::SocketAddr;
use std::sync::Arc;

use axum::body::Body;
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{Request, StatusCode};
use axum::Router;
use flapjaw_server::app::{router, AppState};
use flapjaw_server::config::Config;
use flapjaw_server::db;
use flapjaw_server::limits::Limits;
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tokio::sync::Notify;
use tower::ServiceExt;

async fn setup() -> Option<(Router, PgPool)> {
    let Ok(url) = std::env::var("DATABASE_URL") else {
        eprintln!("DATABASE_URL not set: skipped (tools/backend_test.ps1 runs these)");
        return None;
    };
    let pool = db::connect(&url).await.expect("database");
    db::migrate(&pool).await.expect("migrations");
    let state = Arc::new(AppState {
        pool: pool.clone(),
        config: Config::for_tests(&url),
        limits: Limits::new(),
        new_run: Arc::new(Notify::new()),
    });
    let app = router(state).layer(MockConnectInfo(SocketAddr::from(([10, 0, 0, 2], 1234))));
    Some((app, pool))
}

/// Each player's own address (from their token), unless a test gave two the same.
fn address_of(token: &str) -> String {
    if let Some(ip) = SAME_ADDRESS.lock().unwrap().get(token) {
        return ip.clone();
    }
    let b = flapjaw_server::auth::sha256(token);
    format!("10.{}.{}.{}", b[0], b[1], b[2])
}

static SAME_ADDRESS: std::sync::Mutex<std::collections::BTreeMap<String, String>> =
    std::sync::Mutex::new(std::collections::BTreeMap::new());

async fn call(app: &Router, path: &str, token: &str, body: Value) -> (StatusCode, Value) {
    let req = Request::post(path)
        .header("content-type", "application/json")
        .header("x-flapjaw-api", "1")
        .header("x-flapjaw-gameplay", sim::sim_config::SimConfig::GAMEPLAY_VERSION.to_string())
        .header("x-forwarded-for", address_of(token))
        .header("authorization", format!("Bearer {token}"));
    let res = app.clone().oneshot(req.body(Body::from(body.to_string())).unwrap()).await.unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

/// A signed-in phone: (player id, access token).
async fn player(app: &Router) -> (String, String) {
    let key = flapjaw_server::auth::new_token("Fj-");
    let req = Request::post("/v1/auth/anon")
        .header("content-type", "application/json")
        .header("x-flapjaw-api", "1")
        .body(Body::from(json!({"device_key": key}).to_string()))
        .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let s: Value = serde_json::from_slice(&bytes).unwrap();
    (s["player_id"].as_str().unwrap().into(), s["access_token"].as_str().unwrap().into())
}

async fn ok(app: &Router, op: &str, token: &str, body: Value) -> Value {
    let (status, v) = call(app, &format!("/v1/{op}"), token, body).await;
    assert_eq!(status, StatusCode::OK, "{op}: {v}");
    v
}

fn name(n: &str) -> Value {
    json!(n)
}

/// Starts and sends a run of `round` with this score and taps.
async fn play(app: &Router, token: &str, who: &str, battle: i64, round: i64, score: i64, taps: Value) -> Value {
    let start =
        ok(app, "battle_start_run", token, json!({"p_battle": battle, "p_round": round, "p_gameplay_version": 1}))
            .await;
    assert_eq!(start["round"], json!(round), "{start}");
    ok(
        app,
        "battle_submit",
        token,
        json!({
            "p_battle": battle, "p_round": round, "p_name": name(who), "p_flyer": "buzz",
            "p_score": score, "p_gameplay_version": 1, "p_seed": start["seed"], "p_taps": taps,
            "p_season": start["season"], "p_coins": 0, "p_end_tick": 100,
        }),
    )
    .await
}

/// The checker's verdict on every pending battle run of this battle.
async fn check_all(pool: &PgPool, battle: i64) {
    sqlx::query(
        "update public.runs set status = 'ok', checked_at = now()
         where status = 'pending' and id in (
           select run_a from public.battle_rounds where battle = $1
           union select run_b from public.battle_rounds where battle = $1)",
    )
    .bind(battle)
    .execute(pool)
    .await
    .unwrap();
}

async fn new_invite(app: &Router, token: &str, who: &str) -> (i64, String) {
    let v = ok(
        app,
        "battle_create",
        token,
        json!({"p_name": who, "p_flyer": "buzz", "p_opponent": "invite", "p_gameplay_version": 1}),
    )
    .await;
    let code = v["code"].as_str().unwrap().to_string();
    assert_eq!(code.len(), 6, "{v}");
    assert!(code.chars().all(|c| "ABCDEFGHJKMNPQRSTUVWXYZ23456789".contains(c)), "no look-alikes: {code}");
    (v["battle"].as_i64().unwrap(), code)
}

#[tokio::test]
async fn a_battle_from_invite_to_the_last_round() {
    let Some((app, pool)) = setup().await else { return };
    let (_, ta) = player(&app).await;
    let (_, tb) = player(&app).await;
    let (battle, code) = new_invite(&app, &ta, "AdaA").await;
    // A short battle: first to 2.
    sqlx::query("update public.battles set first_to = 2 where id = $1").bind(battle).execute(&pool).await.unwrap();
    let v = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!(v["turn"], json!("me"), "the starter opens round 1: {v}");
    assert_eq!(v["play"], json!({"round": 1, "role": "open"}));
    let v = play(&app, &ta, "AdaA", battle, 1, 10, json!([5, 30, 60])).await;
    assert_eq!(v["turn"], Value::Null, "nobody's turn while the friend hasn't joined: {v}");
    assert_eq!(v["status"], json!("waiting"));
    // The friend joins with the code, typed in lower case with a dash.
    let typed = format!("{}-{}", &code[..3], &code[3..]).to_lowercase();
    let v = ok(&app, "battle_join", &tb, json!({"p_code": typed, "p_name": "MiraB", "p_flyer": "buzz"})).await;
    assert_eq!(v["status"], json!("open"));
    assert_eq!(v["opponent"]["name"], json!("AdaA"));
    assert_eq!(v["play"]["role"], json!("answer"));
    assert_eq!(v["play"]["rival_pending"], json!(true), "the rival's run is not checked yet: {v}");
    check_all(&pool, battle).await;
    let v = ok(&app, "battle_get", &tb, json!({"p_battle": battle})).await;
    assert_eq!(v["play"]["rival"]["score"], json!(10), "the checked run is the ghost: {v}");
    assert_eq!(v["play"]["rival"]["taps"], json!([5, 30, 60]));
    // B answers round 1 (wins it), then opens round 2.
    play(&app, &tb, "MiraB", battle, 1, 12, json!([7, 31])).await;
    check_all(&pool, battle).await;
    let v = ok(&app, "battle_get", &tb, json!({"p_battle": battle})).await;
    assert_eq!(v["wins_me"], json!(1), "{v}");
    assert_eq!(v["play"], json!({"round": 2, "role": "open"}), "the answerer opens the next round");
    assert_eq!(v["rounds"][0]["winner"], json!("me"));
    play(&app, &tb, "MiraB", battle, 2, 3, json!([9])).await;
    check_all(&pool, battle).await;
    let v = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!(v["turn"], json!("me"), "{v}");
    assert_eq!(v["play"]["round"], json!(2));
    play(&app, &ta, "AdaA", battle, 2, 8, json!([4])).await;
    check_all(&pool, battle).await;
    // 1-1 now: round 3 decides it and is blind for both.
    let v = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!((v["wins_me"].clone(), v["wins_them"].clone()), (json!(1), json!(1)), "{v}");
    assert_eq!(v["play"], json!({"round": 3, "role": "open"}), "A opens odd rounds");
    play(&app, &ta, "AdaA", battle, 3, 20, json!([3])).await;
    check_all(&pool, battle).await;
    let v = ok(&app, "battle_get", &tb, json!({"p_battle": battle})).await;
    assert_eq!(v["play"]["blind"], json!(true), "{v}");
    assert!(v["play"].get("rival").is_none(), "no ghost in a blind round: {v}");
    assert_eq!(v["rounds"][2]["their_score"], Value::Null, "nor the score");
    play(&app, &tb, "MiraB", battle, 3, 15, json!([2])).await;
    check_all(&pool, battle).await;
    let v = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!(v["status"], json!("finished"), "{v}");
    assert_eq!(v["winner"], json!("me"));
    assert_eq!(v["ended_by"], json!("played"));
    assert_eq!(v["rounds"][2]["their_score"], json!(15), "shown once played");
    let v = ok(&app, "battle_get", &tb, json!({"p_battle": battle})).await;
    assert_eq!(v["winner"], json!("them"));
    // Both players are told how it ended.
    let ended: i64 = sqlx::query_scalar("select count(*) from public.battle_alerts where ref = $1")
        .bind(format!("end:{battle}"))
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(ended, 2);
    // The rematch: the one who asks opens round 1.
    let v = ok(&app, "battle_rematch", &tb, json!({"p_battle": battle})).await;
    assert_eq!(v["turn"], json!("me"), "{v}");
    assert_eq!(v["play"], json!({"round": 1, "role": "open"}));
    assert_eq!(v["opponent"]["name"], json!("AdaA"));
}

#[tokio::test]
async fn only_the_player_whose_turn_it_is_plays() {
    let Some((app, _)) = setup().await else { return };
    let (_, ta) = player(&app).await;
    let (_, tb) = player(&app).await;
    let (_, tc) = player(&app).await;
    let (battle, code) = new_invite(&app, &ta, "TurnA").await;
    ok(&app, "battle_join", &tb, json!({"p_code": code, "p_name": "TurnB", "p_flyer": "buzz"})).await;
    let body = json!({"p_battle": battle, "p_round": 1, "p_gameplay_version": 1});
    let (status, _) = call(&app, "/v1/battle_start_run", &tb, body.clone()).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "B can't open round 1");
    let (status, _) = call(&app, "/v1/battle_get", &tc, json!({"p_battle": battle})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "a stranger sees nothing");
    let (status, _) =
        call(&app, "/v1/battle_join", &tc, json!({"p_code": code, "p_name": "TurnC", "p_flyer": "buzz"})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "a code works once");
    let (status, _) =
        call(&app, "/v1/battle_join", &tc, json!({"p_code": "ZZZZZZ", "p_name": "TurnC", "p_flyer": "buzz"})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "an unknown code");
}

#[tokio::test]
async fn a_copied_run_is_rejected_and_loses_the_round() {
    let Some((app, pool)) = setup().await else { return };
    let (_, ta) = player(&app).await;
    let (_, tb) = player(&app).await;
    let (battle, code) = new_invite(&app, &ta, "CopyA").await;
    let taps: Vec<i64> = (0..60).map(|i| 10 + i * 17).collect();
    play(&app, &ta, "CopyA", battle, 1, 30, json!(taps)).await;
    ok(&app, "battle_join", &tb, json!({"p_code": code, "p_name": "CopyB", "p_flyer": "buzz"})).await;
    check_all(&pool, battle).await;
    // The same taps, each one tick later.
    let copied: Vec<i64> = taps.iter().map(|t| t + 1).collect();
    play(&app, &tb, "CopyB", battle, 1, 30, json!(copied)).await;
    let (status, reason): (String, String) = sqlx::query_as(
        "select r.status, r.reason from public.runs r join public.battle_rounds b on b.run_b = r.id
         where b.battle = $1 and b.number = 1",
    )
    .bind(battle)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(status, "rejected");
    assert!(reason.contains("copied"), "{reason}");
    let v = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!(v["rounds"][0]["winner"], json!("me"), "a rejected run counts as 0: {v}");
    let honest: bool = sqlx::query_scalar("select public.spikey_taps_copied($1, $2)")
        .bind(json!((0..60).map(|i| 12 + i * 23).collect::<Vec<i64>>()))
        .bind(json!(taps))
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(!honest, "an honest run that taps at its own times is fine");
}

#[tokio::test]
async fn a_run_started_twice_counts_as_zero() {
    let Some((app, pool)) = setup().await else { return };
    let (_, ta) = player(&app).await;
    let (battle, _) = new_invite(&app, &ta, "LostA").await;
    let body = json!({"p_battle": battle, "p_round": 1, "p_gameplay_version": 1});
    let first = ok(&app, "battle_start_run", &ta, body.clone()).await;
    assert!(first["seed"].as_i64().is_some(), "{first}");
    // The phone was lost mid-run; the new one starts again.
    let again = ok(&app, "battle_start_run", &ta, body).await;
    assert_eq!(again["lost"], json!(true), "one try: {again}");
    let lost: bool = sqlx::query_scalar("select lost_a from public.battle_rounds where battle = $1 and number = 1")
        .bind(battle)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(lost);
}

#[tokio::test]
async fn random_battles_meet_a_waiting_one() {
    let Some((app, pool)) = setup().await else { return };
    let (_, ta) = player(&app).await;
    let (_, tb) = player(&app).await;
    // A version no other test uses, so only these two meet.
    let version = 900 + (rand_byte() as i64);
    let body =
        |who: &str| json!({"p_name": who, "p_flyer": "buzz", "p_opponent": "random", "p_gameplay_version": version});
    let v = ok(&app, "battle_create", &ta, body("RandA")).await;
    let battle = v["battle"].as_i64().unwrap();
    assert_eq!(v["random"], json!(true));
    let start =
        ok(&app, "battle_start_run", &ta, json!({"p_battle": battle, "p_round": 1, "p_gameplay_version": version}))
            .await;
    ok(
        &app,
        "battle_submit",
        &ta,
        json!({
            "p_battle": battle, "p_round": 1, "p_name": "RandA", "p_flyer": "buzz", "p_score": 9,
            "p_gameplay_version": version, "p_seed": start["seed"], "p_taps": [1, 2],
            "p_season": start["season"],
        }),
    )
    .await;
    // Not checked yet: B starts a battle of their own.
    let v = ok(&app, "battle_create", &tb, body("RandB")).await;
    assert_ne!(v["battle"].as_i64().unwrap(), battle, "only a checked run is offered");
    ok(&app, "battle_close", &tb, json!({"p_battle": v["battle"]})).await;
    check_all(&pool, battle).await;
    let v = ok(&app, "battle_create", &tb, body("RandB")).await;
    assert_eq!(v["battle"].as_i64().unwrap(), battle, "B takes A's waiting battle: {v}");
    assert_eq!(v["play"]["rival"]["score"], json!(9));
    let joined: i64 = sqlx::query_scalar("select count(*) from public.battle_alerts where ref = $1")
        .bind(format!("joined:{battle}"))
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(joined, 1, "A hears about it");
}

fn rand_byte() -> u8 {
    let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().subsec_nanos();
    (t % 97) as u8
}

#[tokio::test]
async fn resign_close_and_nudge() {
    let Some((app, pool)) = setup().await else { return };
    let (_, ta) = player(&app).await;
    let (pb, tb) = player(&app).await;
    let (battle, code) = new_invite(&app, &ta, "NudgeA").await;
    play(&app, &ta, "NudgeA", battle, 1, 5, json!([1])).await;
    ok(&app, "battle_join", &tb, json!({"p_code": code, "p_name": "NudgeB", "p_flyer": "buzz"})).await;
    let v = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!(v["can_nudge"], json!(true), "{v}");
    assert_eq!(v["can_close"], json!(false), "not before 7 days without a move");
    let (status, _) = call(&app, "/v1/battle_close", &ta, json!({"p_battle": battle})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    ok(&app, "battle_nudge", &ta, json!({"p_battle": battle})).await;
    let v = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!(v["can_nudge"], json!(false), "once a day");
    let nudges: i64 = sqlx::query_scalar(
        "select count(*) from public.battle_alerts where player_id = $1::uuid and ref like 'nudge:%'",
    )
    .bind(&pb)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(nudges, 1);
    // Eight days without a move: A may close it, with no result.
    sqlx::query("update public.battles set last_move_at = now() - interval '8 days' where id = $1")
        .bind(battle)
        .execute(&pool)
        .await
        .unwrap();
    let v = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!(v["can_close"], json!(true), "{v}");
    let (_, bv) = call(&app, "/v1/battle_get", &tb, json!({"p_battle": battle})).await;
    assert_eq!(bv["can_close"], json!(false), "not the one whose turn it is");
    let v = ok(&app, "battle_close", &ta, json!({"p_battle": battle})).await;
    assert_eq!(v["status"], json!("closed"));
    assert_eq!(v["winner"], Value::Null, "no result");
    // Resign: the other player wins.
    let (battle, code) = new_invite(&app, &ta, "NudgeA").await;
    ok(&app, "battle_join", &tb, json!({"p_code": code, "p_name": "NudgeB", "p_flyer": "buzz"})).await;
    let v = ok(&app, "battle_resign", &tb, json!({"p_battle": battle})).await;
    assert_eq!((v["status"].clone(), v["winner"].clone()), (json!("finished"), json!("them")), "{v}");
    assert_eq!(v["ended_by"], json!("resigned"));
    let (status, _) = call(&app, "/v1/battle_resign", &tb, json!({"p_battle": battle})).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "only once");
}

#[tokio::test]
async fn reminders_go_out_by_day_and_through_the_sender() {
    let Some((app, pool)) = setup().await else { return };
    let (_, ta) = player(&app).await;
    let (pb, tb) = player(&app).await;
    let (battle, code) = new_invite(&app, &ta, "RemA").await;
    play(&app, &ta, "RemA", battle, 1, 5, json!([1])).await;
    ok(&app, "battle_join", &tb, json!({"p_code": code, "p_name": "RemB", "p_flyer": "buzz"})).await;
    // B's phone, set to a clock where it is the middle of the day.
    let utc_hour: i32 = sqlx::query_scalar("select extract(hour from now() at time zone 'UTC')::integer")
        .fetch_one(&pool)
        .await
        .unwrap();
    let offset = ((13 - utc_hour) * 60).clamp(-720, 840);
    ok(
        &app,
        "register_push",
        &tb,
        json!({"p_token": "tok-battle-1234", "p_platform": "android", "p_utc_offset_min": offset}),
    )
    .await;
    sqlx::query("update public.battles set last_move_at = now() - interval '26 hours' where id = $1")
        .bind(battle)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("select public.spikey_battle_reminders()").execute(&pool).await.unwrap();
    sqlx::query("select public.spikey_battle_reminders()").execute(&pool).await.unwrap();
    let refs: Vec<String> =
        sqlx::query_scalar("select ref from public.battle_alerts where player_id = $1::uuid and ref like 'remind:%'")
            .bind(&pb)
            .fetch_all(&pool)
            .await
            .unwrap();
    assert_eq!(refs, vec![format!("remind:{battle}:1")], "one nudge after a day, not two");
    let pending: Value = sqlx::query_scalar("select public.worker_pending_alerts(500)").fetch_one(&pool).await.unwrap();
    let mine: Vec<&Value> = pending.as_array().unwrap().iter().filter(|a| a["token"] == "tok-battle-1234").collect();
    assert!(!mine.is_empty(), "{pending}");
    assert!(mine.iter().all(|a| a["line"] == "battle" && a["id"].as_i64().unwrap() < 0));
    assert!(mine.iter().all(|a| a["battle"] == json!(battle.to_string())), "each says its battle: {pending}");
    let results: Vec<Value> = mine.iter().map(|a| json!({"id": a["id"], "status": "sent"})).collect();
    let n: i32 = sqlx::query_scalar("select public.worker_mark_alerts($1)")
        .bind(Value::Array(results))
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(n as usize, mine.len());
}

#[tokio::test]
async fn no_more_than_twenty_open_battles() {
    let Some((app, pool)) = setup().await else { return };
    let (pa, ta) = player(&app).await;
    new_invite(&app, &ta, "ManyA").await;
    sqlx::query(
        "insert into public.battles (player_a, gameplay_version)
         select $1::uuid, 1 from generate_series(1, 19)",
    )
    .bind(&pa)
    .execute(&pool)
    .await
    .unwrap();
    let (status, v) = call(
        &app,
        "/v1/battle_create",
        &ta,
        json!({"p_name": "ManyA", "p_flyer": "buzz", "p_opponent": "invite", "p_gameplay_version": 1}),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{v}");
    let list = ok(&app, "battle_list", &ta, json!({})).await;
    assert_eq!(list["battles"].as_array().unwrap().len(), 20);
    assert_eq!(list["limits"]["open"], json!(20));
}

/// A battle run goes through the server's real replay check, and a checked
/// round is decided by the trigger.
#[tokio::test]
async fn battle_runs_go_through_the_replay_check() {
    let Some((app, pool)) = setup().await else { return };
    let (_, ta) = player(&app).await;
    let (_, tb) = player(&app).await;
    let (battle, code) = new_invite(&app, &ta, "CheckA").await;
    let path = format!(
        "{}/../tests/replay/golden/g{}_seed_2024.json",
        env!("CARGO_MANIFEST_DIR"),
        sim::sim_config::SimConfig::GAMEPLAY_VERSION
    );
    let g: Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let version = g["gameplay_version"].as_i64().unwrap();
    ok(&app, "battle_start_run", &ta, json!({"p_battle": battle, "p_round": 1, "p_gameplay_version": version})).await;
    // This round deals the golden replay's map.
    sqlx::query("update public.battle_rounds set seed = $2, season = $3, gameplay_version = $4 where battle = $1")
        .bind(battle)
        .bind(g["seed"].as_i64().unwrap())
        .bind(g["season"].as_i64().unwrap() as i32)
        .bind(version as i32)
        .execute(&pool)
        .await
        .unwrap();
    ok(
        &app,
        "battle_submit",
        &ta,
        json!({
            "p_battle": battle, "p_round": 1, "p_name": "CheckA", "p_flyer": "buzz", "p_score": g["score"],
            "p_gameplay_version": version, "p_seed": g["seed"], "p_taps": g["taps"], "p_season": g["season"],
            "p_coins": g["coins"], "p_end_tick": g["end_tick"],
        }),
    )
    .await;
    // The replay check on this run only (other tests' runs are stand-ins).
    let row: Value = sqlx::query_scalar(
        "select jsonb_build_object('id', r.id, 'gameplay_version', r.gameplay_version, 'seed', r.seed,
           'season', r.season, 'taps', r.taps, 'revives', r.revives, 'score', r.score, 'coins', r.coins,
           'end_tick', r.end_tick, 'day', r.day::text)
         from public.runs r join public.battle_rounds b on b.run_a = r.id where b.battle = $1",
    )
    .bind(battle)
    .fetch_one(&pool)
    .await
    .unwrap();
    let verdict = flapjaw_server::verify::check(&flapjaw_server::verify::Run::from_json(&row)).unwrap();
    sqlx::query("select public.worker_record_results($1)")
        .bind(json!([{"id": verdict.id, "status": verdict.status, "reason": verdict.reason}]))
        .execute(&pool)
        .await
        .unwrap();
    let status: String = sqlx::query_scalar(
        "select r.status from public.runs r join public.battle_rounds b on b.run_a = r.id where b.battle = $1",
    )
    .bind(battle)
    .fetch_one(&pool)
    .await
    .unwrap();
    let today = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let in_play = flapjaw_server::verify::seasons_around(&today).contains(&g["season"].as_i64().unwrap());
    if !in_play {
        return;
    }
    assert_eq!(status, "ok", "the honest battle run passes");
    let v = ok(&app, "battle_join", &tb, json!({"p_code": code, "p_name": "CheckB", "p_flyer": "buzz"})).await;
    assert_eq!(v["play"]["rival"]["score"], g["score"], "its replay is B's ghost: {v}");
    // B's phone is lost mid-run: the round goes to A once the trigger decides it.
    let body = json!({"p_battle": battle, "p_round": 1, "p_gameplay_version": version});
    ok(&app, "battle_start_run", &tb, body.clone()).await;
    ok(&app, "battle_start_run", &tb, body).await;
    let v = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!(v["rounds"][0]["winner"], json!("me"), "{v}");
}
