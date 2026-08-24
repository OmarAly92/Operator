use std::collections::{HashMap, VecDeque};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use serde_json::json;

use super::channel::feed_offers_candidate;
use super::{recover_interrupted, RecoverySummary};
use crate::updater::storage::PARTIAL_MAX_AGE_MS;

use super::channel::{
    coerce_settings, collect_feature_builds, list_feature_builds, parse_feature_build,
    reconcile_feature_pin, select_feed_url, validate_public_key, ActiveChannel, Channel,
    FeatureBuild, FeaturePin, FeedUrlError, GitHubRelease, PublicKeyError, ReconcileResult,
    ReleasesSource, UpdateSettings,
};
use super::escalation::{evaluate_escalation, EscalationFeeds, EscalationInput, H48_MS};
use super::status::{
    update_failure_category, update_failure_outcome, UpdateFailureCategory, UpdatePhase,
    UpdateState, UpdateStatus, UpdateTrigger,
};
use super::storage::{StorageError, UpdaterStorage};
use super::{
    first_run_settings, BoxFuture, CheckOptions, ClockFn, EngineConfig, FeedClient, FirstRunAnswer,
    ProgressCallback, ReleaseHandle, StatusSink, UpdaterEngine, APPLY_DEFERRED_MESSAGE,
    MANIFEST_404_CHECK_MESSAGE, MANIFEST_404_DOWNLOAD_MESSAGE, UNSUPPORTED_MESSAGE,
};

const APP_VERSION: &str = "1.0.0";

// ---------------------------------------------------------------- fakes

struct FakeRelease(String);

impl ReleaseHandle for FakeRelease {
    fn version(&self) -> String {
        self.0.clone()
    }
}

#[derive(Default)]
struct FakeClientState {
    checks: Vec<Result<Option<String>, String>>,
    downloads: Vec<Result<Vec<u8>, String>>,
    progress_plans: Vec<Vec<u32>>,
    urls: Vec<String>,
    download_versions: Vec<String>,
    event_log: Vec<String>,
    held_downloads: usize,
}

#[derive(Clone)]
struct FakeClient {
    state: Arc<Mutex<FakeClientState>>,
    gate: Arc<tokio::sync::Notify>,
    download_gate: Arc<tokio::sync::Notify>,
    hold_first_check: bool,
    hold_first_download: bool,
}

impl FakeClient {
    fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(FakeClientState::default())),
            gate: Arc::new(tokio::sync::Notify::new()),
            download_gate: Arc::new(tokio::sync::Notify::new()),
            hold_first_check: false,
            hold_first_download: false,
        }
    }

    fn hold_first_check(mut self) -> Self {
        self.hold_first_check = true;
        self
    }

    fn hold_first_download(mut self) -> Self {
        self.hold_first_download = true;
        self
    }

    fn release_download_gate(&self) -> Arc<tokio::sync::Notify> {
        self.download_gate.clone()
    }

    fn release_check(self, version: &str) -> Self {
        self.state
            .lock()
            .unwrap()
            .checks
            .push(Ok(Some(version.to_string())));
        self
    }

    fn no_release(self) -> Self {
        self.state.lock().unwrap().checks.push(Ok(None));
        self
    }

    fn failed_check(self, message: &str) -> Self {
        self.state
            .lock()
            .unwrap()
            .checks
            .push(Err(message.to_string()));
        self
    }

    fn download_bytes(self, bytes: &[u8]) -> Self {
        self.state
            .lock()
            .unwrap()
            .downloads
            .push(Ok(bytes.to_vec()));
        self
    }

    fn failed_download(self, message: &str) -> Self {
        self.state
            .lock()
            .unwrap()
            .downloads
            .push(Err(message.to_string()));
        self
    }

    fn progress_plan(self, percents: &[u32]) -> Self {
        self.state
            .lock()
            .unwrap()
            .progress_plans
            .push(percents.to_vec());
        self
    }

    fn urls(&self) -> Vec<String> {
        self.state.lock().unwrap().urls.clone()
    }

    fn event_log(&self) -> Vec<String> {
        self.state.lock().unwrap().event_log.clone()
    }

    fn release_gate(&self) -> Arc<tokio::sync::Notify> {
        self.gate.clone()
    }
}

impl FeedClient for FakeClient {
    type Release = FakeRelease;

    fn check<'a>(&'a self, url: String) -> BoxFuture<'a, Result<Option<FakeRelease>, String>> {
        Box::pin(async move {
            let held = self.hold_first_check;
            let hold = {
                let mut state = self.state.lock().unwrap();
                state.urls.push(url);
                state.event_log.push("check".to_string());
                let first_check = state.event_log.iter().filter(|e| *e == "check").count() == 1;
                held && first_check
            };
            if hold {
                self.gate.notified().await;
            }
            let outcome = {
                let mut state = self.state.lock().unwrap();
                if state.checks.is_empty() {
                    Ok(None)
                } else {
                    state.checks.remove(0)
                }
            };
            outcome.map(|version| version.map(FakeRelease))
        })
    }

    fn download<'a>(
        &'a self,
        release: FakeRelease,
        mut progress: ProgressCallback,
    ) -> BoxFuture<'a, Result<Vec<u8>, String>> {
        Box::pin(async move {
            let (plan, hold) = {
                let mut state = self.state.lock().unwrap();
                state.download_versions.push(release.version());
                state.event_log.push("download".to_string());
                let hold = self.hold_first_download && state.held_downloads == 1;
                state.held_downloads += 1;
                if state.progress_plans.is_empty() {
                    (Vec::new(), hold)
                } else {
                    (state.progress_plans.remove(0), hold)
                }
            };
            for percent in &plan {
                progress(*percent);
            }
            if hold {
                self.download_gate.notified().await;
            }
            let outcome = {
                let mut state = self.state.lock().unwrap();
                if state.downloads.is_empty() {
                    Ok(Vec::new())
                } else {
                    state.downloads.remove(0)
                }
            };
            outcome
        })
    }
}

struct FakeSettingsState {
    current: UpdateSettings,
    writes: Vec<UpdateSettings>,
    read_failures: VecDeque<String>,
    order: Vec<&'static str>,
}

#[derive(Clone)]
struct FakeSettings {
    state: Arc<Mutex<FakeSettingsState>>,
}

impl FakeSettings {
    fn new(initial: UpdateSettings) -> Self {
        Self {
            state: Arc::new(Mutex::new(FakeSettingsState {
                current: initial,
                writes: Vec::new(),
                read_failures: VecDeque::new(),
                order: Vec::new(),
            })),
        }
    }

    fn fail_next_read(&self, message: &str) -> &Self {
        self.state
            .lock()
            .unwrap()
            .read_failures
            .push_back(message.to_string());
        self
    }

    fn current(&self) -> UpdateSettings {
        self.state.lock().unwrap().current.clone()
    }

    fn writes(&self) -> Vec<UpdateSettings> {
        self.state.lock().unwrap().writes.clone()
    }

    fn order(&self) -> Vec<&'static str> {
        self.state.lock().unwrap().order.clone()
    }

    fn replace_current(&self, next: UpdateSettings) {
        self.state.lock().unwrap().current = next;
    }
}

impl super::SettingsSource for FakeSettings {
    fn read<'a>(&'a self) -> BoxFuture<'a, Result<UpdateSettings, String>> {
        Box::pin(async move {
            let mut state = self.state.lock().unwrap();
            state.order.push("read");
            if let Some(error) = state.read_failures.pop_front() {
                return Err(error);
            }
            Ok(state.current.clone())
        })
    }

    fn write<'a>(&'a self, settings: UpdateSettings) -> BoxFuture<'a, Result<(), String>> {
        Box::pin(async move {
            let mut state = self.state.lock().unwrap();
            state.order.push("write");
            state.current = settings.clone();
            state.writes.push(settings);
            Ok(())
        })
    }
}

struct FakeFeedsState {
    stable: Option<String>,
    important: bool,
}

#[derive(Clone)]
struct FakeFeeds {
    state: Arc<Mutex<FakeFeedsState>>,
}

