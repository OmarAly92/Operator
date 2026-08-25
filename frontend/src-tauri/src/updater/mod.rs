pub mod channel;
pub mod escalation;
pub mod status;
pub mod storage;
#[cfg(test)]
mod tests;

use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex};

use tauri_plugin_updater::UpdaterExt as _;

use channel::{ActiveChannel, Channel, ReleasesSource, UpdateSettings};
use escalation::EscalationFeeds;
use status::{UpdateOutcome, UpdatePhase, UpdateState, UpdateStatus, UpdateTrigger};
use storage::UpdaterStorage;

pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

pub const AUTOMATIC_CHECK_INTERVAL_MS: u64 = 60 * 60 * 1000;
pub const ESCALATION_INTERVAL_MS: u64 = 30 * 60 * 1000;
pub const RETIREMENT_POLL_INTERVAL_MS: u64 = 30 * 60 * 1000;
pub const UNSUPPORTED_MESSAGE: &str = "Updates are only available in the installed app.";
pub const MANIFEST_404_CHECK_MESSAGE: &str =
    "Couldn't check for updates — the update information was not found on the server.";
pub const MANIFEST_404_DOWNLOAD_MESSAGE: &str =
    "Download failed — the update file was not found on the server.";
pub const APPLY_DEFERRED_MESSAGE: &str =
    "update installation is deferred to the packaging task: the pinned updater plugin writes installer and recovery files to OS-default temp and cache directories that are not configurable";

/// Persisted-settings access behind the updater's serialized operations. The
/// store of record is the daemon's `/api/v1/settings`; writes MUST complete
/// before the engine changes its active channel state.
pub trait SettingsSource: Send + Sync {
    fn read<'a>(&'a self) -> BoxFuture<'a, Result<UpdateSettings, String>>;
    fn write<'a>(&'a self, settings: UpdateSettings) -> BoxFuture<'a, Result<(), String>>;
}

pub type ProgressCallback = Box<dyn FnMut(u32) + Send>;

/// A release the feed offered to the shell.
pub trait ReleaseHandle {
    fn version(&self) -> String;
}

/// Transport seam over the update feed: manifest check plus verified artifact
/// download. Production wires the pinned tauri-plugin-updater client; tests
/// inject fakes.
pub trait FeedClient: Send + Sync {
    type Release: ReleaseHandle + Send + 'static;
    fn check<'a>(&'a self, url: String) -> BoxFuture<'a, Result<Option<Self::Release>, String>>;
    fn download<'a>(
        &'a self,
        release: Self::Release,
        progress: ProgressCallback,
    ) -> BoxFuture<'a, Result<Vec<u8>, String>>;
}

/// Forwards statuses and telemetry outcomes to the renderer window.
pub trait StatusSink: Send + Sync {
    fn emit_status(&self, status: &UpdateStatus);
    fn emit_telemetry(&self, outcome: &UpdateOutcome);
}

pub type ClockFn = Arc<dyn Fn() -> i64 + Send + Sync>;

#[derive(Debug, Clone)]
pub struct EngineConfig {
    pub packaged: bool,
    pub app_version: String,
    pub feed_base_url: Option<String>,
    pub public_key: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Operation {
    AutomaticCheck,
    ManualCheck,
    ManualDownload,
    SettingsWrite,
    ReturnHome,
}

impl Operation {
    fn initial_phase(self) -> UpdatePhase {
        if self == Operation::ManualDownload {
            UpdatePhase::Download
        } else {
            UpdatePhase::Check
        }
    }

    fn trigger(self) -> UpdateTrigger {
        if self == Operation::AutomaticCheck {
            UpdateTrigger::Automatic
        } else {
            UpdateTrigger::Manual
        }
    }
}

#[derive(Clone)]
struct StagedUpdate {
    version: String,
    at_ms: i64,
    escalated: bool,
    request_id: Option<String>,
}

pub struct EngineState {
    last_status: UpdateStatus,
    independent_revision: u64,
    active_op: Option<Operation>,
    active_request_id: Option<String>,
    phase: UpdatePhase,
    pending_version: Option<String>,
    automatic_snapshot: Option<(UpdateStatus, u64)>,
    staged: Option<StagedUpdate>,
    automatic_scheduled: bool,
    retirement_busy: bool,
}

/// State mutations and renderer emission behind one shared handle, cloneable
/// into download-progress callbacks that must update the same status stream.
#[derive(Clone)]
struct Broadcast {
    state: Arc<Mutex<EngineState>>,
    sink: Arc<dyn StatusSink>,
}

impl Broadcast {
    fn with_state<T>(&self, read: impl FnOnce(&mut EngineState) -> T) -> T {
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        read(&mut guard)
    }

    fn begin(&self, op: Operation, request_id: Option<String>) {
        self.with_state(|state| {
            state.active_op = Some(op);
            state.active_request_id = request_id;
            state.phase = op.initial_phase();
        });
    }

    fn end(&self, op: Operation) {
        self.with_state(|state| {
            state.active_op = None;
            state.active_request_id = None;
            state.pending_version = None;
            if op == Operation::AutomaticCheck {
                state.automatic_snapshot = None;
            }
        });
    }

