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
    /// Invite links on Android: the app's signing certificates' SHA-256
    /// (ANDROID_CERT_SHA256, comma-separated; unset or blank: the upload key,
    /// UPLOAD_CERT_SHA256). With Play App Signing, list Google's key too.
    pub android_cert_sha256: Vec<String>,
    /// Invite links on iOS: `TEAMID.com.mxndarijn.spikey` (APPLE_APP_ID); empty: none.
    pub apple_app_id: String,
    /// The App Store id once the app is listed (APP_STORE_ID); empty: a store search.
    pub app_store_id: String,
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
            android_cert_sha256: certs(&env::var("ANDROID_CERT_SHA256").unwrap_or_default()),
            apple_app_id: env::var("APPLE_APP_ID").unwrap_or_default().trim().to_string(),
            app_store_id: env::var("APP_STORE_ID").unwrap_or_default().trim().to_string(),
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
            android_cert_sha256: Vec::new(),
            apple_app_id: String::new(),
            app_store_id: String::new(),
        }
    }
}

/// The SHA-256 of the app's upload key (public: it is in every APK).
pub const UPLOAD_CERT_SHA256: &str =
    "C0:2B:FE:32:99:DB:7B:BB:72:5E:8F:F2:B9:4A:F0:AC:21:B1:67:82:C1:C0:BD:63:42:3A:4B:D7:02:FA:4E:91";

/// `"AA:BB, CC:DD"` -> ["AA:BB", "CC:DD"] (blanks dropped); none: the upload key.
pub fn certs(value: &str) -> Vec<String> {
    let given: Vec<String> = value.split(',').map(|v| v.trim().to_uppercase()).filter(|v| !v.is_empty()).collect();
    if given.is_empty() {
        vec![UPLOAD_CERT_SHA256.to_string()]
    } else {
        given
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_upload_key_unless_the_certificates_are_given() {
        assert_eq!(certs(""), vec![UPLOAD_CERT_SHA256.to_string()]);
        assert_eq!(certs(" aa:bb , ,CC:DD"), vec!["AA:BB".to_string(), "CC:DD".to_string()]);
    }
}

fn int(name: &str, default: i64) -> i64 {
    env::var(name).ok().and_then(|v| v.trim().parse().ok()).unwrap_or(default)
}