impl FakeFeeds {
    fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(FakeFeedsState {
                stable: None,
                important: false,
            })),
        }
    }
}

impl EscalationFeeds for FakeFeeds {
    fn latest_stable_version<'a>(&'a self) -> BoxFuture<'a, Option<String>> {
        Box::pin(async move { self.state.lock().unwrap().stable.clone() })
    }

    fn nightly_important<'a>(&'a self, _version: &str) -> BoxFuture<'a, bool> {
        Box::pin(async move { self.state.lock().unwrap().important })
    }
}

struct FakeReleasesState {
    list: Result<Vec<GitHubRelease>, String>,
    open: HashMap<i64, bool>,
    list_calls: usize,
    pulls: Vec<i64>,
}

#[derive(Clone)]
struct FakeReleases {
    state: Arc<Mutex<FakeReleasesState>>,
}

impl FakeReleases {
    fn new(list: Result<Vec<GitHubRelease>, String>) -> Self {
        Self {
            state: Arc::new(Mutex::new(FakeReleasesState {
                list,
                open: HashMap::new(),
                list_calls: 0,
                pulls: Vec::new(),
            })),
        }
    }

    fn with_pr_open(self, pr: i64, open: bool) -> Self {
        self.state.lock().unwrap().open.insert(pr, open);
        self
    }

    fn set_list(&self, releases: Result<Vec<GitHubRelease>, String>) {
        self.state.lock().unwrap().list = releases;
    }

    fn list_calls(&self) -> usize {
        self.state.lock().unwrap().list_calls
    }
}

impl ReleasesSource for FakeReleases {
    fn list_releases<'a>(&'a self) -> BoxFuture<'a, Result<Vec<GitHubRelease>, String>> {
        Box::pin(async move {
            let mut state = self.state.lock().unwrap();
            state.list_calls += 1;
            match &state.list {
                Ok(releases) => Ok(releases.clone()),
                Err(message) => Err(message.clone()),
            }
        })
    }

    fn is_pr_open<'a>(&'a self, pr: i64) -> BoxFuture<'a, bool> {
        Box::pin(async move {
            let mut state = self.state.lock().unwrap();
            state.pulls.push(pr);
            *state.open.get(&pr).unwrap_or(&true)
        })
    }
}

#[derive(Default)]
struct VecSinkState {
    statuses: Vec<UpdateStatus>,
    telemetry: Vec<super::status::UpdateOutcome>,
}

#[derive(Clone, Default)]
struct VecSink {
    state: Arc<Mutex<VecSinkState>>,
}

impl VecSink {
    fn statuses(&self) -> Vec<UpdateStatus> {
        self.state.lock().unwrap().statuses.clone()
    }

    fn telemetry(&self) -> Vec<super::status::UpdateOutcome> {
        self.state.lock().unwrap().telemetry.clone()
    }
}

impl StatusSink for VecSink {
    fn emit_status(&self, status: &UpdateStatus) {
        self.state.lock().unwrap().statuses.push(status.clone());
    }

    fn emit_telemetry(&self, outcome: &super::status::UpdateOutcome) {
        self.state.lock().unwrap().telemetry.push(outcome.clone());
    }
}

type SharedClock = Arc<std::sync::Mutex<i64>>;

fn clock_at(ms: i64) -> SharedClock {
    Arc::new(std::sync::Mutex::new(ms))
}

const BASE_TIME: i64 = 1_753_000_000_000;

struct Harness {
    engine: Arc<UpdaterEngine<FakeClient>>,
    client: FakeClient,
    settings: FakeSettings,
    feeds: FakeFeeds,
    releases: FakeReleases,
    sink: VecSink,
    clock: SharedClock,
    updater_root: PathBuf,
    _keep: tempfile_guard::TempDirGuard,
}

