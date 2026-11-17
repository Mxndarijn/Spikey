//! The Battle bots (migrations/0112_battle_bots.sql, src/bot.rs) against a real
//! Postgres: a bot takes a random battle after the bot wait, plays its turns
//! through the battle operations, never counts on the wins boards, and its
//! level follows the player.
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
use flapjaw_server::bot::{self, BotRun};
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
    let app = router(state).layer(MockConnectInfo(SocketAddr::from(([10, 0, 0, 4], 1234))));
    Some((app, pool))
}

async fn call(app: &Router, path: &str, token: &str, body: Value) -> (StatusCode, Value) {
    let req = Request::post(path)
        .header("content-type", "application/json")
        .header("x-flapjaw-api", "1")
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

fn stand_in(seed: i64, _season: i64, level: i64, bot_seed: i64) -> Result<BotRun, String> {
    assert!((1..=8).contains(&level), "level {level}");
    let _ = (seed, bot_seed);
    Ok(BotRun { taps: vec![5, 40], score: 1, coins: 0, end_tick: 90 })
}

async fn due_now(pool: &PgPool, battle: i64) {
    sqlx::query("update public.battles set bot_due_at = now() where id = $1 and bot_due_at is not null")
        .bind(battle)
        .execute(pool)
        .await
        .unwrap();
}

async fn a_plays(app: &Router, pool: &PgPool, ta: &str, battle: i64, round: i64, version: i64) {
    let start =
        ok(app, "battle_start_run", ta, json!({"p_battle": battle, "p_round": round, "p_gameplay_version": version}))
            .await;
    ok(
        app,
        "battle_submit",
        ta,
        json!({
            "p_battle": battle, "p_round": round, "p_name": "BotFan", "p_flyer": "buzz", "p_score": 50,
            "p_gameplay_version": version, "p_seed": start["seed"], "p_taps": [1, 2, 3],
            "p_season": start["season"], "p_coins": 0, "p_end_tick": 100,
        }),
    )
    .await;
    check_all(pool, battle).await;
}

#[tokio::test]
async fn a_bot_takes_a_waiting_battle_and_plays_its_turns() {
    let Some((app, pool)) = setup().await else { return };
    sqlx::query("select public.worker_set_bot_wait(0)").execute(&pool).await.unwrap();
    let (pa, ta) = player(&app).await;
    let version = sim::sim_config::SimConfig::GAMEPLAY_VERSION;
    let v = ok(
        &app,
        "battle_create",
        &ta,
        json!({"p_name": "BotFan", "p_flyer": "buzz", "p_opponent": "random", "p_gameplay_version": version}),
    )
    .await;
    let battle = v["battle"].as_i64().unwrap();
    sqlx::query("update public.battles set first_to = 3 where id = $1").bind(battle).execute(&pool).await.unwrap();
    a_plays(&app, &pool, &ta, battle, 1, version).await;
    sqlx::query("update public.runs set checked_at = now() - interval '1 minute' where player_id = $1::uuid")
        .bind(&pa)
        .execute(&pool)
        .await
        .unwrap();
    let runner: &bot::Runner = &stand_in;
    bot::round(&pool, runner).await.unwrap();
    let v = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!(v["status"], json!("open"), "a bot took it: {v}");
    assert_eq!(v["opponent"]["bot"], json!(true));
    let bot_name = v["opponent"]["name"].as_str().unwrap().to_string();
    for word in ["Good", "Beginner", "Expert", "Beast", "Normal", "Level"] {
        assert!(!bot_name.contains(word), "no skill words in a bot's name: {bot_name}");
    }
    assert_eq!(v["turn"], json!("them"));
    assert_eq!(v["can_close"], json!(true), "a battle with a bot can be closed any time");
    assert_eq!(v["can_nudge"], json!(false), "nobody to nudge");
    let alerts: i64 = sqlx::query_scalar("select count(*) from public.battle_alerts where ref = $1")
        .bind(format!("joined:{battle}"))
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(alerts, 1);
    // Not due yet: the bot waits a few minutes like a person.
    let (_, sent) = bot::round(&pool, runner).await.unwrap();
    assert_eq!(sent, 0);
    due_now(&pool, battle).await;
    let (_, sent) = bot::round(&pool, runner).await.unwrap();
    assert_eq!(sent, 2, "it answers round 1 and opens round 2");
    check_all(&pool, battle).await;
    let v = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!(v["wins_me"], json!(1), "{v}");
    assert_eq!(v["play"]["round"], json!(2));
    assert_eq!(v["play"]["rival"]["score"], json!(1), "the bot's run is A's ghost");
    // A wins 3-0: the bot plays a level stronger next time.
    a_plays(&app, &pool, &ta, battle, 2, version).await;
    a_plays(&app, &pool, &ta, battle, 3, version).await;
    due_now(&pool, battle).await;
    bot::round(&pool, runner).await.unwrap();
    check_all(&pool, battle).await;
    let v = ok(&app, "battle_get", &ta, json!({"p_battle": battle})).await;
    assert_eq!((v["status"].clone(), v["winner"].clone()), (json!("finished"), json!("me")), "{v}");
    let (counted, reason): (bool, String) =
        sqlx::query_as("select counted, reason from public.match_results where battle = $1")
            .bind(battle)
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!((counted, reason.as_str()), (false, "bot"), "bot battles never count");
    let (start, now): (i32, i32) = sqlx::query_as(
        "select b.bot_level, s.level from public.battles b, public.battle_bot_skill s
         where b.id = $1 and s.player_id = $2::uuid",
    )
    .bind(battle)
    .bind(&pa)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(now, (start + 1).min(8), "won 3-0: one level up");
    // Bots are off below 0: nothing is taken.
    sqlx::query("select public.worker_set_bot_wait(-1)").execute(&pool).await.unwrap();
    let (assigned, _) = bot::round(&pool, runner).await.unwrap();
    assert_eq!(assigned, 0);
    sqlx::query("select public.worker_set_bot_wait(600)").execute(&pool).await.unwrap();
}
