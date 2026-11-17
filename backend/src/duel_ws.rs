//! Duel over a WebSocket (docs/DUEL_MODE.md, section 3): `GET /v1/duel/ws`.
//! One socket per phone, JSON text messages. The hub pairs players (a random
//! queue by gameplay version, or a 6-letter invite code) and runs each match as
//! a task holding both players' Rust sims (duel.rs): it relays each player's
//! taps to the other, steps both sims, decides rounds and the match, and
//! stores the result for the wins boards (duel_record).
//!
//! Phone -> server
//!   {"t": "hello", "token": "...", "version": 25, "name": "Ada", "flyer": "buzz"}
//!   {"t": "queue"} | {"t": "invite"} | {"t": "join", "code": "KD7WQ3"} | {"t": "cancel"}
//!   {"t": "ticks", "tick": 360, "taps": [341, 352]}   about every 100 ms in a round
//!   {"t": "leave"}   gives the match up            {"t": "rematch"}
//! Server -> phone
//!   welcome, queued, invite {code}, matched {match, rival, random},
//!   countdown {round, seed, season, start_in_ms, wins}, resume {round, seed,
//!   season, elapsed_ms, last_tick, wins} (back after a lost connection),
//!   rival {tick, taps}, rival_down {score, why}, round_over {round, winner,
//!   my_score, their_score, wins}, match_over {winner, ended_by, wins},
//!   rival_gone, rival_back, rematch_asked, error {message}
//!
//! Rejoin: a phone whose socket dropped says hello again and is put back in
//! its match (resume). In a round it has the 5 s grace of the clock check;
//! between rounds 30 s, then the match is forfeited.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{ConnectInfo, State};
use axum::http::HeaderMap;
use axum::response::Response;
use chrono::Datelike;
use serde_json::{json, Value};
use sqlx::PgPool;
use tokio::sync::{mpsc, Mutex};
use uuid::Uuid;

use crate::app::Shared;
use crate::auth;
use crate::duel::{Down, Ending, Match, RoundResult};

pub type Tx = mpsc::UnboundedSender<String>;

/// The countdown before a round, ms.
pub const COUNTDOWN_MS: i64 = 3000;
/// The pause between rounds, ms.
pub const BETWEEN_MS: i64 = 5000;
/// Away between rounds (or in the countdown) longer than this: forfeit.
pub const AWAY_MS: i64 = 30_000;
/// After a match: how long a rematch can be asked for.
pub const REMATCH_MS: i64 = 20_000;
/// An invite code lasts this long.
pub const INVITE_MS: u64 = 10 * 60 * 1000;
pub const LOOP_MS: u64 = 100;

#[derive(Clone, Copy, Debug, PartialEq)]
enum Phase {
    Countdown,
    Live,
    Between,
    Over,
}

struct Player {
    id: Uuid,
    info: Value,
    tx: Option<Tx>,
    gone_at: Option<i64>,
}

struct Live {
    id: u64,
    players: [Player; 2],
    core: Match,
    phase: Phase,
    /// When the current phase ends (ms since `epoch`).
    until: i64,
    random: bool,
    version: i64,
    epoch: Instant,
    rematch: [bool; 2],
    told_down: [bool; 2],
    recorded: bool,
}

impl Live {
    fn now(&self) -> i64 {
        self.epoch.elapsed().as_millis() as i64
    }

    fn send(&self, who: usize, msg: Value) {
        if let Some(tx) = &self.players[who].tx {
            let _ = tx.send(msg.to_string());
        }
    }

    fn wins_for(&self, who: usize) -> Value {
        json!([self.core.wins[who], self.core.wins[1 - who]])
    }

    fn start_round(&mut self) {
        let seed = rand::random::<u32>() as i64;
        let today = chrono::Utc::now();
        let season = crate::verify::season_for(today.month(), today.day());
        let start = self.now() + COUNTDOWN_MS;
        let n = self.core.start_round(seed, season, start);
        self.phase = Phase::Countdown;
        self.until = start;
        self.told_down = [false, false];
        for who in 0..2 {
            self.send(
                who,
                json!({"t": "countdown", "round": n, "seed": seed, "season": season,
                       "start_in_ms": COUNTDOWN_MS, "wins": self.wins_for(who)}),
            );
        }
    }