mod tempfile_guard {
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicUsize, Ordering};

    pub struct TempDirGuard(PathBuf);

    impl TempDirGuard {
        pub fn create(tag: &str) -> Self {
            let dir = std::env::temp_dir().join(format!(
                "opr-updater-test-{tag}-{}-{}",
                std::process::id(),
                next_counter()
            ));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(&dir).unwrap();
            let canonical = std::fs::canonicalize(&dir).unwrap();
            Self(canonical)
        }

        pub fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDirGuard {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn next_counter() -> usize {
        static COUNTER: AtomicUsize = AtomicUsize::new(0);
        COUNTER.fetch_add(1, Ordering::SeqCst)
    }
}

fn enabled_latest() -> UpdateSettings {
    UpdateSettings {
        enabled: true,
        channel: Channel::Latest,
        nightly_ack: false,
        feature: None,
    }
}

fn pinned(pr: i64) -> UpdateSettings {
    UpdateSettings {
        enabled: true,
        channel: Channel::Latest,
        nightly_ack: false,
        feature: Some(FeaturePin { pr }),
    }
}

struct HarnessBuilder {
    settings: UpdateSettings,
    packaged: bool,
    app_version: String,
    feed_base: Option<String>,
    public_key: String,
}

fn harness() -> HarnessBuilder {
    HarnessBuilder {
        settings: enabled_latest(),
        packaged: true,
        app_version: APP_VERSION.to_string(),
        feed_base: Some("https://releases.example.com/operator/".to_string()),
        public_key: String::new(),
    }
}

impl HarnessBuilder {
    fn build(self, client: FakeClient) -> Harness {
        let keep = tempfile_guard::TempDirGuard::create("state");
        let storage = UpdaterStorage::open(keep.path()).unwrap();
        let updater_root = storage.root().to_path_buf();
        let settings = FakeSettings::new(self.settings);
        let feeds = FakeFeeds::new();
        let releases = FakeReleases::new(Ok(Vec::new()));
        let sink = VecSink::default();
        let clock = clock_at(BASE_TIME);
        let config = EngineConfig {
            packaged: self.packaged,
            app_version: self.app_version,
            feed_base_url: self.feed_base,
            public_key: self.public_key,
        };
        let engine = Arc::new(UpdaterEngine::new(
            Arc::new(client.clone()),
            Arc::new(settings.clone()),
            Arc::new(feeds.clone()),
            Arc::new(releases.clone()),
            storage,
            Arc::new(sink.clone()),
            {
                let shared = clock.clone();
                Arc::new(move || *shared.lock().unwrap()) as ClockFn
            },
            config,
        ));
        Harness {
            engine,
            client,
            settings,
            feeds,
            releases,
            sink,
            clock,
            updater_root,
            _keep: keep,
        }
    }
}

fn staged_at(status: &UpdateStatus) -> i64 {
    status.staged_at.expect("stagedAt present")
}

// ---------------------------------------------------------------- channel

#[test]
fn channel_selects_latest_and_nightly_feed_urls() {
    assert_eq!(
        select_feed_url(
            "https://releases.example.com/op/",
            ActiveChannel::Latest,
            true
        )
        .unwrap(),
        "https://releases.example.com/op/latest.json"
    );
    assert_eq!(
        select_feed_url(
            "https://releases.example.com/op",
            ActiveChannel::Nightly,
            true
        )
        .unwrap(),
        "https://releases.example.com/op/nightly.json"
    );
    assert_eq!(
        select_feed_url(
            "https://releases.example.com/op/",
            ActiveChannel::Feature(2270),
            true
        )
        .unwrap(),
        "https://releases.example.com/op/pr2270.json"
    );
}

#[test]
fn channel_requires_https_except_unpackaged_loopback() {
    assert_eq!(
        select_feed_url(
            "http://releases.example.com/op/",
            ActiveChannel::Latest,
            true
        ),
        Err(FeedUrlError::NotHttps)
    );
    assert!(select_feed_url("http://127.0.0.1:9000/feeds/", ActiveChannel::Latest, false).is_ok());
    assert!(select_feed_url("http://127.0.0.1:9000/feeds/", ActiveChannel::Latest, true).is_err());
    assert_eq!(
        select_feed_url("not a url", ActiveChannel::Latest, true),
        Err(FeedUrlError::InvalidBase)
    );
}

fn minisign_public_key_material() -> String {
    let mut packet = b"Ed".to_vec();
    packet.extend_from_slice(&[7u8; 40]);
    format!(
        "untrusted comment: minisign public key ABCDEF\n{}\n",
        simple_base64(&packet)
    )
}

fn minisign_private_key_material() -> String {
    let mut packet = b"Bs".to_vec();
    packet.extend_from_slice(&[9u8; 102]);
    format!(
        "untrusted comment: minisign encrypted secret key\n{}\n",
        simple_base64(&packet)
    )
}

fn simple_base64(input: &[u8]) -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in input.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = chunk.get(1).copied().unwrap_or(0) as u32;
        let b2 = chunk.get(2).copied().unwrap_or(0) as u32;
        let triple = (b0 << 16) | (b1 << 8) | b2;
        out.push(ALPHABET[(triple >> 18) as usize & 63] as char);
        out.push(ALPHABET[(triple >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 {
            ALPHABET[(triple >> 6) as usize & 63] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            ALPHABET[triple as usize & 63] as char
        } else {
            '='
        });
    }
    out
}

#[allow(dead_code)]
fn simple_base64_decode(input: &str) -> Option<Vec<u8>> {
    const ALPHABET: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let bytes: Vec<u8> = input.bytes().filter(|b| !b.is_ascii_whitespace()).collect();
    let mut out = Vec::new();
    for chunk in bytes.chunks(4) {
        if chunk.len() < 2 {
            return None;
        }
        let mut acc: u32 = 0;
        let mut symbols = 0usize;
        for (i, byte) in chunk.iter().enumerate() {
            if *byte == b'=' {
                break;
            }
            let value = ALPHABET.find(*byte as char)? as u32;
            acc |= value << (18 - 6 * i);
            symbols += 1;
        }
        for k in 0..symbols.saturating_sub(1) {
            out.push(((acc >> (16 - 8 * k)) & 0xff) as u8);
        }
    }
    Some(out)
}

#[test]
fn public_key_accepts_public_packets_and_rejects_other_shapes() {
    assert_eq!(validate_public_key(&minisign_public_key_material()), Ok(()));
    assert_eq!(
        validate_public_key(&minisign_private_key_material()),
        Err(PublicKeyError::PrivateKeyMaterial)
    );
    assert_eq!(
        validate_public_key("untrusted comment: x\nnot-base64!!\n"),
        Err(PublicKeyError::Malformed)
    );
    assert_eq!(
        validate_public_key("untrusted comment: x\nc2hvcnQ=\n"),
        Err(PublicKeyError::Malformed)
    );
}

#[test]
fn feed_offers_candidate_permits_downgrades_and_rejects_equality() {
    assert!(
        feed_offers_candidate("2.0.0", "1.9.9"),
        "allowDowngrade parity"
    );
    assert!(!feed_offers_candidate("2.0.0", "2.0.0"));
    assert!(feed_offers_candidate("2.0.0", "2.0.1"));
    assert!(
        feed_offers_candidate("2.0.0-nightly.202608010000", "2.0.0"),
        "a nightly running build is offered stable of the same base"
    );
}

#[test]
fn parse_feature_build_matches_electron_parser() {
    assert_eq!(parse_feature_build("0.2.0-pr2270.202607061200"), Some(2270));
    assert_eq!(
        parse_feature_build("v0.2.0-pr2270.202607061200"),
        Some(2270)
    );
    assert_eq!(parse_feature_build("0.2.0"), None);
    assert_eq!(parse_feature_build("0.3.0-nightly.202607060000"), None);
    assert_eq!(
        parse_feature_build("0.3.0-nightly.202607060000+abc1234"),
        None
    );
    assert_eq!(parse_feature_build(""), None);
    assert_eq!(parse_feature_build("0.2.0-pr0.202607061200"), None);
}

#[test]
fn settings_coerce_matches_daemon_normalization() {
    let coerced = coerce_settings(&json!({
        "enabled": true,
        "channel": "bogus",
        "nightlyAck": true,
        "feature": { "pr": 2709 },
    }));
    assert_eq!(coerced.channel, Channel::Latest);
    assert_eq!(coerced.feature, Some(FeaturePin { pr: 2709 }));

    let cleared = coerce_settings(&json!({ "enabled": false, "feature": { "pr": -1 } }));
    assert_eq!(cleared.feature, None);
    assert!(!cleared.enabled);

    let defaulted = coerce_settings(&serde_json::Value::Null);
    assert_eq!(defaulted, UpdateSettings::default());

    let active = pinned(42);
    assert_eq!(active.active_channel(), ActiveChannel::Feature(42));
    assert_eq!(enabled_latest().active_channel(), ActiveChannel::Latest);
}

#[tokio::test]
async fn feature_listing_filters_prerelease_marker_and_age() {
    let recent = BASE_TIME - 24 * 60 * 60 * 1000;
    let old = BASE_TIME - 8 * 24 * 60 * 60 * 1000;
    let edge_recent = BASE_TIME - 6 * 24 * 60 * 60 * 1000;
    let source = FakeReleases::new(Ok(vec![
        release(
            "v0.2.0-pr2270.202607061200",
            true,
            recent,
            Some(marker(2270)),
        ),
        release("v1.0.0", false, recent, Some(marker(2300))),
        release("v0.2.0-pr2271.202607061200", true, recent, None),
        release("v0.2.0-pr2272.202607061200", true, old, Some(marker(2272))),
        release(
            "v0.2.0-pr2273.202607061200",
            true,
            edge_recent,
            Some(marker(2273)),
        ),
    ]))
    .with_pr_open(2270, true)
    .with_pr_open(2273, true);

    let builds = list_feature_builds(&source, BASE_TIME).await;

    assert_eq!(builds.len(), 2);
    assert_eq!(builds[0].pr, 2270);
    assert_eq!(builds[1].pr, 2273);
}

#[tokio::test]
async fn feature_listing_groups_newest_per_pr_and_sorts_newest_first() {
    let t1 = BASE_TIME - 3 * 24 * 60 * 60 * 1000;
    let t2 = BASE_TIME - 24 * 60 * 60 * 1000;
    let t3 = BASE_TIME - 2 * 24 * 60 * 60 * 1000;
    let older = BASE_TIME - 5 * 24 * 60 * 60 * 1000;
    let source = FakeReleases::new(Ok(vec![
        release("v0.2.0-pr2271.202607040000", true, t1, Some(marker(2271))),
        release("v0.2.0-pr2272.202607060000", true, t2, Some(marker(2272))),
        release("v0.2.0-pr2270.202607050000", true, t3, Some(marker(2270))),
        release(
            "v0.2.0-pr2270.202607030000",
            true,
            older,
            Some(marker(2270)),
        ),
    ]))
    .with_pr_open(2270, true)
    .with_pr_open(2271, true)
    .with_pr_open(2272, true);

    let builds = collect_feature_builds(&source, BASE_TIME).await.unwrap();

    let prs: Vec<i64> = builds.iter().map(|b| b.pr).collect();
    assert_eq!(prs, vec![2272, 2270, 2271]);
    let pr2270: Vec<&FeatureBuild> = builds.iter().filter(|b| b.pr == 2270).collect();
    assert_eq!(pr2270.len(), 1);
    assert_eq!(pr2270[0].build_id, "v0.2.0-pr2270.202607050000");
}

#[tokio::test]
async fn feature_listing_excludes_closed_merged_and_keeps_on_probe_errors() {
    let recent = BASE_TIME - 24 * 60 * 60 * 1000;
    let source = FakeReleases::new(Ok(vec![release(
        "v0.2.0-pr2270.202607061200",
        true,
        recent,
        Some(marker(2270)),
    )]))
    .with_pr_open(2270, false);

    assert!(list_feature_builds(&source, BASE_TIME).await.is_empty());

    let erroring = FakeReleases::new(Ok(vec![release(
        "v0.2.0-pr2270.202607061200",
        true,
        recent,
        Some(marker(2270)),
    )]));
    assert_eq!(
        list_feature_builds(&erroring, BASE_TIME).await.len(),
        1,
        "probe errors keep the build"
    );
}

#[tokio::test]
async fn feature_listing_degrades_to_empty_on_fetch_failure() {
    let source = FakeReleases::new(Err("network error".to_string()));
    assert!(list_feature_builds(&source, BASE_TIME).await.is_empty());
}

#[tokio::test]
async fn reconcile_pin_keeps_live_pins_and_clears_retired_ones() {
    let recent = BASE_TIME - 24 * 60 * 60 * 1000;
    let live = FakeReleases::new(Ok(vec![release(
        "v0.2.0-pr2270.202607061200",
        true,
        recent,
        Some(marker(2270)),
    )]))
    .with_pr_open(2270, true);
    let live_result = reconcile_feature_pin(&live, pinned(2270), BASE_TIME).await;
    assert_eq!(
        live_result,
        ReconcileResult {
            settings: pinned(2270),
            cleared: false,
        }
    );

    let retired = FakeReleases::new(Ok(Vec::new()));
    let retired_result = reconcile_feature_pin(&retired, pinned(2270), BASE_TIME).await;
    assert!(retired_result.cleared);
    assert_eq!(retired_result.settings.feature, None);
    assert_eq!(retired_result.settings.channel, Channel::Latest);

    let failing = FakeReleases::new(Err("rate limited".to_string()));
    let failing_result = reconcile_feature_pin(&failing, pinned(2270), BASE_TIME).await;
    assert!(!failing_result.cleared);

    let unpinned = reconcile_feature_pin(&retired, enabled_latest(), BASE_TIME).await;
    assert!(!unpinned.cleared);
}

// ---------------------------------------------------------------- status wire

#[test]
fn status_serializes_the_renderer_wire_shape() {
    let available: UpdateStatus = UpdateStatus {
        state: UpdateState::Available,
        version: Some("2.0.0".to_string()),
        request_id: Some("feature-update-1".to_string()),
        ..UpdateStatus::idle()
    };
    assert_eq!(
        serde_json::to_value(&available).unwrap(),
        json!({"state": "available", "version": "2.0.0", "requestId": "feature-update-1"})
    );

    let staged = UpdateStatus {
        state: UpdateState::Downloaded,
        version: Some("2.1.0".to_string()),
        staged_at: Some(1234),
        escalated: Some(true),
        ..UpdateStatus::idle()
    };
    assert_eq!(
        serde_json::to_value(&staged).unwrap(),
        json!({"state": "downloaded", "version": "2.1.0", "stagedAt": 1234, "escalated": true})
    );

    assert_eq!(
        serde_json::to_value(UpdateStatus {
            state: UpdateState::NotAvailable,
            ..UpdateStatus::idle()
        })
        .unwrap(),
        json!({"state": "not-available"})
    );
}

#[test]
fn failure_categories_bucket_like_electron() {
    assert_eq!(
        update_failure_category(Some("request failed: ENOTFOUND api.github.com")),
        UpdateFailureCategory::Network
    );
    assert_eq!(
        update_failure_category(Some("signature verification failed: sha512 mismatch")),
        UpdateFailureCategory::Signature
    );
    assert_eq!(
        update_failure_category(Some("EACCES: permission denied")),
        UpdateFailureCategory::Permission
    );
    assert_eq!(
        update_failure_category(Some("ENOSPC: no space left on device")),
        UpdateFailureCategory::DiskSpace
    );
    assert_eq!(
        update_failure_category(Some("HttpError: 404 not found")),
        UpdateFailureCategory::NotFound
    );
    assert_eq!(
        update_failure_category(Some("cannot update in this mode")),
        UpdateFailureCategory::NotSupported
    );
    assert_eq!(
        update_failure_category(Some("something novel happened")),
        UpdateFailureCategory::Unknown
    );
    assert_eq!(
        update_failure_category(None),
        UpdateFailureCategory::Unknown
    );
}

#[test]
fn failure_outcomes_carry_phase_trigger_and_target_version() {
    let outcome = update_failure_outcome(
        Some("offline"),
        UpdatePhase::Download,
        UpdateTrigger::Automatic,
        Some("2.0.0".to_string()),
    );
    assert_eq!(outcome.event, "opr.renderer.update_failed");
    assert_eq!(outcome.phase, UpdatePhase::Download);
    assert_eq!(outcome.trigger, UpdateTrigger::Automatic);
    assert_eq!(outcome.to_version, Some("2.0.0".to_string()));
}

// ---------------------------------------------------------------- escalation

#[test]
fn escalation_latest_channel_uses_the_48h_rule() {
    let now = BASE_TIME;
    let input = |staged_at: i64| EscalationInput {
        channel: Channel::Latest,
        staged_at_ms: staged_at,
        now_ms: now,
        important: false,
        running_version: "0.10.4",
        latest_stable_version: Some("0.10.5"),
    };
    assert!(!evaluate_escalation(input(now - H48_MS + 1000)));
    assert!(evaluate_escalation(input(now - H48_MS)));
    assert!(evaluate_escalation(input(now - H48_MS - 1)));
}

#[test]
fn escalation_nightly_uses_importance_and_stable_comparison() {
    const fn input<'a>(running: &'a str, stable: Option<&'a str>) -> EscalationInput<'a> {
        EscalationInput {
            channel: Channel::Nightly,
            staged_at_ms: BASE_TIME,
            now_ms: BASE_TIME,
            important: false,
            running_version: running,
            latest_stable_version: stable,
        }
    }
    let important = EscalationInput {
        important: true,
        ..input("0.10.4-nightly.202607031330", None)
    };
    assert!(evaluate_escalation(important));
    assert!(evaluate_escalation(input(
        "0.10.4-nightly.202607031330",
        Some("0.10.4")
    )));
    assert!(!evaluate_escalation(input(
        "0.10.4-nightly.202607031330",
        Some("0.10.3")
    )));
    assert!(!evaluate_escalation(input(
        "0.10.4-nightly.202607031330",
        None
    )));
    assert!(!evaluate_escalation(input("not-a-version", Some("0.10.4"))));
}

// ---------------------------------------------------------------- storage

#[test]
fn storage_opens_beneath_the_state_root_and_stages_artifacts() {
    let harness = harness().build(FakeClient::new());
    let root = harness.updater_root.clone();
    assert!(root.starts_with(harness._keep.path()));
    assert!(root.join("staged").is_dir());
    assert!(root.join("tmp").is_dir());

    let artifact = harness
        .engine_storage_stage("2.1.0", b"installer-bytes")
        .unwrap();
    assert_eq!(artifact.meta.version, "2.1.0");
    assert_eq!(artifact.meta.size, "installer-bytes".len() as u64);
    assert!(artifact.path.starts_with(&root));
    assert_eq!(
        std::fs::read(&artifact.path).unwrap(),
        b"installer-bytes".to_vec()
    );

    let loaded = UpdaterStorage::open(harness._keep.path())
        .unwrap()
        .staged("2.1.0")
        .expect("artifact survives reopen");
    assert_eq!(
        loaded.meta.url,
        "https://releases.example.com/operator/latest.json"
    );
    assert_eq!(loaded.meta.size, 15);
}

#[test]
fn storage_records_interrupted_downloads_and_recovers_them() {
    let harness = harness().build(FakeClient::new());
    harness.engine_storage_begin("2.1.0", BASE_TIME).unwrap();

    let pending = UpdaterStorage::open(harness._keep.path())
        .unwrap()
        .pending_downloads();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].intent.version, "2.1.0");
    assert_eq!(
        pending[0].intent.url,
        "https://releases.example.com/operator/latest.json"
    );

    harness.engine_storage_stage("2.1.0", b"bytes").unwrap();
    assert!(UpdaterStorage::open(harness._keep.path())
        .unwrap()
        .pending_downloads()
        .is_empty());
}

