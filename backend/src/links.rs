//! Invite links (docs/DUEL_MODE.md): `https://<host>/battle/CODE` and
//! `/duel/CODE` open the game's join screen when it is installed (Android App
//! Links, iOS Universal Links), else this page with the store buttons.
//!
//! - `GET /.well-known/assetlinks.json`: the app Android may open these links
//!   in (package com.mxndarijn.spikey, its signing certificates' SHA-256 from
//!   ANDROID_CERT_SHA256, by default the upload key; with Play App Signing,
//!   Google's key too).
//! - `GET /.well-known/apple-app-site-association` (and at the root): the iOS
//!   app (APPLE_APP_ID, `TEAMID.com.mxndarijn.spikey`) for /battle/* and /duel/*.
//! - `GET /battle/{code}`, `GET /duel/{code}`: the page without the app.
//!
//! Without APPLE_APP_ID the Apple file is a 404, so nothing wrong is ever
//! cached by a phone.

use axum::extract::{Path, State};
use axum::http::{header, StatusCode};
use axum::response::{Html, IntoResponse, Response};
use axum::Json;
use serde_json::{json, Value};

use crate::app::Shared;

pub const PACKAGE: &str = "com.mxndarijn.spikey";
pub const PLAY_URL: &str = "https://play.google.com/store/apps/details?id=com.mxndarijn.spikey";
pub const APP_STORE_SEARCH: &str = "https://apps.apple.com/search?term=flapjaw";
/// The paths the app opens.
pub const PATHS: [&str; 2] = ["/battle/*", "/duel/*"];

/// Android's Digital Asset Links file for these certificates (none: None).
pub fn assetlinks(certs: &[String]) -> Option<Value> {
    if certs.is_empty() {
        return None;
    }
    Some(json!([{
        "relation": ["delegate_permission/common.handle_all_urls"],
        "target": {
            "namespace": "android_app",
            "package_name": PACKAGE,
            "sha256_cert_fingerprints": certs,
        }
    }]))
}

/// Apple's app-site-association file for this app id (none: None).
pub fn apple_association(app_id: &str) -> Option<Value> {
    if app_id.is_empty() {
        return None;
    }
    let components: Vec<Value> = PATHS.iter().map(|p| json!({ "/": p })).collect();
    Some(json!({
        "applinks": {
            "details": [{
                "appIDs": [app_id],
                "components": components,
                // iOS before 13 reads this form.
                "appID": app_id,
                "paths": PATHS,
            }]
        }
    }))
}

/// A typed code as the game reads it: letters and digits only, upper case
/// (KD7-WQ3 and kd7wq3 are KD7WQ3), at most 12; anything else is empty.
pub fn clean_code(raw: &str) -> String {
    let code: String = raw.chars().filter(|c| c.is_ascii_alphanumeric()).map(|c| c.to_ascii_uppercase()).collect();
    if code.len() > 12 {
        String::new()
    } else {
        code
    }
}

/// The App Store page (APP_STORE_ID once the app is listed, else a search).
pub fn app_store_url(app_store_id: &str) -> String {
    if app_store_id.is_empty() {
        APP_STORE_SEARCH.into()
    } else {
        format!("https://apps.apple.com/app/id{app_store_id}")
    }
}

/// The page a link opens without the app: what it is, the code, the stores.
pub fn invite_page(mode: &str, code: &str, app_store: &str) -> String {
    let what = if mode == "duel" { "a Duel" } else { "a Battle" };
    let shown = if code.len() == 6 { format!("{}·{}", &code[..3], &code[3..]) } else { code.to_string() };
    let code_line =
        if code.is_empty() { String::new() } else { format!("<p>Your code</p><p class=\"code\">{shown}</p>") };
    format!(
        r#"<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Flapjaw: you're invited</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Archivo:wght@500;800&display=swap" rel="stylesheet">
<style>
body {{ margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
  background: #1b1f3b; color: #fff; font-family: Archivo, system-ui, sans-serif; text-align: center; }}
main {{ padding: 24px 16px; max-width: 360px; }}
h1 {{ font-weight: 800; font-size: 28px; margin: 0 0 8px; }}
p {{ margin: 8px 0; opacity: .85; }}
.code {{ font-weight: 800; font-size: 40px; letter-spacing: 4px; opacity: 1; }}
a {{ display: block; margin: 12px 0; padding: 14px; border-radius: 14px; background: #ffd23f;
  color: #1b1f3b; font-weight: 800; text-decoration: none; }}
</style></head>
<body><main>
<h1>You're invited to {what}</h1>
<p>Get Flapjaw, then open this link again, or type the code in the game.</p>
{code_line}
<a href="{PLAY_URL}">Get it on Google Play</a>
<a href="{app_store}">Download on the App Store</a>
</main></body></html>
"#
    )
}

pub async fn assetlinks_file(State(s): State<Shared>) -> Response {
    match assetlinks(&s.config.android_cert_sha256) {
        Some(v) => Json(v).into_response(),
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

pub async fn apple_file(State(s): State<Shared>) -> Response {
    match apple_association(&s.config.apple_app_id) {
        // Apple wants application/json, served directly (no redirect).
        Some(v) => ([(header::CONTENT_TYPE, "application/json")], v.to_string()).into_response(),
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

pub async fn battle_page(State(s): State<Shared>, Path(code): Path<String>) -> Html<String> {
    Html(invite_page("battle", &clean_code(&code), &app_store_url(&s.config.app_store_id)))
}

pub async fn duel_page(State(s): State<Shared>, Path(code): Path<String>) -> Html<String> {
    Html(invite_page("duel", &clean_code(&code), &app_store_url(&s.config.app_store_id)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_association_files_name_the_app_or_are_absent() {
        assert!(assetlinks(&[]).is_none());
        let certs = vec!["AA:BB".to_string(), "CC:DD".to_string()];
        let a = assetlinks(&certs).unwrap();
        assert_eq!(a[0]["target"]["package_name"], PACKAGE);
        assert_eq!(a[0]["target"]["sha256_cert_fingerprints"], json!(["AA:BB", "CC:DD"]));
        assert!(apple_association("").is_none());
        let i = apple_association("TEAM123456.com.mxndarijn.spikey").unwrap();
        let d = &i["applinks"]["details"][0];
        assert_eq!(d["appIDs"], json!(["TEAM123456.com.mxndarijn.spikey"]));
        assert_eq!(d["components"], json!([{"/": "/battle/*"}, {"/": "/duel/*"}]));
    }

    #[test]
    fn the_page_shows_a_clean_code_and_both_stores() {
        assert_eq!(clean_code("kd7-wq3"), "KD7WQ3");
        assert_eq!(clean_code("<script>"), "SCRIPT");
        assert_eq!(clean_code("ABCDEFGHIJKLMN"), "");
        let page = invite_page("duel", "KD7WQ3", &app_store_url(""));
        assert!(page.contains("a Duel"));
        assert!(page.contains("KD7·WQ3"));
        assert!(page.contains(PLAY_URL));
        assert!(page.contains(APP_STORE_SEARCH));
        assert!(app_store_url("123").ends_with("/id123"));
        assert!(!invite_page("battle", "", APP_STORE_SEARCH).contains("Your code"));
    }
}
