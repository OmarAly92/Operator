use serde::{Deserialize, Serialize};

use super::BoxFuture;

pub const DEFAULT_RELEASE_REPO_OWNER: &str = "OmarAly92";
pub const DEFAULT_RELEASE_REPO_NAME: &str = "operator";
pub const FEATURE_BUILD_MARKER: &str = "<!-- opr-feature-build:";
pub const FEATURE_BUILD_MAX_AGE_MS: i64 = 7 * 24 * 60 * 60 * 1000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Channel {
    Latest,
    Nightly,
}

/// The channel the updater feed actually tracks: the home channel, or the
/// `pr<N>` prerelease feed while a feature build is pinned.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActiveChannel {
    Latest,
    Nightly,
    Feature(i64),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct FeaturePin {
    pub pr: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateSettings {
    pub enabled: bool,
    pub channel: Channel,
    pub nightly_ack: bool,
    pub feature: Option<FeaturePin>,
}

impl Default for UpdateSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            channel: Channel::Latest,
            nightly_ack: false,
            feature: None,
        }
    }
}

impl UpdateSettings {
    /// The channel whose feed this configuration tracks right now.
    pub fn active_channel(&self) -> ActiveChannel {
        match self.feature {
            Some(pin) => ActiveChannel::Feature(pin.pr),
            None => match self.channel {
                Channel::Latest => ActiveChannel::Latest,
                Channel::Nightly => ActiveChannel::Nightly,
            },
        }
    }
}

/// Coerces an untrusted settings payload into supported values, mirroring the
/// daemon's normalization: unknown channels collapse to latest and a pin is
/// kept only when its PR is a positive integer.
pub fn coerce_settings(raw: &serde_json::Value) -> UpdateSettings {
    let object = match raw.as_object() {
        Some(object) => object,
        None => return UpdateSettings::default(),
    };
    UpdateSettings {
        enabled: object.get("enabled").and_then(serde_json::Value::as_bool) == Some(true),
        channel: if object.get("channel").and_then(serde_json::Value::as_str) == Some("nightly") {
            Channel::Nightly
        } else {
            Channel::Latest
        },
        nightly_ack: object
            .get("nightlyAck")
            .and_then(serde_json::Value::as_bool)
            == Some(true),
        feature: match object.get("feature") {
            Some(value) => value
                .get("pr")
                .and_then(serde_json::Value::as_i64)
                .filter(|pr| *pr > 0)
                .map(|pr| FeaturePin { pr }),
            None => None,
        },
    }
}

/// Electron allowDowngrade=true parity: any semantically different candidate
/// the feed offers is surfaced to the shell, including older versions, so a
/// return-home from a pr<N>/nightly build can never strand the user.
pub fn feed_offers_candidate(current: &str, candidate: &str) -> bool {
    match (
        semver::Version::parse(candidate),
        semver::Version::parse(current),
    ) {
        (Ok(candidate), Ok(current)) => candidate != current,
        _ => candidate != current,
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeedUrlError {
    NotHttps,
    InvalidBase,
}

impl std::fmt::Display for FeedUrlError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FeedUrlError::NotHttps => write!(f, "update feeds must use HTTPS"),
            FeedUrlError::InvalidBase => write!(f, "update feed base URL could not be parsed"),
        }
    }
}

/// Resolves the static update-feed URL for a channel. Loopback HTTP is allowed
/// only for unpackaged development shells; production feeds must be HTTPS.
pub fn select_feed_url(
    base: &str,
    channel: ActiveChannel,
    packaged: bool,
) -> Result<String, FeedUrlError> {
    let parsed = tauri::Url::parse(base.trim()).map_err(|_| FeedUrlError::InvalidBase)?;
    let loopback = matches!(parsed.host_str(), Some("127.0.0.1" | "localhost" | "::1"));
    if parsed.scheme() == "http" {
        if packaged || !loopback {
            return Err(FeedUrlError::NotHttps);
        }
    } else if parsed.scheme() != "https" || parsed.host_str().is_none() {
        return Err(FeedUrlError::InvalidBase);
    }
    let file = match channel {
        ActiveChannel::Latest => "latest.json",
        ActiveChannel::Nightly => "nightly.json",
        ActiveChannel::Feature(pr) if pr > 0 => {
            return Ok(join_feed_file(&parsed, &format!("pr{pr}.json")))
        }
        ActiveChannel::Feature(_) => return Err(FeedUrlError::InvalidBase),
    };
    Ok(join_feed_file(&parsed, file))
}