    fn who(&self, player: Uuid) -> Option<usize> {
        self.players.iter().position(|p| p.id == player)
    }

    /// Where a phone that just came back picks up.
    fn resume(&self, who: usize) {
        self.send(
            who,
            json!({"t": "matched", "match": self.id, "rival": self.players[1 - who].info, "random": self.random}),
        );
        if let Some(r) = self.core.rounds.last() {
            if r.result.is_none() {
                self.send(
                    who,
                    json!({"t": "resume", "round": r.number, "seed": r.seed, "season": r.season,
                           "elapsed_ms": self.now() - r.start_ms, "last_tick": r.sides[who].last_t,
                           "wins": self.wins_for(who)}),
                );
            }
        }
    }
}

/// A phone waiting for a rival (the queue or an invite).
struct Waiting {
    player: Uuid,
    info: Value,
    version: i64,
    tx: Tx,
    at: Instant,
}

#[derive(Default)]
struct HubInner {
    queue: Vec<Waiting>,
    invites: HashMap<String, Waiting>,
    live: HashMap<Uuid, Arc<Mutex<Live>>>,
    next_id: u64,
}

/// Every Duel in this server process.
#[derive(Default)]
pub struct Hub {
    inner: Mutex<HubInner>,
}

pub fn hub() -> &'static Hub {
    static HUB: OnceLock<Hub> = OnceLock::new();
    HUB.get_or_init(Hub::default)
}

/// An invite code: 6 characters with no look-alikes.
pub fn new_code() -> String {
    const ABC: &[u8] = b"ABCDEFGHJKMNPQRSTUVWXYZ23456789";
    (0..6).map(|_| ABC[rand::random::<usize>() % ABC.len()] as char).collect()
}

pub async fn upgrade(
    ws: WebSocketUpgrade,
    State(s): State<Shared>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
) -> Response {
    let ip = crate::app::client_ip(&s, &headers, Some(addr));
    ws.on_upgrade(move |socket| connection(socket, s, ip))
}

async fn connection(socket: WebSocket, s: Shared, ip: String) {
    use futures_util::{SinkExt, StreamExt};
    let (mut sink, mut stream) = socket.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<String>();
    let writer = tokio::spawn(async move {
        while let Some(text) = rx.recv().await {
            if sink.send(Message::Text(text.into())).await.is_err() {
                break;
            }
        }
        let _ = sink.close().await;
    });
    let mut me: Option<(Uuid, Value, i64)> = None;
    while let Some(Ok(msg)) = stream.next().await {
        let Message::Text(text) = msg else {
            if matches!(msg, Message::Close(_)) {
                break;
            }
            continue;
        };
        let Ok(v) = serde_json::from_str::<Value>(&text) else { continue };
        let kind = v["t"].as_str().unwrap_or("");
        if kind == "hello" {
            match hello(&s, &v, &tx).await {
                Ok(who) => {
                    // The wins boards' shared-IP rule (only a salted hash is kept).
                    crate::app::note_ip(&s.pool, who.0, &ip).await;
                    me = Some(who)
                }
                Err(e) => {
                    let _ = tx.send(json!({"t": "error", "message": e}).to_string());
                    break;
                }
            }
            continue;
        }
        let Some((player, info, version)) = me.clone() else {
            let _ = tx.send(json!({"t": "error", "message": "say hello first"}).to_string());
            continue;
        };
        handle(&s.pool, player, &info, version, kind, &v, &tx).await;
    }
    if let Some((player, _, _)) = me {
        gone(player, &tx).await;
    }
    drop(tx);
    let _ = writer.await;
}

