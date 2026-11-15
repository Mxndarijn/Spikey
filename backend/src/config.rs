//! Settings from the environment (the Kubernetes Secret, made from `.env.<env>`;
//! every key is listed in `.env.example`).

use std::env;

#[derive(Clone, Debug)]
pub struct Config {
    /// `postgres://user:password@host:5432/db`.
    pub database_url: String,
    /// Where to listen, `0.0.0.0:8080`.
    pub listen: String,
    /// Apps older than this request protocol get 426 ("please update").
    pub min_api_version: i64,
    /// The git commit this build is from (the deploy script sets it).
    pub git_sha: String,
    /// How long an access token works, in seconds.
    pub access_ttl_s: i64,
    /// How long an unused refresh token works, in seconds.
    pub refresh_ttl_s: i64,
    /// Seconds between checker rounds (a new run also starts one at once).
    pub verify_every_s: u64,
    /// The Firebase service account JSON (or base64 of it); empty: no push.
    pub firebase_service_account: String,
    /// Seconds between push sender rounds.
    pub push_every_s: u64,
    /// Trust X-Forwarded-For (behind Traefik); off when the server faces the internet itself.
    pub trust_proxy: bool,
}

impl Config {
    pub fn from_env() -> Result<Config, String> {
        let database_url = env::var("DATABASE_URL").map_err(|_| "DATABASE_URL is not set".to_string())?;
        Ok(Config {
            database_url,
            listen: env::var("LISTEN").unwrap_or_else(|_| "0.0.0.0:8080".into()),
            min_api_version: int("MIN_API_VERSION", 1),
            git_sha: env::var("GIT_SHA").unwrap_or_else(|_| "dev".into()),
            access_ttl_s: int("ACCESS_TTL_S", 3600),
            refresh_ttl_s: int("REFRESH_TTL_S", 90 * 86400),
            verify_every_s: int("VERIFY_EVERY_S", 15) as u64,
            firebase_service_account: env::var("FIREBASE_SERVICE_ACCOUNT").unwrap_or_default(),
            push_every_s: int("PUSH_EVERY_S", 30) as u64,
            trust_proxy: env::var("TRUST_PROXY").map(|v| v != "0" && v != "false").unwrap_or(true),
        })
    }

    /// Settings for tests: everything at its default.
    pub fn for_tests(database_url: &str) -> Config {
        Config {
            database_url: database_url.into(),
            listen: "127.0.0.1:0".into(),
            min_api_version: 1,
            git_sha: "test".into(),
            access_ttl_s: 3600,
            refresh_ttl_s: 86400,
            verify_every_s: 3600,
            firebase_service_account: String::new(),
            push_every_s: 3600,
            trust_proxy: true,
        }
    }
}

fn int(name: &str, default: i64) -> i64 {
    env::var(name).ok().and_then(|v| v.trim().parse().ok()).unwrap_or(default)
}