fn join_feed_file(base: &tauri::Url, file: &str) -> String {
    let mut joined = base.clone();
    joined.set_path(&format!("{}/{}", base.path().trim_end_matches('/'), file));
    joined.to_string()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PublicKeyError {
    PrivateKeyMaterial,
    Malformed,
}

impl std::fmt::Display for PublicKeyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PublicKeyError::PrivateKeyMaterial => {
                write!(f, "refusing updater key material shaped like a private key; only the minisign public key may be compiled in")
            }
            PublicKeyError::Malformed => {
                write!(f, "updater key material is not a valid minisign public key")
            }
        }
    }
}

const MINISIGN_PUBLIC_PACKET_BYTES: usize = 42;

fn decoded_packet(material: &str) -> Option<Vec<u8>> {
    use base64::Engine as _;
    let second_line = material.lines().nth(1)?.trim();
    base64::engine::general_purpose::STANDARD
        .decode(second_line)
        .ok()
}

/// Validates compiled-in key material as a Tauri/minisign public key packet:
/// two comment lines wrapping a 42-byte base64 packet whose algorithm bytes
/// are "Ed". Anything else — including secret-key material — is rejected.
pub fn validate_public_key(material: &str) -> Result<(), PublicKeyError> {
    let trimmed = material.trim();
    if !trimmed.starts_with("untrusted comment:") || trimmed.lines().count() < 2 {
        return Err(PublicKeyError::Malformed);
    }
    if trimmed.to_lowercase().contains("secret key") {
        return Err(PublicKeyError::PrivateKeyMaterial);
    }
    let packet = decoded_packet(trimmed).ok_or(PublicKeyError::Malformed)?;
    if packet.len() != MINISIGN_PUBLIC_PACKET_BYTES || &packet[..2] != b"Ed" {
        return Err(PublicKeyError::Malformed);
    }
    Ok(())
}

/// Parses a version string for a feature-build prerelease identifier,
/// matching "-pr<N>.<12-digit-ts>" with an optional leading "v".
pub fn parse_feature_build(version: &str) -> Option<i64> {
    let stripped = version.strip_prefix('v').unwrap_or(version);
    let marker = stripped.find("-pr")?;
    let rest = &stripped[marker + 3..];
    let dot = rest.find('.')?;
    let pr: i64 = rest[..dot].parse().ok()?;
    if pr <= 0 {
        return None;
    }
    let timestamp = tail_digits(rest.get(dot + 1..)?);
    if timestamp != 12 {
        return None;
    }
    Some(pr)
}

fn tail_digits(tail: &str) -> usize {
    tail.chars().take_while(|c| c.is_ascii_digit()).count()
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FeatureBuild {
    pub pr: i64,
    pub title: String,
    pub base: String,
    pub sha: String,
    pub slug: String,
    pub build_id: String,
    pub published_at: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GitHubRelease {
    pub tag_name: String,
    pub name: String,
    pub prerelease: bool,
    pub published_at: String,
    #[serde(default)]
    pub body: Option<String>,
}

/// Live release lookups behind the feature-build listing and pin reconciliation.
pub trait ReleasesSource: Send + Sync {
    fn list_releases<'a>(&'a self) -> BoxFuture<'a, Result<Vec<GitHubRelease>, String>>;
    fn is_pr_open<'a>(&'a self, pr: i64) -> BoxFuture<'a, bool>;
}

fn parse_marker(body: &str) -> Option<(i64, String, String, String)> {
    let start = body.find(FEATURE_BUILD_MARKER)? + FEATURE_BUILD_MARKER.len();
    let end = body[start..].find("-->")? + start;
    let payload: serde_json::Value = serde_json::from_str(body[start..end].trim()).ok()?;
    let pr = payload.get("pr")?.as_i64()?;
    let base = payload.get("base")?.as_str()?.to_string();
    let sha = payload
        .get("sha")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .to_string();
    let slug = payload
        .get("slug")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default()
        .to_string();
    Some((pr, base, sha, slug))
}

fn published_epoch_ms(published_at: &str) -> Option<i64> {
    let trimmed = published_at.trim();
    let (date_part, time_part) = trimmed.split_once('T')?;
    let time_part = time_part.trim_end_matches('Z');
    let (clock, millis) = match time_part.split_once('.') {
        Some((clock, fraction)) => {
            let millis = format!("{fraction:0<3}");
            let millis = millis.get(..3).unwrap_or("0");
            (clock, millis.parse::<i64>().unwrap_or(0))
        }
        None => (time_part, 0),
    };
    let mut clock_parts = clock.split(':');
    let hours: i64 = clock_parts.next()?.parse().ok()?;
    let minutes: i64 = clock_parts.next()?.parse().ok()?;
    let seconds: i64 = clock_parts.next().unwrap_or("0").parse().ok()?;
    let mut date_parts = date_part.split('-');
    let year: i64 = date_parts.next()?.parse().ok()?;
    let month: i32 = date_parts.next()?.parse().ok()?;
    let day: i32 = date_parts.next()?.parse().ok()?;
    let days = days_from_civil(year, month, day);
    Some(((days * 86_400) + hours * 3600 + minutes * 60 + seconds) * 1000 + millis)
}