/// Signs the phone in (its access token) and puts it back in its match if it has one.
async fn hello(s: &Shared, v: &Value, tx: &Tx) -> Result<(Uuid, Value, i64), String> {
    let mut headers = HeaderMap::new();
    let token = v["token"].as_str().unwrap_or("");
    headers.insert("authorization", format!("Bearer {token}").parse().map_err(|_| "bad token".to_string())?);
    let player = auth::player_of(&s.pool, &headers).await.map_err(|e| e.code.to_string())?;
    let version = v["version"].as_i64().unwrap_or(0);
    if version < sim::sim_config::SimConfig::GAMEPLAY_VERSION {
        return Err(crate::error::UPDATE_REQUIRED.to_string());
    }
    let mut db = s.pool.begin().await.map_err(|e| e.to_string())?;
    sqlx::query("select set_config('request.jwt.claim.sub', $1, true)")
        .bind(player.to_string())
        .execute(&mut *db)
        .await
        .map_err(|e| e.to_string())?;
    sqlx::query("select public.spikey_ensure_player($1, $2)")
        .bind(v["name"].as_str())
        .bind(v["flyer"].as_str())
        .execute(&mut *db)
        .await
        .map_err(|e| e.to_string())?;
    let info: Value = sqlx::query_scalar("select public.duel_player($1)")
        .bind(player)
        .fetch_one(&mut *db)
        .await
        .map_err(|e| e.to_string())?;
    db.commit().await.map_err(|e| e.to_string())?;
    let _ = tx.send(json!({"t": "welcome", "player": player}).to_string());
    let live = hub().inner.lock().await.live.get(&player).cloned();
    if let Some(live) = live {
        let mut l = live.lock().await;
        if let Some(who) = l.who(player) {
            l.players[who].tx = Some(tx.clone());
            l.players[who].gone_at = None;
            l.resume(who);
            l.send(1 - who, json!({"t": "rival_back"}));
        }
    }
    Ok((player, info, version))
}

async fn handle(pool: &PgPool, player: Uuid, info: &Value, version: i64, kind: &str, v: &Value, tx: &Tx) {
    let say = |m: Value| {
        let _ = tx.send(m.to_string());
    };
    match kind {
        "queue" | "invite" | "join" => {
            let mut h = hub().inner.lock().await;
            if h.live.contains_key(&player) {
                say(json!({"t": "error", "message": "already in a duel"}));
                return;
            }
            h.queue.retain(|w| w.player != player && !w.tx.is_closed());
            h.invites.retain(|_, w| {
                w.player != player && !w.tx.is_closed() && w.at.elapsed().as_millis() < INVITE_MS as u128
            });
            let me = Waiting { player, info: info.clone(), version, tx: tx.clone(), at: Instant::now() };
            match kind {
                "queue" => {
                    if let Some(i) = h.queue.iter().position(|w| w.version == version && w.player != player) {
                        let other = h.queue.remove(i);
                        start_match(&mut h, pool, other, me, true);
                    } else {
                        h.queue.push(me);
                        say(json!({"t": "queued"}));
                    }
                }
                "invite" => {
                    let code = new_code();
                    h.invites.insert(code.clone(), me);
                    say(json!({"t": "invite", "code": code}));
                }
                _ => {
                    let code: String = v["code"]
                        .as_str()
                        .unwrap_or("")
                        .to_uppercase()
                        .chars()
                        .filter(|c| c.is_ascii_alphanumeric())
                        .collect();
                    match h.invites.remove(&code) {
                        Some(host) if host.player != player && host.version == version => {
                            start_match(&mut h, pool, host, me, false);
                        }
                        Some(host) => {
                            let wrong = if host.player == player {
                                "that's your own code"
                            } else {
                                "your friend has another version of the game"
                            };
                            h.invites.insert(code, host);
                            say(json!({"t": "error", "message": wrong}));
                        }
                        None => say(json!({"t": "error", "message": "unknown code"})),
                    }
                }
            }
        }
        "cancel" => {
            let mut h = hub().inner.lock().await;
            h.queue.retain(|w| w.player != player);
            h.invites.retain(|_, w| w.player != player);
        }
        "ticks" | "leave" | "rematch" => {
            let live = hub().inner.lock().await.live.get(&player).cloned();
            let Some(live) = live else { return };
            let mut l = live.lock().await;
            let Some(who) = l.who(player) else { return };
            match kind {
                "ticks" => {
                    if l.phase != Phase::Live {
                        return;
                    }
                    let t = v["tick"].as_i64().unwrap_or(-1);
                    let taps: Vec<i64> =
                        v["taps"].as_array().map(|a| a.iter().filter_map(|x| x.as_i64()).collect()).unwrap_or_default();
                    let now = l.now();
                    let fed = match l.core.current() {
                        Some(r) => r.feed(who, t, &taps, now),
                        None => return,
                    };
                    match fed {
                        Ok(()) => l.send(1 - who, json!({"t": "rival", "tick": t, "taps": taps})),
                        Err(e) => say(json!({"t": "error", "message": e})),
                    }
                }
                "leave" => {
                    l.core.leave(who);
                }
                _ => {
                    if l.phase == Phase::Over {
                        l.rematch[who] = true;
                        l.send(1 - who, json!({"t": "rematch_asked"}));
                    }
                }
            }
        }
        _ => say(json!({"t": "error", "message": format!("unknown message {kind}")})),
    }
}