#[test]
fn storage_prunes_stale_partials_only() {
    let harness = harness().build(FakeClient::new());
    harness.engine_storage_begin("2.1.0", BASE_TIME).unwrap();
    harness
        .engine_storage_begin("2.2.0", BASE_TIME - 8 * 24 * 60 * 60 * 1000)
        .unwrap();

    let pruned = UpdaterStorage::open(harness._keep.path())
        .unwrap()
        .prune_partials(BASE_TIME, 7 * 24 * 60 * 60 * 1000);
    assert_eq!(pruned, 1);

    let remaining = UpdaterStorage::open(harness._keep.path())
        .unwrap()
        .pending_downloads();
    assert_eq!(remaining.len(), 1);
    assert_eq!(remaining[0].intent.version, "2.1.0");
}

#[test]
fn storage_refuses_paths_outside_the_updater_directory() {
    let harness = harness().build(FakeClient::new());
    let storage = UpdaterStorage::open(harness._keep.path()).unwrap();
    let outside = harness._keep.path().join("elsewhere");
    std::fs::create_dir_all(&outside).unwrap();

    assert!(matches!(
        storage.ensure_inside(&outside),
        Err(StorageError::OutsideUpdaterDir)
    ));
    assert!(matches!(
        storage.ensure_inside(&harness._keep.path().join("updater-staged")),
        Err(StorageError::OutsideUpdaterDir)
    ));
    assert!(storage.ensure_inside(storage.root()).is_ok());

    assert!(matches!(
        storage.remove_staged("../2.1.0"),
        Err(StorageError::InvalidVersionName)
    ));
    assert!(matches!(
        storage.remove_staged(".hidden"),
        Err(StorageError::InvalidVersionName)
    ));
}