    fn broadcast(&self, status: UpdateStatus, independent: bool) {
        self.with_state(|state| {
            if independent {
                state.independent_revision += 1;
                if state.active_op == Some(Operation::AutomaticCheck) {
                    if let Some(snapshot) = state.automatic_snapshot.as_mut() {
                        *snapshot = (status.clone(), state.independent_revision);
                    }
                }
            }
            state.last_status = status.clone();
        });
        self.sink.emit_status(&status);
    }

    fn broadcast_owned(&self, mut status: UpdateStatus) {
        let automatic = self.with_state(|state| {
            if let Some(request_id) = &state.active_request_id {
                status.request_id = Some(request_id.clone());
            }
            state.active_op == Some(Operation::AutomaticCheck)
        });
        self.broadcast(status, !automatic);
    }
}

/// The updater state machine. Every mutating flow runs serialized on one
/// operation lock so checks, downloads, settings writes, and return-home can
/// never interleave.
pub struct UpdaterEngine<C: FeedClient> {
    shared: Broadcast,
    op_lock: tokio::sync::Mutex<()>,
    release_slot: Mutex<Option<(C::Release, String)>>,
    client: Arc<C>,
    settings: Arc<dyn SettingsSource>,
    feeds: Arc<dyn EscalationFeeds>,
    releases: Arc<dyn ReleasesSource>,
    storage: UpdaterStorage,
    sink: Arc<dyn StatusSink>,
    clock: ClockFn,
    config: EngineConfig,
}

#[derive(Debug, Default, Clone)]
pub struct CheckOptions {
    pub settings: Option<UpdateSettings>,
    pub request_id: Option<String>,
}

impl<C: FeedClient> UpdaterEngine<C> {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        client: Arc<C>,
        settings: Arc<dyn SettingsSource>,
        feeds: Arc<dyn EscalationFeeds>,
        releases: Arc<dyn ReleasesSource>,
        storage: UpdaterStorage,
        sink: Arc<dyn StatusSink>,
        clock: ClockFn,
        config: EngineConfig,
    ) -> Self {
        Self {
            shared: Broadcast {
                state: Arc::new(Mutex::new(EngineState {
                    last_status: UpdateStatus::idle(),
                    independent_revision: 0,
                    active_op: None,
                    active_request_id: None,
                    phase: UpdatePhase::Check,
                    pending_version: None,
                    automatic_snapshot: None,
                    staged: None,
                    automatic_scheduled: false,
                    retirement_busy: false,
                })),
                sink: sink.clone(),
            },
            op_lock: tokio::sync::Mutex::new(()),
            release_slot: Mutex::new(None),
            client,
            settings,
            feeds,
            releases,
            storage,
            sink,
            clock,
            config,
        }
    }

    pub fn active_feature(&self) -> Option<i64> {
        channel::parse_feature_build(&self.config.app_version)
    }

    pub fn releases_source(&self) -> &Arc<dyn ReleasesSource> {
        &self.releases
    }

    pub fn clock_snapshot(&self) -> i64 {
        (self.clock)()
    }

    pub fn status(&self) -> UpdateStatus {
        self.with_state(|state| state.last_status.clone())
    }

    fn with_state<T>(&self, read: impl FnOnce(&mut EngineState) -> T) -> T {
        self.shared.with_state(read)
    }

    fn now_ms(&self) -> i64 {
        (self.clock)()
    }

    fn begin(&self, op: Operation, request_id: Option<String>) {
        self.shared.begin(op, request_id);
    }

    fn end(&self, op: Operation) {
        self.shared.end(op);
    }

    fn broadcast(&self, status: UpdateStatus, independent: bool) {
        self.shared.broadcast(status, independent);
    }

    /// Broadcasts a status that belongs to the active updater operation: it
    /// carries the operation's request id and, for automatic checks, never
    /// advances the independent baseline the suppression logic restores.
    fn broadcast_owned(&self, status: UpdateStatus) {
        self.shared.broadcast_owned(status)
    }

    fn staged_downloaded_status(staged: &StagedUpdate) -> UpdateStatus {
        UpdateStatus {
            state: UpdateState::Downloaded,
            version: Some(staged.version.clone()),
            staged_at: Some(staged.at_ms),
            escalated: Some(staged.escalated),
            request_id: staged.request_id.clone(),
            ..UpdateStatus::idle()
        }
    }

    fn record_error(&self, op: Operation, message: &str) {
        let (phase, trigger, pending_version) =
            self.with_state(|state| (state.phase, op.trigger(), state.pending_version.clone()));
        self.sink.emit_telemetry(&status::update_failure_outcome(
            Some(message),
            phase,
            trigger,
            pending_version,
        ));
        if op == Operation::AutomaticCheck {
            eprintln!("auto-update check failed: {message}");
            let restore = self.with_state(|state| {
                state
                    .automatic_snapshot
                    .take()
                    .filter(|(_, revision)| *revision == state.independent_revision)
                    .map(|(status, _)| status)
            });
            if let Some(status) = restore {
                self.broadcast(status, true);
            }
            return;
        }
        self.broadcast_error(op, message);
    }