/// Pairs two waiting phones and starts their match's task.
fn start_match(h: &mut HubInner, pool: &PgPool, a: Waiting, b: Waiting, random: bool) {
    h.next_id += 1;
    let live = Live {
        id: h.next_id,
        players: [
            Player { id: a.player, info: a.info, tx: Some(a.tx), gone_at: None },
            Player { id: b.player, info: b.info, tx: Some(b.tx), gone_at: None },
        ],
        core: Match::new(),
        phase: Phase::Countdown,
        until: 0,
        random,
        version: a.version,
        epoch: Instant::now(),
        rematch: [false, false],
        told_down: [false, false],
        recorded: false,
    };
    for who in 0..2 {
        live.send(
            who,
            json!({"t": "matched", "match": live.id, "rival": live.players[1 - who].info, "random": random}),
        );
    }
    let live = Arc::new(Mutex::new(live));
    h.live.insert(a.player, live.clone());
    h.live.insert(b.player, live.clone());
    tokio::spawn(run_match(live, pool.clone()));
}

/// The match's own loop: the countdown, the clock check, deciding rounds, the
/// pause between them, forfeits, the result and the rematch.
async fn run_match(live: Arc<Mutex<Live>>, pool: PgPool) {
    live.lock().await.start_round();
    loop {
        tokio::time::sleep(Duration::from_millis(LOOP_MS)).await;
        let mut l = live.lock().await;
        if !step(&mut l, &pool) {
            let ids = [l.players[0].id, l.players[1].id];
            let again = l.rematch == [true, true];
            let senders: Vec<Option<Tx>> = l.players.iter().map(|p| p.tx.clone()).collect();
            let infos: Vec<Value> = l.players.iter().map(|p| p.info.clone()).collect();
            let (random, version) = (l.random, l.version);
            drop(l);
            let mut h = hub().inner.lock().await;
            for id in ids {
                if h.live.get(&id).is_some_and(|m| Arc::ptr_eq(m, &live)) {
                    h.live.remove(&id);
                }
            }
            if again {
                if let (Some(a), Some(b)) = (senders[0].clone(), senders[1].clone()) {
                    let now = Instant::now();
                    let wa = Waiting { player: ids[0], info: infos[0].clone(), version, tx: a, at: now };
                    let wb = Waiting { player: ids[1], info: infos[1].clone(), version, tx: b, at: now };
                    start_match(&mut h, &pool, wa, wb, random);
                }
            }
            return;
        }
    }
}