#[test]
fn storage_refuses_symlink_escapes() {
    let harness = harness().build(FakeClient::new());
    let storage = UpdaterStorage::open(harness._keep.path()).unwrap();
    let outside = harness._keep.path().join("escape-target");
    std::fs::create_dir_all(&outside).unwrap();
    #[cfg(unix)]
    {
        let link = storage.root().join("link");
        std::os::unix::fs::symlink(&outside, &link).unwrap();
        assert!(matches!(
            storage.ensure_inside(&link),
            Err(StorageError::OutsideUpdaterDir)
        ));
    }
}

// ---------------------------------------------------------------- engine

#[tokio::test]
async fn start_with_disabled_settings_skips_checks_and_keeps_retirement_capable() {
    let mut harness = harness();
    harness.settings.enabled = false;
    let h = harness.build(FakeClient::new().release_check("2.0.0"));

    let should_schedule = h.engine.start().await;

    assert!(!should_schedule);
    assert!(h.client.urls().is_empty());
    assert_eq!(h.engine.status(), UpdateStatus::idle());
}

#[test]
fn first_run_opt_in_policy_writes_expected_defaults() {
    assert_eq!(
        first_run_settings(FirstRunAnswer::Decline),
        UpdateSettings {
            enabled: false,
            channel: Channel::Latest,
            nightly_ack: false,
            feature: None,
        }
    );
    assert_eq!(
        first_run_settings(FirstRunAnswer::EnableLatest),
        UpdateSettings {
            enabled: true,
            channel: Channel::Latest,
            nightly_ack: false,
            feature: None,
        }
    );
    assert_eq!(
        first_run_settings(FirstRunAnswer::EnableNightlyAcked),
        UpdateSettings {
            enabled: true,
            channel: Channel::Nightly,
            nightly_ack: true,
            feature: None,
        }
    );
    assert_eq!(
        first_run_settings(FirstRunAnswer::EnableNightlyDeclined),
        first_run_settings(FirstRunAnswer::EnableLatest)
    );
}

#[tokio::test]
async fn launch_runs_an_automatic_check_that_downloads_and_stages() {
    let h = harness().build(
        FakeClient::new()
            .release_check("2.0.0")
            .progress_plan(&[50])
            .download_bytes(b"pkg"),
    );

    let should_schedule = h.engine.start().await;

    assert!(should_schedule);
    assert_eq!(
        h.client.urls(),
        vec!["https://releases.example.com/operator/latest.json"]
    );
    let last = h.sink.statuses().last().unwrap().clone();
    assert_eq!(last.state, UpdateState::Downloaded);
    assert_eq!(last.version.as_deref(), Some("2.0.0"));
    let telemetry = h.sink.telemetry();
    let downloaded = telemetry
        .iter()
        .find(|o| o.event == "opr.renderer.update_downloaded")
        .expect("downloaded telemetry retained");
    assert_eq!(downloaded.trigger, UpdateTrigger::Automatic);
    assert!(h
        .updater_root
        .join("staged")
        .join("2.0.0")
        .join("update.bin")
        .exists());
}

#[tokio::test]
async fn automatic_failure_suppresses_status_but_keeps_telemetry() {
    let h = harness().build(FakeClient::new().failed_check("feed failed"));

    h.engine.start().await;

    let statuses = h.sink.statuses();
    assert!(
        statuses
            .iter()
            .all(|s| matches!(s.state, UpdateState::Checking | UpdateState::Idle)),
        "no error status may leak into the UI: {statuses:?}"
    );
    assert_eq!(h.engine.status(), UpdateStatus::idle());
    let outcomes = h.sink.telemetry();
    assert_eq!(outcomes.len(), 1);
    assert_eq!(outcomes[0].event, "opr.renderer.update_failed");
    assert_eq!(outcomes[0].phase, UpdatePhase::Check);
    assert_eq!(outcomes[0].trigger, UpdateTrigger::Automatic);
}

#[tokio::test]
async fn automatic_error_restores_previous_status_after_checking() {
    let h = harness().build(
        FakeClient::new()
            .release_check("2.0.0")
            .failed_check("feed failed"),
    );
    h.engine.manual_check(CheckOptions::default()).await;
    assert_eq!(h.engine.status().state, UpdateState::Available);

    h.engine.run_hourly_tick().await;

    assert_eq!(
        h.engine.status(),
        UpdateStatus {
            state: UpdateState::Available,
            version: Some("2.0.0".to_string()),
            ..UpdateStatus::idle()
        }
    );
}

#[tokio::test]
async fn automatic_error_restores_previous_status_after_download_progress() {
    let h = harness().build(
        FakeClient::new()
            .release_check("2.0.0")
            .release_check("2.1.0")
            .progress_plan(&[42])
            .failed_download("download failed"),
    );
    h.engine.manual_check(CheckOptions::default()).await;

    h.engine.run_hourly_tick().await;

    assert_eq!(
        h.engine.status(),
        UpdateStatus {
            state: UpdateState::Available,
            version: Some("2.0.0".to_string()),
            ..UpdateStatus::idle()
        }
    );
    let telemetry = h.sink.telemetry();
    let failures: Vec<_> = telemetry
        .iter()
        .filter(|o| o.event == "opr.renderer.update_failed")
        .collect();
    assert_eq!(failures.len(), 1);
    assert_eq!(failures[0].phase, UpdatePhase::Download);
}

#[tokio::test]
async fn automatic_error_restores_the_enriched_staged_status() {
    let h = harness().build(
        FakeClient::new()
            .release_check("2.1.0")
            .progress_plan(&[])
            .download_bytes(b"pkg")
            .failed_check("feed failed"),
    );
    h.engine.manual_check(CheckOptions::default()).await;
    h.engine.download_now(None).await;
    let expected = h.engine.status();
    assert_eq!(expected.state, UpdateState::Downloaded);

    h.engine.run_hourly_tick().await;

    assert_eq!(staged_at(&h.engine.status()), staged_at(&expected));
    assert_eq!(h.engine.status().state, UpdateState::Downloaded);
    assert_eq!(h.engine.status().version.as_deref(), Some("2.1.0"));
}

#[tokio::test]
async fn escalation_progress_is_not_lost_to_an_automatic_failure() {
    let h = harness().build(
        FakeClient::new()
            .release_check("2.1.0")
            .progress_plan(&[])
            .download_bytes(b"pkg")
            .failed_check("feed failed"),
    );
    h.engine.manual_check(CheckOptions::default()).await;
    h.engine.download_now(None).await;
    *h.clock.lock().unwrap() = BASE_TIME + 49 * 60 * 60 * 1000;
    h.engine.run_escalation_tick().await;
    assert!(h.engine.status().escalated == Some(true));

    h.engine.run_hourly_tick().await;

    assert!(h.engine.status().escalated == Some(true));
    assert_eq!(h.engine.status().state, UpdateState::Downloaded);
}