    /// Promise-rejection path: broadcasts an error without telemetry, exactly
    /// like Electron's catch blocks around each serialized operation.
    fn broadcast_error(&self, op: Operation, message: &str) {
        if is_manifest_404(message) {
            if op == Operation::ManualDownload {
                self.broadcast(
                    UpdateStatus {
                        state: UpdateState::Error,
                        message: Some(MANIFEST_404_DOWNLOAD_MESSAGE.to_string()),
                        ..UpdateStatus::idle()
                    },
                    true,
                );
                return;
            }
            let staged_status =
                self.with_state(|state| state.staged.as_ref().map(Self::staged_downloaded_status));
            if let Some(staged_status) = staged_status {
                self.broadcast(staged_status, true);
            } else {
                self.broadcast(
                    UpdateStatus {
                        state: UpdateState::Error,
                        message: Some(MANIFEST_404_CHECK_MESSAGE.to_string()),
                        ..UpdateStatus::idle()
                    },
                    true,
                );
            }
            return;
        }
        self.broadcast(
            UpdateStatus {
                state: UpdateState::Error,
                message: Some(message.to_string()),
                ..UpdateStatus::idle()
            },
            true,
        );
    }

    fn unsupported_flow(&self, request_id: Option<String>) {
        let phase = self.with_state(|state| state.phase);
        self.sink
            .emit_telemetry(&status::update_unsupported_outcome(
                phase,
                UpdateTrigger::Manual,
            ));
        self.broadcast(
            UpdateStatus {
                state: UpdateState::Unsupported,
                message: Some(UNSUPPORTED_MESSAGE.to_string()),
                request_id,
                ..UpdateStatus::idle()
            },
            true,
        );
    }

    async fn reconcile_pin(&self, settings: UpdateSettings) -> UpdateSettings {
        channel::reconcile_feature_pin(self.releases.as_ref(), settings, self.now_ms())
            .await
            .settings
    }

    async fn run_check_for_settings(
        &self,
        settings: &UpdateSettings,
        auto_download: bool,
        op: Operation,
    ) {
        let feed_url = match self.resolve_feed_url(settings.active_channel()) {
            Ok(url) => url,
            Err(error) => {
                self.record_error(op, &error);
                return;
            }
        };
        self.with_state(|state| {
            if state.active_op == Some(Operation::AutomaticCheck)
                && state.automatic_snapshot.is_none()
            {
                state.automatic_snapshot =
                    Some((state.last_status.clone(), state.independent_revision));
            }
        });
        self.broadcast_owned(UpdateStatus {
            state: UpdateState::Checking,
            ..UpdateStatus::idle()
        });
        self.release_slot
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .take();
        match self.client.check(feed_url.clone()).await {
            Err(message) => self.record_error(op, &message),
            Ok(None) => {
                self.broadcast_owned(UpdateStatus {
                    state: UpdateState::NotAvailable,
                    ..UpdateStatus::idle()
                });
                let staged_status = self
                    .with_state(|state| state.staged.as_ref().map(Self::staged_downloaded_status));
                if let Some(staged_status) = staged_status {
                    self.broadcast_owned(staged_status);
                }
            }
            Ok(Some(release)) => {
                let version = release.version();
                let already_staged = self.with_state(|state| {
                    state
                        .staged
                        .as_ref()
                        .is_some_and(|staged| staged.version == version)
                });
                if already_staged {
                    let staged_status = self.with_state(|state| {
                        state.staged.as_ref().map(Self::staged_downloaded_status)
                    });
                    if let Some(staged_status) = staged_status {
                        self.broadcast_owned(staged_status);
                    }
                    return;
                }
                self.with_state(|state| state.pending_version = Some(version.clone()));
                self.broadcast_owned(UpdateStatus {
                    state: UpdateState::Available,
                    version: Some(version),
                    ..UpdateStatus::idle()
                });
                if auto_download {
                    self.perform_download(release, feed_url, op).await;
                } else {
                    *self
                        .release_slot
                        .lock()
                        .unwrap_or_else(|poisoned| poisoned.into_inner()) =
                        Some((release, feed_url));
                }
            }
        }
    }

    async fn perform_download(&self, release: C::Release, feed_url: String, op: Operation) {
        self.with_state(|state| state.phase = UpdatePhase::Download);
        let version = release.version();
        if let Err(error) = self
            .storage
            .begin_download(&version, &feed_url, self.now_ms())
        {
            self.record_error(op, &error.to_string());
            return;
        }
        let broadcaster = self.shared.clone();
        let progress: ProgressCallback = Box::new(move |percent: u32| {
            broadcaster.broadcast_owned(UpdateStatus {
                state: UpdateState::Downloading,
                percent: Some(percent.clamp(0, 100)),
                ..UpdateStatus::idle()
            });
        });
        match self.client.download(release, progress).await {
            Err(message) => self.record_error(op, &message),
            Ok(bytes) => {
                let staged_at = self.now_ms();
                let staged = match self
                    .storage
                    .complete_download(&version, &feed_url, &bytes, staged_at)
                {
                    Ok(staged) => staged,
                    Err(error) => {
                        self.record_error(op, &error.to_string());
                        return;
                    }
                };
                let trigger = self.with_state(|state| state.active_op.unwrap_or(op).trigger());
                self.sink
                    .emit_telemetry(&status::update_downloaded_outcome(trigger, Some(version)));
                let owned = self.with_state(|state| {
                    state.staged = Some(StagedUpdate {
                        version: staged.meta.version.clone(),
                        at_ms: staged_at,
                        escalated: false,
                        request_id: state.active_request_id.clone(),
                    });
                    state.automatic_snapshot = None;
                    state.pending_version = None;
                    Self::staged_downloaded_status(state.staged.as_ref().unwrap())
                });
                self.broadcast(owned, true);
                self.run_escalation_tick().await;
            }
        }
    }