/// One loop step; false when the match task is done.
fn step(l: &mut Live, pool: &PgPool) -> bool {
    let now = l.now();
    if l.phase != Phase::Over {
        for who in 0..2 {
            // Away too long outside a round: the match is lost.
            if let Some(at) = l.players[who].gone_at {
                if l.phase != Phase::Live && now - at > AWAY_MS {
                    l.core.leave(who);
                }
            }
        }
    }
    if l.core.ending.is_some() && l.phase != Phase::Over {
        finish(l, pool);
        return true;
    }
    match l.phase {
        Phase::Countdown => {
            if now >= l.until {
                l.phase = Phase::Live;
            }
        }
        Phase::Live => {
            let Some(r) = l.core.current() else { return true };
            r.tick_clock(now);
            let downs: Vec<(Option<Down>, i64)> = r.sides.iter().map(|s| (s.down, s.score())).collect();
            for who in 0..2 {
                if let (Some(why), score) = downs[who] {
                    if !l.told_down[who] {
                        l.told_down[who] = true;
                        // A phone that stopped (the app in the background, the
                        // connection) hears it too: it may not know.
                        if why == Down::FellBehind {
                            l.send(who, json!({"t": "you_down", "score": score, "why": "left_app"}));
                        }
                        let why = format!("{why:?}").to_lowercase();
                        l.send(1 - who, json!({"t": "rival_down", "score": score, "why": why}));
                    }
                }
            }
            let Some(r) = l.core.current() else { return true };
            if let Some(result) = r.judge() {
                let (number, scores) = (r.number, [r.sides[0].score(), r.sides[1].score()]);
                l.core.round_settled(result);
                for who in 0..2 {
                    let winner = match result {
                        RoundResult::Win(w) if w == who => "me",
                        RoundResult::Win(_) => "them",
                        RoundResult::Draw => "draw",
                    };
                    l.send(
                        who,
                        json!({"t": "round_over", "round": number, "winner": winner,
                               "my_score": scores[who], "their_score": scores[1 - who],
                               "wins": l.wins_for(who)}),
                    );
                }
                if l.core.ending.is_some() {
                    finish(l, pool);
                } else {
                    l.phase = Phase::Between;
                    l.until = now + BETWEEN_MS;
                }
            }
        }
        Phase::Between => {
            if now >= l.until {
                l.start_round();
            }
        }
        Phase::Over => {
            if l.rematch == [true, true] || now >= l.until {
                return false;
            }
        }
    }
    true
}

/// The match ended: tell both phones and store the result.
fn finish(l: &mut Live, pool: &PgPool) {
    let now = l.now();
    l.phase = Phase::Over;
    l.until = now + REMATCH_MS;
    let ending = l.core.ending.unwrap_or(Ending::Draw);
    let (winner, ended_by) = match ending {
        Ending::Won(w) => (Some(w), "played"),
        Ending::Left(w) => (Some(1 - w), "left"),
        Ending::Draw => (None, "played"),
    };
    for who in 0..2 {
        let w = match winner {
            Some(x) if x == who => "me",
            Some(_) => "them",
            None => "draw",
        };
        l.send(who, json!({"t": "match_over", "winner": w, "ended_by": ended_by, "wins": l.wins_for(who)}));
    }
    if l.recorded {
        return;
    }
    l.recorded = true;
    let (a, b) = (l.players[0].id, l.players[1].id);
    let winner_id = winner.map(|w| l.players[w].id);
    let rounds = l.core.rounds_played() as i32;
    let (random, wins, version) = (l.random, l.core.wins, l.version);
    let pool = pool.clone();
    tokio::spawn(async move {
        let res = sqlx::query("select public.duel_record($1, $2, $3, $4, $5, $6, $7, $8, $9)")
            .bind(a)
            .bind(b)
            .bind(winner_id)
            .bind(ended_by)
            .bind(rounds)
            .bind(random)
            .bind(wins[0] as i32)
            .bind(wins[1] as i32)
            .bind(version as i32)
            .execute(&pool)
            .await;
        if let Err(e) = res {
            tracing::warn!("couldn't store a duel's result: {e}");
        }
    });
}

/// A socket closed: out of the queue and invites; in a match, the rival hears.
async fn gone(player: Uuid, tx: &Tx) {
    let live = {
        let mut h = hub().inner.lock().await;
        h.queue.retain(|w| w.player != player);
        h.invites.retain(|_, w| w.player != player);
        h.live.get(&player).cloned()
    };
    if let Some(live) = live {
        let mut l = live.lock().await;
        if let Some(who) = l.who(player) {
            // Only this socket's own: a phone that came back on a new socket stays.
            if l.players[who].tx.as_ref().is_some_and(|t| t.same_channel(tx)) {
                l.players[who].tx = None;
                l.players[who].gone_at = Some(l.now());
                l.send(1 - who, json!({"t": "rival_gone"}));
            }
        }
    }
}