#[tokio::test]
async fn manual_check_carries_request_ids_and_reports_available() {
    let h = harness().build(FakeClient::new().release_check("2.0.0"));

    h.engine
        .manual_check(CheckOptions {
            request_id: Some("feature-update-1".to_string()),
            ..CheckOptions::default()
        })
        .await;

    let statuses = h.sink.statuses();
    assert!(statuses
        .iter()
        .any(|s| s.state == UpdateState::Checking
            && s.request_id.as_deref() == Some("feature-update-1")));
    let last = statuses.last().unwrap();
    assert_eq!(last.state, UpdateState::Available);
    assert_eq!(last.version.as_deref(), Some("2.0.0"));
    assert_eq!(last.request_id.as_deref(), Some("feature-update-1"));
    assert!(!h.client.urls()[0].contains("pr"));
}

#[tokio::test]
async fn concurrent_operations_leave_the_latest_owned_status_visible() {
    let h = harness().build(
        FakeClient::new()
            .release_check("1.9.0")
            .release_check("2.0.0-pr2709.1"),
    );

    h.engine.manual_check(CheckOptions::default()).await;
    assert_eq!(h.engine.status().version.as_deref(), Some("1.9.0"));
    h.releases.set_list(Ok(vec![release(
        "v0.2.0-pr2709.202607061200",
        true,
        BASE_TIME - 24 * 60 * 60 * 1000,
        Some(marker(2709)),
    )]));
    h.engine
        .manual_check(CheckOptions {
            settings: Some(pinned(2709)),
            request_id: Some("feature-2709".to_string()),
        })
        .await;

    assert_eq!(
        h.engine.status(),
        UpdateStatus {
            state: UpdateState::Available,
            version: Some("2.0.0-pr2709.1".to_string()),
            request_id: Some("feature-2709".to_string()),
            ..UpdateStatus::idle()
        }
    );
    assert!(h.client.urls()[1].ends_with("/pr2709.json"));
}

#[tokio::test]
async fn download_progress_clamps_percentages() {
    let h = harness().build(
        FakeClient::new()
            .release_check("2.0.0")
            .progress_plan(&[250, 33])
            .download_bytes(b"pkg"),
    );

    h.engine.manual_check(CheckOptions::default()).await;
    h.engine.download_now(Some("req-dl".to_string())).await;

    let percents: Vec<u32> = h
        .sink
        .statuses()
        .iter()
        .filter(|s| s.state == UpdateState::Downloading)
        .map(|s| s.percent.unwrap_or(0))
        .collect();
    assert_eq!(percents, vec![100, 33]);
    let last = h.sink.statuses().last().unwrap().clone();
    assert_eq!(last.state, UpdateState::Downloaded);
    assert_eq!(last.request_id.as_deref(), Some("req-dl"));
}

#[tokio::test]
async fn downloaded_flow_keeps_request_ownership_through_rebroadcasts() {
    let h = harness().build(
        FakeClient::new()
            .release_check("2.0.0-pr2709.1")
            .progress_plan(&[10])
            .download_bytes(b"pkg"),
    );
    h.engine.manual_check(CheckOptions::default()).await;
    h.engine
        .download_now(Some("feature-2709".to_string()))
        .await;
    *h.clock.lock().unwrap() = BASE_TIME + 49 * 60 * 60 * 1000;
    h.engine.run_escalation_tick().await;

    assert_eq!(
        h.engine.status().state,
        UpdateState::Downloaded,
        "escalation rebroadcast keeps the staged shape"
    );
    assert_eq!(
        h.engine.status().request_id.as_deref(),
        Some("feature-2709")
    );
}

#[tokio::test]
async fn manifest_404s_broadcast_friendly_errors_per_operation() {
    let err = "Cannot find latest-mac.yml in the latest release artifacts\nHttpError: 404 \"method: GET url: https://x/latest-mac.yml\"";

    let check_harness = harness().build(FakeClient::new().failed_check(err));
    check_harness
        .engine
        .manual_check(CheckOptions::default())
        .await;
    assert_eq!(
        check_harness.engine.status().message.as_deref(),
        Some(MANIFEST_404_CHECK_MESSAGE)
    );

    let download_harness = harness().build(
        FakeClient::new()
            .release_check("2.0.0")
            .failed_download(err),
    );
    download_harness
        .engine
        .manual_check(CheckOptions::default())
        .await;
    download_harness.engine.download_now(None).await;
    assert_eq!(
        download_harness.engine.status().message.as_deref(),
        Some(MANIFEST_404_DOWNLOAD_MESSAGE)
    );
}

#[tokio::test]
async fn manifest_404_restores_a_staged_build_instead_of_erroring() {
    let err = "Cannot find latest-mac.yml artifacts\nHttpError: 404";
    let h = harness().build(
        FakeClient::new()
            .release_check("2.1.0")
            .progress_plan(&[])
            .download_bytes(b"pkg")
            .failed_check(err),
    );
    h.engine.manual_check(CheckOptions::default()).await;
    h.engine.download_now(None).await;
    assert_eq!(h.engine.status().state, UpdateState::Downloaded);

    h.engine.manual_check(CheckOptions::default()).await;

    assert_eq!(h.engine.status().state, UpdateState::Downloaded);
    assert_eq!(h.engine.status().version.as_deref(), Some("2.1.0"));
}

#[tokio::test]
async fn non_manifest_404_errors_surface_verbatim() {
    let err = "HttpError: 404 \"method: GET url: https://x/some-file.png\"";
    let h = harness().build(FakeClient::new().failed_check(err));

    h.engine.manual_check(CheckOptions::default()).await;

    assert_eq!(h.engine.status().state, UpdateState::Error);
    assert_eq!(h.engine.status().message.as_deref(), Some(err));
}

#[tokio::test]
async fn unpackaged_shell_reports_unsupported_without_touching_settings() {
    let mut builder = harness();
    builder.packaged = false;
    let h = builder.build(
        FakeClient::new()
            .release_check("2.0.0")
            .download_bytes(b"pkg"),
    );

    h.engine
        .manual_check(CheckOptions {
            request_id: Some("req-2".to_string()),
            ..CheckOptions::default()
        })
        .await;
    h.engine.return_home(Some("req-3".to_string())).await;
    h.engine.download_now(Some("req-4".to_string())).await;

    assert_eq!(h.settings.writes(), Vec::new());
    assert!(h.client.urls().is_empty());
    let statuses = h.sink.statuses();
    assert!(statuses.iter().all(|s| s.state == UpdateState::Unsupported));
    assert_eq!(
        statuses.last().unwrap().message.as_deref(),
        Some(UNSUPPORTED_MESSAGE)
    );
    assert!(h
        .sink
        .telemetry()
        .iter()
        .any(|o| o.event == "opr.renderer.update_unsupported"
            && o.error_category == Some(UpdateFailureCategory::NotSupported)));
}

#[tokio::test]
async fn return_home_clears_the_pin_through_settings_before_checking_home() {
    let mut builder = harness();
    builder.settings = UpdateSettings {
        enabled: true,
        channel: Channel::Nightly,
        nightly_ack: true,
        feature: Some(FeaturePin { pr: 2270 }),
    };
    let h = builder.build(FakeClient::new().no_release());

    h.engine.return_home(Some("req-1".to_string())).await;

    assert_eq!(
        h.client.urls(),
        vec!["https://releases.example.com/operator/nightly.json"]
    );
    let writes = h.settings.writes();
    assert_eq!(writes.len(), 1);
    assert_eq!(writes[0].feature, None);
    assert_eq!(writes[0].channel, Channel::Nightly);
    assert!(writes[0].nightly_ack);
    assert_eq!(h.settings.order(), vec!["read", "write"]);
    assert_eq!(h.client.event_log(), vec!["check"]);
    let statuses = h.sink.statuses();
    assert!(matches!(statuses[0].state, UpdateState::Checking));
    assert!(statuses
        .iter()
        .any(|s| s.request_id.as_deref() == Some("req-1")));
}