    pub async fn start(&self) -> bool {
        let _guard = self.op_lock.lock().await;
        self.begin(Operation::AutomaticCheck, None);
        let mut should_schedule = true;
        match self.settings.read().await {
            Err(error) => {
                eprintln!("auto-update check failed: {error}");
            }
            Ok(current) => {
                let settings = self.reconcile_pin(current).await;
                if !settings.enabled {
                    self.with_state(|state| state.automatic_scheduled = false);
                    should_schedule = false;
                } else {
                    self.run_check_for_settings(&settings, true, Operation::AutomaticCheck)
                        .await;
                }
            }
        }
        self.end(Operation::AutomaticCheck);
        should_schedule
    }

    pub async fn manual_check(&self, options: CheckOptions) {
        if !self.config.packaged {
            self.unsupported_flow(options.request_id);
            return;
        }
        let _guard = self.op_lock.lock().await;
        self.begin(Operation::ManualCheck, options.request_id);
        if let Some(next) = options.settings {
            if let Err(error) = self.settings.write(next).await {
                self.broadcast_error(Operation::ManualCheck, &error);
                self.end(Operation::ManualCheck);
                return;
            }
        }
        match self.settings.read().await {
            Err(error) => self.broadcast_error(Operation::ManualCheck, &error),
            Ok(current) => {
                let settings = self.reconcile_pin(current).await;
                self.with_state(|state| state.automatic_scheduled = settings.enabled);
                self.run_check_for_settings(&settings, false, Operation::ManualCheck)
                    .await;
            }
        }
        self.end(Operation::ManualCheck);
    }

    pub async fn return_home(&self, request_id: Option<String>) {
        if !self.config.packaged {
            self.unsupported_flow(request_id);
            return;
        }
        let _guard = self.op_lock.lock().await;
        self.begin(Operation::ReturnHome, request_id);
        match self.settings.read().await {
            Err(error) => self.broadcast_error(Operation::ReturnHome, &error),
            Ok(current) => {
                let mut cleared = current.clone();
                if current.feature.is_some() {
                    cleared.feature = None;
                    if let Err(error) = self.settings.write(cleared.clone()).await {
                        self.broadcast_error(Operation::ReturnHome, &error);
                        self.end(Operation::ReturnHome);
                        return;
                    }
                }
                let settings = self.reconcile_pin(cleared).await;
                self.with_state(|state| state.automatic_scheduled = settings.enabled);
                self.run_check_for_settings(&settings, false, Operation::ReturnHome)
                    .await;
            }
        }
        self.end(Operation::ReturnHome);
    }

    pub async fn download_now(&self, request_id: Option<String>) {
        if !self.config.packaged {
            self.unsupported_flow(request_id);
            return;
        }
        let _guard = self.op_lock.lock().await;
        self.begin(Operation::ManualDownload, request_id);
        let pending = self
            .release_slot
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .take();
        match pending {
            Some((release, feed_url)) => {
                self.perform_download(release, feed_url, Operation::ManualDownload)
                    .await;
            }
            None => {
                self.broadcast_error(
                    Operation::ManualDownload,
                    "no update is ready to download; check for updates first",
                );
            }
        }
        self.end(Operation::ManualDownload);
    }

    pub fn install_update(&self) -> Result<(), String> {
        Err(APPLY_DEFERRED_MESSAGE.to_string())
    }

    pub async fn apply_settings(&self, settings: UpdateSettings) {
        self.with_state(|state| state.automatic_scheduled = settings.enabled);
    }

    pub async fn run_hourly_tick(&self) {
        let busy = self.with_state(|state| state.active_op == Some(Operation::AutomaticCheck));
        if busy {
            return;
        }
        self.start().await;
    }

    pub async fn run_retirement_tick(&self) {
        let acquired = self.with_state(|state| {
            if state.retirement_busy {
                false
            } else {
                state.retirement_busy = true;
                true
            }
        });
        if !acquired {
            return;
        }
        let result: Result<(), String> = async {
            let _guard = self.op_lock.lock().await;
            self.begin(Operation::SettingsWrite, None);
            let outcome: Result<(), String> = async {
                let current = self.settings.read().await?;
                if let Some(pin) = current.feature {
                    let reconciled = channel::reconcile_feature_pin(
                        self.releases.as_ref(),
                        current.clone(),
                        self.now_ms(),
                    )
                    .await;
                    if reconciled.cleared {
                        let fresh = self.settings.read().await?;
                        if fresh.feature == Some(pin) {
                            let mut next = fresh;
                            next.feature = None;
                            self.settings.write(next).await?;
                        }
                    }
                }
                Ok(())
            }
            .await;
            self.end(Operation::SettingsWrite);
            outcome
        }
        .await;
        self.with_state(|state| state.retirement_busy = false);
        if let Err(error) = result {
            eprintln!("retirement poll skipped: {error}");
        }
    }