fn days_from_civil(y: i64, m: i32, d: i32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = if m > 2 { m - 3 } else { m + 9 } as i64;
    let doy = (153 * mp + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

struct Candidate {
    build: FeatureBuild,
    published_ms: i64,
}

/// Fetches and filters live feature builds: prerelease, marker-carrying,
/// published within the last seven days, PR still open; grouped to the newest
/// build per PR and sorted newest-first. Errors only when the releases fetch
/// itself fails so callers can tell "no live builds" from "unreachable".
pub async fn collect_feature_builds(
    source: &dyn ReleasesSource,
    now_ms: i64,
) -> Result<Vec<FeatureBuild>, String> {
    let releases = source.list_releases().await?;
    let cutoff = now_ms - FEATURE_BUILD_MAX_AGE_MS;

    let mut candidates: Vec<Candidate> = Vec::new();
    for release in releases {
        if !release.prerelease {
            continue;
        }
        let Some(published_ms) = published_epoch_ms(&release.published_at) else {
            continue;
        };
        if published_ms < cutoff {
            continue;
        }
        let Some(body) = release.body.clone() else {
            continue;
        };
        let Some((pr, base, sha, slug)) = parse_marker(&body) else {
            continue;
        };
        candidates.push(Candidate {
            build: FeatureBuild {
                pr,
                title: release.name,
                base,
                sha,
                slug,
                build_id: release.tag_name,
                published_at: release.published_at,
            },
            published_ms,
        });
    }

    let mut unique_prs: Vec<i64> = Vec::new();
    for candidate in &candidates {
        if !unique_prs.contains(&candidate.build.pr) {
            unique_prs.push(candidate.build.pr);
        }
    }
    let mut best_by_pr: std::collections::HashMap<i64, Candidate> =
        std::collections::HashMap::new();
    for pr in unique_prs {
        let open = source.is_pr_open(pr).await;
        if !open {
            continue;
        }
        if let Some(newest) = candidates
            .iter()
            .filter(|candidate| candidate.build.pr == pr)
            .max_by_key(|candidate| candidate.published_ms)
        {
            best_by_pr.insert(
                pr,
                Candidate {
                    build: newest.build.clone(),
                    published_ms: newest.published_ms,
                },
            );
        }
    }

    let mut results: Vec<Candidate> = best_by_pr.into_values().collect();
    results.sort_by_key(|candidate| std::cmp::Reverse(candidate.published_ms));
    Ok(results
        .into_iter()
        .map(|candidate| candidate.build)
        .collect())
}

/// Lists feature builds, degrading to an empty list on any releases-fetch
/// failure so a picker never breaks on network errors.
pub async fn list_feature_builds(source: &dyn ReleasesSource, now_ms: i64) -> Vec<FeatureBuild> {
    match collect_feature_builds(source, now_ms).await {
        Ok(builds) => builds,
        Err(error) => {
            eprintln!("[feature-builds] failed to list feature builds: {error}");
            Vec::new()
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReconcileResult {
    pub settings: UpdateSettings,
    pub cleared: bool,
}

/// Clears a pinned feature build whose PR no longer has a live build. A fetch
/// failure keeps the pin so a transient error never strands the user off it.
pub async fn reconcile_feature_pin(
    source: &dyn ReleasesSource,
    settings: UpdateSettings,
    now_ms: i64,
) -> ReconcileResult {
    let Some(pin) = settings.feature else {
        return ReconcileResult {
            settings,
            cleared: false,
        };
    };
    let builds = match collect_feature_builds(source, now_ms).await {
        Ok(builds) => builds,
        Err(_) => {
            return ReconcileResult {
                settings,
                cleared: false,
            }
        }
    };
    if builds.iter().any(|build| build.pr == pin.pr) {
        return ReconcileResult {
            settings,
            cleared: false,
        };
    }
    ReconcileResult {
        cleared: true,
        settings: UpdateSettings {
            feature: None,
            ..settings
        },
    }
}