#[tokio::test]
async fn return_home_to_an_older_home_channel_still_offers_it() {
    let mut builder = harness();
    builder.app_version = "2.0.0".to_string();
    builder.settings = UpdateSettings {
        enabled: true,
        channel: Channel::Latest,
        nightly_ack: false,
        feature: Some(FeaturePin { pr: 2270 }),
    };
    let h = builder.build(FakeClient::new().release_check("1.9.9"));

    h.engine.return_home(Some("req-home".to_string())).await;

    assert!(h.client.urls()[0].ends_with("/latest.json"));
    assert_eq!(
        h.engine.status(),
        UpdateStatus {
            state: UpdateState::Available,
            version: Some("1.9.9".to_string()),
            request_id: Some("req-home".to_string()),
            ..UpdateStatus::idle()
        },
        "allowDowngrade parity: an older home-channel build must still be offered"
    );
}

#[tokio::test]
async fn return_home_without_a_pin_still_checks_the_home_channel() {
    let h = harness().build(FakeClient::new().no_release());

    h.engine.return_home(None).await;

    assert!(h.settings.writes().is_empty());
    assert_eq!(
        h.client.urls(),
        vec!["https://releases.example.com/operator/latest.json"]
    );
}

#[tokio::test]
async fn retirement_poll_clears_a_retired_pin_only_if_unchanged() {
    let mut builder = harness();
    builder.settings = pinned(2709);
    let h = builder.build(FakeClient::new());

    h.engine.run_retirement_tick().await;

    let writes = h.settings.writes();
    assert_eq!(writes.len(), 1);
    assert_eq!(writes[0].feature, None);
    assert_eq!(h.releases.list_calls(), 1);

    h.releases.set_list(Ok(vec![release(
        "v0.2.0-pr2710.202607061200",
        true,
        BASE_TIME - 24 * 60 * 60 * 1000,
        Some(marker(2710)),
    )]));
    h.settings.replace_current(UpdateSettings {
        enabled: true,
        channel: Channel::Nightly,
        nightly_ack: true,
        feature: Some(FeaturePin { pr: 2710 }),
    });
    h.engine.run_retirement_tick().await;

    let writes = h.settings.writes();
    assert_eq!(writes.len(), 1, "a newly selected live pin survives");
    assert_eq!(h.settings.current().feature, Some(FeaturePin { pr: 2710 }));
}

#[tokio::test]
async fn settings_write_precedes_channel_change_for_option_settings() {
    let h = harness().build(FakeClient::new().no_release());
    h.releases.set_list(Ok(vec![release(
        "v0.2.0-pr2711.202607061200",
        true,
        BASE_TIME - 24 * 60 * 60 * 1000,
        Some(marker(2711)),
    )]));

    h.engine
        .manual_check(CheckOptions {
            settings: Some(pinned(2711)),
            request_id: None,
        })
        .await;

    assert_eq!(h.settings.order(), vec!["write", "read"]);
    assert!(h.client.urls()[0].ends_with("/pr2711.json"));
    assert_eq!(h.settings.current().feature, Some(FeaturePin { pr: 2711 }));
}

#[tokio::test]
async fn apply_settings_arms_and_disarms_the_scheduler_without_local_writes() {
    let mut builder = harness();
    builder.settings.enabled = false;
    let h = builder.build(FakeClient::new());

    assert!(!h.engine.automatic_scheduled_snapshot());
    h.engine
        .apply_settings(UpdateSettings {
            enabled: true,
            channel: Channel::Latest,
            nightly_ack: false,
            feature: None,
        })
        .await;
    assert!(h.engine.automatic_scheduled_snapshot());
    h.engine
        .apply_settings(UpdateSettings {
            enabled: false,
            channel: Channel::Latest,
            nightly_ack: false,
            feature: None,
        })
        .await;
    assert!(!h.engine.automatic_scheduled_snapshot());
    h.engine.run_hourly_tick().await;
    assert!(h.client.urls().is_empty());
    assert!(h.settings.writes().is_empty());
}

#[tokio::test]
async fn hourly_ticks_coalesce_behind_an_in_flight_check() {
    let h = harness().build(FakeClient::new().hold_first_check().release_check("2.1.0"));

    let first = {
        let engine = h.engine.clone();
        tokio::spawn(async move { engine.run_hourly_tick().await })
    };
    for _ in 0..200 {
        if h.engine.automatic_active_snapshot() {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(5)).await;
    }
    assert!(
        h.engine.automatic_active_snapshot(),
        "first tick never started"
    );
    h.engine.run_hourly_tick().await;
    h.client.release_gate().notify_one();
    first.await.unwrap();
    tokio::time::sleep(std::time::Duration::from_millis(20)).await;

    assert_eq!(h.client.urls().len(), 1, "the overlapping tick was dropped");

    h.engine.run_hourly_tick().await;
    assert_eq!(h.client.urls().len(), 2, "later ticks still run");
}

#[tokio::test]
async fn settings_read_failures_are_logged_and_retried_by_later_ticks() {
    let h = harness().build(FakeClient::new().no_release());
    h.settings.fail_next_read("settings locked");

    let should_schedule = h.engine.start().await;

    assert!(should_schedule);
    assert!(h.client.urls().is_empty());
    h.engine.run_hourly_tick().await;
    assert_eq!(h.client.urls().len(), 1);
}

#[tokio::test]
async fn install_update_is_a_recorded_stop_with_reason() {
    let h = harness().build(
        FakeClient::new()
            .release_check("2.0.0")
            .download_bytes(b"pkg"),
    );
    h.engine.manual_check(CheckOptions::default()).await;
    h.engine.download_now(None).await;

    let error = h.engine.install_update().unwrap_err();

    assert_eq!(error, APPLY_DEFERRED_MESSAGE);
    assert!(
        std::fs::read_dir(h.updater_root.join("tmp"))
            .unwrap()
            .count()
            == 0
    );
}

#[tokio::test]
async fn active_feature_reporting_parses_the_running_version() {
    let mut builder = harness();
    builder.app_version = "0.2.0-pr2270.202607061200".to_string();
    let feature_harness = builder.build(FakeClient::new());
    assert_eq!(feature_harness.engine.active_feature(), Some(2270));

    let stable_harness = harness().build(FakeClient::new());
    assert_eq!(stable_harness.engine.active_feature(), None);
}

#[tokio::test]
async fn nightly_escalation_uses_importance_then_stale_stable_comparison() {
    let mut builder = harness();
    builder.settings.channel = Channel::Nightly;
    builder.settings.nightly_ack = true;
    let h = builder.build(
        FakeClient::new()
            .release_check("2.1.0-nightly.202608010000")
            .progress_plan(&[])
            .download_bytes(b"pkg"),
    );
    h.feeds.state.lock().unwrap().important = true;
    h.engine.manual_check(CheckOptions::default()).await;
    h.engine.download_now(None).await;
    assert_eq!(
        h.engine.status().escalated,
        Some(true),
        "an important nightly escalates immediately"
    );

    h.feeds.state.lock().unwrap().important = false;
    h.feeds.state.lock().unwrap().stable = Some("1.0.1".to_string());
    *h.clock.lock().unwrap() = BASE_TIME + ESCALATION_STEP;
    h.engine.run_escalation_tick().await;
    assert_eq!(
        h.engine.status().escalated,
        Some(true),
        "a nightly behind stable escalates"
    );

    h.feeds.state.lock().unwrap().stable = Some("0.9.0".to_string());
    h.engine.run_escalation_tick().await;
    assert_eq!(h.engine.status().escalated, Some(false));
}

#[tokio::test]
async fn latest_channel_escalates_after_forty_eight_hours_via_timer() {
    let h = harness().build(
        FakeClient::new()
            .release_check("2.1.0")
            .download_bytes(b"pkg"),
    );
    h.engine.manual_check(CheckOptions::default()).await;
    h.engine.download_now(None).await;
    assert_eq!(h.engine.status().escalated, Some(false));

    *h.clock.lock().unwrap() = BASE_TIME + 47 * 60 * 60 * 1000;
    h.engine.run_escalation_tick().await;
    assert_eq!(h.engine.status().escalated, Some(false));

    *h.clock.lock().unwrap() = BASE_TIME + 49 * 60 * 60 * 1000;
    h.engine.run_escalation_tick().await;
    assert_eq!(h.engine.status().escalated, Some(true));
}