    pub async fn run_escalation_tick(&self) {
        let Some(staged) = self.with_state(|state| state.staged.clone()) else {
            return;
        };
        if self.with_state(|state| state.last_status.state) == UpdateState::Downloading {
            return;
        }
        let Ok(settings) = self.settings.read().await else {
            return;
        };
        let (important, latest_stable) = if settings.channel == Channel::Nightly {
            let important = self.feeds.nightly_important(&staged.version).await;
            let latest_stable = self.feeds.latest_stable_version().await;
            (important, latest_stable)
        } else {
            (false, None)
        };
        let escalated = escalation::evaluate_escalation(escalation::EscalationInput {
            channel: settings.channel,
            staged_at_ms: staged.at_ms,
            now_ms: self.now_ms(),
            important,
            running_version: &self.config.app_version,
            latest_stable_version: latest_stable.as_deref(),
        });
        let status = self.with_state(|state| {
            if let Some(staged) = state.staged.as_mut() {
                staged.escalated = escalated;
                Self::staged_downloaded_status(staged)
            } else {
                Self::staged_downloaded_status(&staged)
            }
        });
        self.broadcast(status, true);
    }

    #[cfg(test)]
    pub fn automatic_scheduled_snapshot(&self) -> bool {
        self.with_state(|state| state.automatic_scheduled)
    }

    #[cfg(test)]
    pub fn automatic_active_snapshot(&self) -> bool {
        self.with_state(|state| state.active_op == Some(Operation::AutomaticCheck))
    }

    #[cfg(test)]
    fn home_feed_url_for_test(&self) -> String {
        self.resolve_feed_url(ActiveChannel::Latest)
            .unwrap_or_default()
    }

    #[cfg(test)]
    pub fn begin_bytes_for_test(
        &self,
        version: &str,
        started_at_ms: i64,
    ) -> Result<(), storage::StorageError> {
        self.storage
            .begin_download(version, &self.home_feed_url_for_test(), started_at_ms)
    }

    #[cfg(test)]
    pub fn stage_bytes_for_test(
        &self,
        version: &str,
        bytes: &[u8],
    ) -> Result<storage::StagedArtifact, storage::StorageError> {
        let staged_at = (self.clock)();
        self.storage
            .complete_download(version, &self.home_feed_url_for_test(), bytes, staged_at)
    }

    fn resolve_feed_url(&self, channel: ActiveChannel) -> Result<String, String> {
        let base = self
            .config
            .feed_base_url
            .as_deref()
            .ok_or_else(|| "no update feed is configured for this build".to_string())?;
        channel::select_feed_url(base, channel, self.config.packaged)
            .map_err(|error| error.to_string())
    }
}

/// The first-run opt-in policy: a decline persists disabled defaults, an
/// enable picks stable unless the nightly instability disclaimer was
/// acknowledged, and dismissing nightly falls back to stable.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FirstRunAnswer {
    Decline,
    EnableLatest,
    EnableNightlyAcked,
    EnableNightlyDeclined,
}

pub fn first_run_settings(answer: FirstRunAnswer) -> UpdateSettings {
    match answer {
        FirstRunAnswer::Decline => UpdateSettings::default(),
        FirstRunAnswer::EnableLatest | FirstRunAnswer::EnableNightlyDeclined => UpdateSettings {
            enabled: true,
            channel: Channel::Latest,
            nightly_ack: false,
            feature: None,
        },
        FirstRunAnswer::EnableNightlyAcked => UpdateSettings {
            enabled: true,
            channel: Channel::Nightly,
            nightly_ack: true,
            feature: None,
        },
    }
}

/// A 404 on a release-manifest YAML is routine (missing channel file), not an
/// actionable error; anything else passes through verbatim.
fn is_manifest_404(message: &str) -> bool {
    let lowered = message.to_lowercase();
    if !lowered.contains("404") {
        return false;
    }
    match lowered.find(".yml") {
        Some(index) => lowered[index + 4..]
            .chars()
            .next()
            .is_none_or(|next| !next.is_ascii_alphanumeric()),
        None => false,
    }
}

pub const UPDATER_STATE_DIR_NAME: &str = "updater";

/// The minisign verification key, compiled in at build time. A build without
/// the key fails closed: no feed is checked and no artifact is downloaded.
pub const COMPILED_UPDATER_PUBLIC_KEY: &str = match core::option_env!("OPERATOR_UPDATER_PUBLIC_KEY")
{
    Some(key) => key,
    None => "",
};

pub const FEED_BASE_ENV: &str = "OPERATOR_UPDATER_FEED_URL";

/// The `plugins` key under which tauri.release.conf.json bakes the production
/// updater surface into packaged shells.
pub const RELEASE_PLUGIN_CONFIG_KEY: &str = "operator-updates";

/// Feed base resolution order: the runtime environment wins (dev, tests, and
/// the update-E2E harness), then the release config baked at build time, then
/// nothing — an unconfigured build fails closed at check time.
pub fn resolve_feed_base_url(
    env_override: Option<String>,
    plugins: Option<&serde_json::Value>,
) -> Option<String> {
    if let Some(value) = env_override {
        if !value.is_empty() {
            return Some(value);
        }
    }
    let baked = plugins?
        .get(RELEASE_PLUGIN_CONFIG_KEY)?
        .get("feedBaseUrl")?
        .as_str()?;
    if baked.is_empty() {
        return None;
    }
    Some(baked.to_string())
}

/// Forwards updater events to the main renderer window. Rust-side emission is
/// always scoped to that window.
pub struct WindowStatusSink {
    app: tauri::AppHandle,
}

impl WindowStatusSink {
    pub fn new(app: tauri::AppHandle) -> Self {
        Self { app }
    }
}

impl StatusSink for WindowStatusSink {
    fn emit_status(&self, status: &UpdateStatus) {
        use tauri::Emitter;
        let _ = self.app.emit_to(
            crate::shortcuts::MAIN_WINDOW_LABEL,
            "updates:status",
            status,
        );
    }

    fn emit_telemetry(&self, outcome: &UpdateOutcome) {
        use tauri::Emitter;
        let _ = self.app.emit_to(
            crate::shortcuts::MAIN_WINDOW_LABEL,
            "updates:telemetry",
            outcome,
        );
    }
}

/// Feed transport through the pinned tauri-plugin-updater client: manifest
/// checks and signature-verified downloads happen in memory only; nothing in
/// this client writes to disk before the engine stages verified bytes.
pub struct PluginFeedClient {
    app: tauri::AppHandle,
    public_key: String,
}

impl PluginFeedClient {
    pub fn new(app: tauri::AppHandle, public_key: String) -> Self {
        Self { app, public_key }
    }

    fn validated_key(&self) -> Result<String, String> {
        if self.public_key.is_empty() {
            return Err("this build has no compiled-in update verification key".to_string());
        }
        channel::validate_public_key(&self.public_key).map_err(|error| error.to_string())?;
        Ok(self.public_key.clone())
    }
}

impl FeedClient for PluginFeedClient {
    type Release = tauri_plugin_updater::Update;

    fn check<'a>(&'a self, url: String) -> BoxFuture<'a, Result<Option<Self::Release>, String>> {
        Box::pin(async move {
            let key = self.validated_key()?;
            let endpoint: tauri::Url = url
                .parse()
                .map_err(|error| format!("invalid feed URL: {error}"))?;
            let updater = self
                .app
                .updater_builder()
                .endpoints(vec![endpoint])
                .map_err(|error| error.to_string())?
                .pubkey(key)
                .version_comparator(|current, candidate| {
                    channel::feed_offers_candidate(
                        &current.to_string(),
                        &candidate.version.to_string(),
                    )
                })
                .build()
                .map_err(|error| error.to_string())?;
            updater.check().await.map_err(|error| error.to_string())
        })
    }

    fn download<'a>(
        &'a self,
        release: Self::Release,
        mut progress: ProgressCallback,
    ) -> BoxFuture<'a, Result<Vec<u8>, String>> {
        Box::pin(async move {
            let mut received: u64 = 0;
            release
                .download(
                    |chunk, total| {
                        received += chunk as u64;
                        let percent = total
                            .map(|total| ((received * 100) / total.max(1)).min(100))
                            .unwrap_or(0);
                        progress(percent.min(u32::MAX as u64) as u32);
                    },
                    || {},
                )
                .await
                .map_err(|error| error.to_string())
        })
    }
}

impl ReleaseHandle for tauri_plugin_updater::Update {
    fn version(&self) -> String {
        self.version.clone()
    }
}

fn loopback_http(
    port: u16,
    method: &'static str,
    path: &'static str,
    body: Option<serde_json::Value>,
) -> BoxFuture<'static, Result<serde_json::Value, String>> {
    Box::pin(async move {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let stream = tokio::time::timeout(
            std::time::Duration::from_secs(5),
            tokio::net::TcpStream::connect(("127.0.0.1", port)),
        )
        .await
        .map_err(|_| "timed out reaching the Operator daemon settings API".to_string())?
        .map_err(|error| format!("could not reach the Operator daemon settings API: {error}"))?;
        let (mut reader, mut writer) = stream.into_split();
        let payload = body.map(|value| value.to_string()).unwrap_or_default();
        let request = format!(
            "{method} {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{payload}",
            payload.len(),
        );
        writer
            .write_all(request.as_bytes())
            .await
            .map_err(|error| format!("settings request failed: {error}"))?;
        let mut raw = Vec::new();
        reader
            .read_to_end(&mut raw)
            .await
            .map_err(|error| format!("settings response failed: {error}"))?;
        drop(writer);
        let text = String::from_utf8_lossy(&raw);
        let header_end = text
            .find("\r\n\r\n")
            .ok_or_else(|| "malformed settings response".to_string())?;
        let status_ok = text.starts_with("HTTP/1.1 2") || text.starts_with("HTTP/1.0 2");
        let parsed: serde_json::Value = serde_json::from_str(text[header_end + 4..].trim())
            .map_err(|error| format!("unreadable settings response: {error}"))?;
        if !status_ok {
            let message = parsed["message"]
                .as_str()
                .or(parsed["error"]["message"].as_str())
                .unwrap_or("settings request rejected");
            return Err(message.to_string());
        }
        Ok(parsed)
    })
}