#[tokio::test]
async fn download_progress_broadcasts_through_engine_state_and_gates_escalation() {
    let h = harness().build(
        FakeClient::new()
            .release_check("2.1.0")
            .progress_plan(&[100])
            .download_bytes(b"pkg")
            .release_check("2.2.0")
            .progress_plan(&[30])
            .download_bytes(b"pkg2")
            .hold_first_download(),
    );
    h.engine.manual_check(CheckOptions::default()).await;
    h.engine.download_now(None).await;
    assert_eq!(
        h.engine.status().version.as_deref(),
        Some("2.1.0"),
        "first download stages the baseline build"
    );

    h.engine.manual_check(CheckOptions::default()).await;
    let streamed = {
        let engine = h.engine.clone();
        tokio::spawn(async move { engine.download_now(None).await })
    };
    let mut surfaced = false;
    for _ in 0..400 {
        if h.engine.status().state == UpdateState::Downloading {
            surfaced = true;
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(5)).await;
    }
    assert!(surfaced, "streaming progress must reach updates_status");

    *h.clock.lock().unwrap() = BASE_TIME + 49 * 60 * 60 * 1000;
    h.engine.run_escalation_tick().await;

    assert_eq!(
        h.engine.status(),
        UpdateStatus {
            state: UpdateState::Downloading,
            percent: Some(30),
            ..UpdateStatus::idle()
        },
        "an in-flight download must own the status stream over the stale staged row"
    );

    h.client.release_download_gate().notify_one();
    streamed.await.unwrap();
    assert_eq!(h.engine.status().version.as_deref(), Some("2.2.0"));
}

#[tokio::test]
async fn failed_real_download_records_recovery_intent() {
    let h = harness().build(
        FakeClient::new()
            .release_check("3.0.0")
            .failed_download("offline"),
    );
    h.engine.manual_check(CheckOptions::default()).await;
    h.engine.download_now(Some("req-dl".to_string())).await;

    let pending = UpdaterStorage::open(h._keep.path())
        .unwrap()
        .pending_downloads();
    assert_eq!(pending.len(), 1);
    assert_eq!(pending[0].intent.version, "3.0.0");
    assert_eq!(
        pending[0].intent.url,
        "https://releases.example.com/operator/latest.json"
    );
    assert_eq!(h.engine.status().state, UpdateState::Error);
}

#[test]
fn recover_sweeps_stale_intents_and_reports_pending() {
    let keep = tempfile_guard::TempDirGuard::create("recover");
    let storage = UpdaterStorage::open(keep.path()).unwrap();
    storage
        .begin_download(
            "2.1.0",
            "https://releases.example.com/latest.json",
            BASE_TIME,
        )
        .unwrap();
    storage
        .begin_download(
            "2.2.0",
            "https://releases.example.com/latest.json",
            BASE_TIME - PARTIAL_MAX_AGE_MS - 1,
        )
        .unwrap();

    let summary = recover_interrupted(&storage, BASE_TIME, PARTIAL_MAX_AGE_MS);

    assert_eq!(
        summary,
        RecoverySummary {
            pruned: 1,
            pending: 1,
        }
    );
    let remaining: Vec<String> = UpdaterStorage::open(keep.path())
        .unwrap()
        .pending_downloads()
        .into_iter()
        .map(|record| record.intent.version)
        .collect();
    assert_eq!(remaining, vec!["2.1.0"]);
}

const ESCALATION_STEP: i64 = 30 * 60 * 1000;

fn release(
    tag_name: &str,
    prerelease: bool,
    published_offset_ms: i64,
    body: Option<String>,
) -> GitHubRelease {
    let published = chrono_like_iso(published_offset_ms);
    GitHubRelease {
        tag_name: tag_name.to_string(),
        name: format!("Feature build {tag_name}"),
        prerelease,
        published_at: published,
        body,
    }
}

fn marker(pr: i64) -> String {
    format!("<!-- opr-feature-build: {{\"pr\":{pr},\"base\":\"main\",\"sha\":\"abc1234\",\"slug\":\"pr{pr}\"}} -->")
}

fn chrono_like_iso(epoch_ms: i64) -> String {
    let secs = epoch_ms.div_euclid(1000);
    let millis = epoch_ms.rem_euclid(1000);
    let days = secs.div_euclid(86_400);
    let tod = secs.rem_euclid(86_400);
    let (y, mo, d) = civil_from_days(days);
    format!(
        "{y:04}-{mo:02}-{d:02}T{:02}:{:02}:{:02}.{millis:03}Z",
        tod / 3600,
        (tod % 3600) / 60,
        tod % 60
    )
}

fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

trait HarnessExtras {
    fn engine_storage_stage(
        &self,
        version: &str,
        bytes: &[u8],
    ) -> Result<super::storage::StagedArtifact, StorageError>;
    fn engine_storage_begin(&self, version: &str, at: i64) -> Result<(), StorageError>;
}

impl HarnessExtras for Harness {
    fn engine_storage_stage(
        &self,
        version: &str,
        bytes: &[u8],
    ) -> Result<super::storage::StagedArtifact, StorageError> {
        self.engine.stage_bytes_for_test(version, bytes)
    }

    fn engine_storage_begin(&self, version: &str, at: i64) -> Result<(), StorageError> {
        self.engine.begin_bytes_for_test(version, at)
    }
}

// ---------------------------------------------------------------- release config

#[test]
fn baked_release_config_feed_base_url_is_used_when_env_absent() {
    let plugins = json!({"operator-updates": {"feedBaseUrl": "https://github.com/OmarAly92/operator/releases/latest/download/"}});
    assert_eq!(
        super::resolve_feed_base_url(None, Some(&plugins)),
        Some("https://github.com/OmarAly92/operator/releases/latest/download/".to_string())
    );
}

#[test]
fn env_feed_url_overrides_the_baked_release_config() {
    let plugins = json!({"operator-updates": {"feedBaseUrl": "https://github.com/OmarAly92/operator/releases/latest/download/"}});
    assert_eq!(
        super::resolve_feed_base_url(Some("http://127.0.0.1:9876/".to_string()), Some(&plugins)),
        Some("http://127.0.0.1:9876/".to_string())
    );
    assert_eq!(
        super::resolve_feed_base_url(Some(String::new()), Some(&plugins)),
        Some("https://github.com/OmarAly92/operator/releases/latest/download/".to_string())
    );
}

#[test]
fn empty_or_absent_baked_config_falls_through_to_none() {
    assert_eq!(super::resolve_feed_base_url(None, None), None);
    assert_eq!(super::resolve_feed_base_url(None, Some(&json!({}))), None);
    assert_eq!(
        super::resolve_feed_base_url(None, Some(&json!({"operator-updates": {}}))),
        None
    );
    assert_eq!(
        super::resolve_feed_base_url(
            None,
            Some(&json!({"operator-updates": {"feedBaseUrl": ""}}))
        ),
        None
    );
    assert_eq!(
        super::resolve_feed_base_url(
            None,
            Some(&json!({"operator-updates": {"feedBaseUrl": 42}}))
        ),
        None
    );
}

#[test]
fn tauri_release_conf_bakes_the_production_updater_surface() {
    let raw = std::fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tauri.release.conf.json"
    ))
    .expect("tauri.release.conf.json must exist beside the crate");
    let conf: serde_json::Value = serde_json::from_str(&raw).expect("release conf is valid JSON");
    assert_eq!(conf["bundle"]["createUpdaterArtifacts"], json!(true));
    // The bundler refuses createUpdaterArtifacts unless plugins > updater
    // exists; the verification key itself is compiled in, not configured here.
    assert!(
        conf["plugins"].get("updater").is_some(),
        "release conf must declare the updater plugin config for the bundler"
    );
    let base = conf["plugins"]["operator-updates"]["feedBaseUrl"]
        .as_str()
        .expect("release conf bakes feedBaseUrl");
    assert!(
        base.starts_with("https://"),
        "production feed base must be https"
    );
    assert!(
        base.ends_with("/releases/latest/download/"),
        "feed base must target the latest download root, got {base}"
    );
}