async fn daemon_port(manager: &crate::daemon::supervisor::DaemonManager) -> Option<u16> {
    manager.status().await.port
}

/// Settings access against the daemon's `/api/v1/settings`, which is the store
/// of record for update opt-in, channel, nightly acknowledgement, and pins.
pub struct DaemonSettingsSource {
    pub manager: crate::daemon::supervisor::DaemonManager,
}

impl DaemonSettingsSource {
    fn updates_payload(settings: &UpdateSettings) -> serde_json::Value {
        let feature = settings
            .feature
            .map(|pin| serde_json::json!({ "pr": pin.pr }));
        serde_json::json!({
            "enabled": settings.enabled,
            "channel": match settings.channel {
                Channel::Latest => "latest",
                Channel::Nightly => "nightly",
            },
            "nightlyAck": settings.nightly_ack,
            "feature": feature,
        })
    }
}

impl SettingsSource for DaemonSettingsSource {
    fn read<'a>(&'a self) -> BoxFuture<'a, Result<UpdateSettings, String>> {
        Box::pin(async move {
            let port = daemon_port(&self.manager)
                .await
                .ok_or_else(|| "the Operator daemon is not ready".to_string())?;
            let snapshot = loopback_http(port, "GET", "/api/v1/settings", None).await?;
            Ok(channel::coerce_settings(
                snapshot.get("updates").unwrap_or(&serde_json::Value::Null),
            ))
        })
    }

    fn write<'a>(&'a self, settings: UpdateSettings) -> BoxFuture<'a, Result<(), String>> {
        Box::pin(async move {
            let port = daemon_port(&self.manager)
                .await
                .ok_or_else(|| "the Operator daemon is not ready".to_string())?;
            loopback_http(
                port,
                "PATCH",
                "/api/v1/settings/updates",
                Some(Self::updates_payload(&settings)),
            )
            .await
            .map(|_| ())
        })
    }
}

/// Recorded stop: no shell-side HTTPS transport exists for the GitHub releases
/// API in this task. Listing degrades to an empty picker and reconciliation
/// keeps any pin (a fetch failure never strands a user off a pinned build).
pub struct StoppedReleasesSource;

const RELEASES_TRANSPORT_STOPPED: &str =
    "feature-build listing is unavailable in this shell: no GitHub releases transport is wired in yet";

impl ReleasesSource for StoppedReleasesSource {
    fn list_releases<'a>(&'a self) -> BoxFuture<'a, Result<Vec<channel::GitHubRelease>, String>> {
        Box::pin(async move { Err(RELEASES_TRANSPORT_STOPPED.to_string()) })
    }

    fn is_pr_open<'a>(&'a self, _pr: i64) -> BoxFuture<'a, bool> {
        Box::pin(async move { true })
    }
}

/// Recorded stop with graceful degradation: escalation feed probes behave
/// exactly like an unreachable GitHub in Electron — no important flag, no
/// stable-version comparison — so latest still escalates on its 48-hour rule.
pub struct StoppedEscalationFeeds;

impl EscalationFeeds for StoppedEscalationFeeds {
    fn latest_stable_version<'a>(&'a self) -> BoxFuture<'a, Option<String>> {
        Box::pin(async move { None })
    }

    fn nightly_important<'a>(&'a self, _version: &str) -> BoxFuture<'a, bool> {
        Box::pin(async move { false })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RecoverySummary {
    pub pruned: usize,
    pub pending: usize,
}

/// Startup sweep over the updater state directory: stale interrupted-download
/// intents are pruned, live ones are reported so the next launch knows a
/// download died mid-stream.
pub fn recover_interrupted(
    storage: &UpdaterStorage,
    now_ms: i64,
    max_age_ms: i64,
) -> RecoverySummary {
    let pruned = storage.prune_partials(now_ms, max_age_ms);
    let pending = storage.pending_downloads().len();
    RecoverySummary { pruned, pending }
}

pub type ShellEngine = UpdaterEngine<PluginFeedClient>;

/// Managed handle for the shell's updater engine.
pub struct UpdaterShell(pub Arc<ShellEngine>);

#[tauri::command]
pub async fn updates_status(shell: tauri::State<'_, UpdaterShell>) -> Result<UpdateStatus, String> {
    Ok(shell.0.status())
}

#[tauri::command]
pub async fn updates_check(
    shell: tauri::State<'_, UpdaterShell>,
    settings: Option<UpdateSettings>,
    request_id: Option<String>,
) -> Result<(), String> {
    shell
        .0
        .manual_check(CheckOptions {
            settings,
            request_id,
        })
        .await;
    Ok(())
}

#[tauri::command]
pub async fn updates_return_home(
    shell: tauri::State<'_, UpdaterShell>,
    request_id: Option<String>,
) -> Result<(), String> {
    shell.0.return_home(request_id).await;
    Ok(())
}

#[tauri::command]
pub async fn updates_download(
    shell: tauri::State<'_, UpdaterShell>,
    request_id: Option<String>,
) -> Result<(), String> {
    shell.0.download_now(request_id).await;
    Ok(())
}

#[tauri::command]
pub fn updates_install(shell: tauri::State<'_, UpdaterShell>) -> Result<(), String> {
    shell.0.install_update()
}

#[tauri::command]
pub async fn feature_builds_list(
    shell: tauri::State<'_, UpdaterShell>,
) -> Result<Vec<channel::FeatureBuild>, String> {
    let now_ms = shell.0.clock_snapshot();
    Ok(channel::list_feature_builds(shell.0.releases_source().as_ref(), now_ms).await)
}

#[tauri::command]
pub fn feature_builds_active(shell: tauri::State<'_, UpdaterShell>) -> Option<channel::FeaturePin> {
    shell
        .0
        .active_feature()
        .map(|pr| channel::FeaturePin { pr })
}

#[tauri::command]
pub async fn updates_apply_settings(
    shell: tauri::State<'_, UpdaterShell>,
    settings: UpdateSettings,
) -> Result<(), String> {
    shell.0.apply_settings(settings).await;
    Ok(())
}

/// Arms the three periodic loops: hourly automatic checks, 30-minute staged-
/// update escalation re-evaluations, and 30-minute feature-pin retirement
/// polls. The shell also checks ONCE at launch — Electron's initAutoUpdates
/// checked at startup, and both the update E2E harness and packaged users
/// depend on availability surfacing without waiting out the first hour.
pub fn spawn_updater_timers(engine: Arc<ShellEngine>) {
    let launch_check = engine.clone();
    tauri::async_runtime::spawn(async move { launch_check.run_hourly_tick().await });
    let hourly = engine.clone();
    tauri::async_runtime::spawn(async move {
        let mut timer = tokio::time::interval(std::time::Duration::from_millis(
            AUTOMATIC_CHECK_INTERVAL_MS,
        ));
        timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        timer.tick().await;
        loop {
            timer.tick().await;
            hourly.run_hourly_tick().await;
        }
    });
    let escalations = engine.clone();
    tauri::async_runtime::spawn(async move {
        let mut timer =
            tokio::time::interval(std::time::Duration::from_millis(ESCALATION_INTERVAL_MS));
        timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            timer.tick().await;
            escalations.run_escalation_tick().await;
        }
    });
    let retirement = engine.clone();
    tauri::async_runtime::spawn(async move {
        let mut timer = tokio::time::interval(std::time::Duration::from_millis(
            RETIREMENT_POLL_INTERVAL_MS,
        ));
        timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            timer.tick().await;
            retirement.run_retirement_tick().await;
        }
    });
}

/// Builds the production updater engine beneath `<state-root>/updater`.
pub fn open_shell_engine(
    app: &tauri::AppHandle,
    state_root: &std::path::Path,
    packaged: bool,
    app_version: &str,
    manager: crate::daemon::supervisor::DaemonManager,
) -> Result<Arc<ShellEngine>, Box<dyn std::error::Error>> {
    let storage = UpdaterStorage::open(state_root)?;
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as i64)
        .unwrap_or_default();
    let summary = recover_interrupted(&storage, now_ms, storage::PARTIAL_MAX_AGE_MS);
    if summary.pruned > 0 {
        eprintln!(
            "pruned {} stale interrupted update download(s)",
            summary.pruned
        );
    }
    if summary.pending > 0 {
        eprintln!(
            "{} interrupted update download(s) will restart from the feed",
            summary.pending
        );
    }
    let client = PluginFeedClient::new(app.clone(), COMPILED_UPDATER_PUBLIC_KEY.to_string());
    let config = EngineConfig {
        packaged,
        app_version: app_version.to_string(),
        feed_base_url: resolve_feed_base_url(
            std::env::var(FEED_BASE_ENV).ok(),
            app.config().plugins.0.get(RELEASE_PLUGIN_CONFIG_KEY),
        ),
        public_key: COMPILED_UPDATER_PUBLIC_KEY.to_string(),
    };
    let sink = Arc::new(WindowStatusSink::new(app.clone()));
    let clock: ClockFn = Arc::new(|| {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|elapsed| elapsed.as_millis() as i64)
            .unwrap_or_default()
    });
    let client = Arc::new(client);
    Ok(Arc::new(UpdaterEngine::new(
        client,
        Arc::new(DaemonSettingsSource { manager }),
        Arc::new(StoppedEscalationFeeds),
        Arc::new(StoppedReleasesSource),
        storage,
        sink,
        clock,
        config,
    )))
}
