use crate::daemon::discovery::{
    bundled_daemon_binary_name, keep_daemon_alive, parse_daemon_listen_port, parse_daemon_probe,
    parse_run_file, resolve_acp_runtime_dir, resolve_agent_browser_binary_path,
    resolve_daemon_launch, resolve_data_dir, resolve_run_file_path, should_link_on_attach,
    supervisor_addr, with_fallback_path, DaemonProbe, ListenPortScanner,
};
use crate::daemon::{DaemonLaunchSpec, DaemonStatus};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpStream, UnixStream};
use tokio::process::{Child, Command};
use tokio::sync::Mutex;

const PORT_DISCOVERY_TIMEOUT: Duration = Duration::from_millis(30000);
const RUN_FILE_POLL_INTERVAL: Duration = Duration::from_millis(300);
const RUN_FILE_FRESHNESS_SKEW: Duration = Duration::from_millis(2000);
const DAEMON_PROBE_TIMEOUT: Duration = Duration::from_millis(2000);
const DAEMON_RESTART_STOP_TIMEOUT: Duration = Duration::from_millis(5000);
const MAX_DAEMON_OUTPUT_CHARS: usize = 12000;

#[derive(Debug)]
pub struct SupervisorLink {
    disposed: Arc<AtomicBool>,
    connected: Arc<AtomicBool>,
    handle: Option<tokio::task::JoinHandle<()>>,
}

impl SupervisorLink {
    pub fn new(addr: PathBuf) -> Self {
        let disposed = Arc::new(AtomicBool::new(false));
        let connected = Arc::new(AtomicBool::new(false));
        let disposed_clone = disposed.clone();
        let connected_clone = connected.clone();
        let handle = tokio::spawn(async move {
            supervisor_loop_unix(addr, connected_clone, disposed_clone).await;
        });
        Self {
            disposed,
            connected,
            handle: Some(handle),
        }
    }
    #[cfg(windows)]
    pub fn new_windows(addr: String) -> Self {
        let disposed = Arc::new(AtomicBool::new(false));
        let connected = Arc::new(AtomicBool::new(false));
        let disposed_clone = disposed.clone();
        let connected_clone = connected.clone();
        let handle = tokio::spawn(async move {
            supervisor_loop_windows(addr, connected_clone, disposed_clone).await;
        });
        Self {
            disposed,
            connected,
            handle: Some(handle),
        }
    }
    pub fn connected(&self) -> bool {
        self.connected.load(Ordering::SeqCst)
    }
    pub fn dispose(mut self) {
        self.disposed.store(true, Ordering::SeqCst);
        self.connected.store(false, Ordering::SeqCst);
        if let Some(h) = self.handle.take() {
            h.abort();
        }
    }
    pub fn dispose_ref(&self) {
        self.disposed.store(true, Ordering::SeqCst);
        self.connected.store(false, Ordering::SeqCst);
    }
}

impl Drop for SupervisorLink {
    fn drop(&mut self) {
        self.disposed.store(true, Ordering::SeqCst);
        self.connected.store(false, Ordering::SeqCst);
        if let Some(h) = self.handle.take() {
            h.abort();
        }
    }
}

#[cfg(not(windows))]
async fn supervisor_loop_unix(
    addr: PathBuf,
    connected: Arc<AtomicBool>,
    disposed: Arc<AtomicBool>,
) {
    let mut backoff = Duration::from_millis(200);
    loop {
        if disposed.load(Ordering::SeqCst) {
            break;
        }
        match UnixStream::connect(&addr).await {
            Ok(mut stream) => {
                connected.store(true, Ordering::SeqCst);
                backoff = Duration::from_millis(200);
                let mut buf = [0u8; 32];
                loop {
                    if disposed.load(Ordering::SeqCst) {
                        break;
                    }
                    match stream.read(&mut buf).await {
                        Ok(0) => break,
                        Ok(_) => continue,
                        Err(_) => break,
                    }
                }
                connected.store(false, Ordering::SeqCst);
            }
            Err(_) => {}
        }
        if disposed.load(Ordering::SeqCst) {
            break;
        }
        tokio::time::sleep(backoff).await;
        backoff = std::cmp::min(backoff * 2, Duration::from_millis(2000));
    }
}

#[cfg(windows)]
async fn supervisor_loop_windows(
    addr: String,
    connected: Arc<AtomicBool>,
    disposed: Arc<AtomicBool>,
) {
    use tokio::net::windows::named_pipe::ClientOptions;
    let mut backoff = Duration::from_millis(200);
    loop {
        if disposed.load(Ordering::SeqCst) {
            break;
        }
        match ClientOptions::new().open(&addr) {
            Ok(mut stream) => {
                connected.store(true, Ordering::SeqCst);
                backoff = Duration::from_millis(200);
                let mut buf = [0u8; 32];
                loop {
                    if disposed.load(Ordering::SeqCst) {
                        break;
                    }
                    match stream.read(&mut buf).await {
                        Ok(0) => break,
                        Ok(_) => continue,
                        Err(_) => break,
                    }
                }
                connected.store(false, Ordering::SeqCst);
            }
            Err(_) => {}
        }
        if disposed.load(Ordering::SeqCst) {
            break;
        }
        tokio::time::sleep(backoff).await;
        backoff = std::cmp::min(backoff * 2, Duration::from_millis(2000));
    }
}

#[derive(Debug)]
struct Inner {
    status: DaemonStatus,
    output: String,
    child: Option<Child>,
    supervisor: Option<SupervisorLink>,
    start_epoch: u64,
}

#[derive(Debug, Clone)]
pub struct DaemonConfig {
    pub run_file: PathBuf,
    pub data_dir: PathBuf,
    pub acp_runtime_dir: PathBuf,
    pub app_version: String,
    pub resources_dir: PathBuf,
    pub home_dir: PathBuf,
    pub is_packaged: bool,
    pub app_run_id: String,
    pub launch_spec: Option<DaemonLaunchSpec>,
}

impl DaemonConfig {
    pub fn from_env() -> Self {
        let env: HashMap<String, String> = std::env::vars().collect();
        let home = crate::daemon::home_dir();
        let is_packaged = crate::daemon::is_packaged();
        let resources = crate::daemon::resource_dir();
        let app_p = crate::daemon::app_path();
        let platform = if cfg!(windows) { "win32" } else { "darwin" };
        let launch_spec =
            resolve_daemon_launch(&env, is_packaged, &resources, &app_p, &home, platform);
        let run_file = resolve_run_file_path(&env, &home, is_packaged)
            .unwrap_or(home.join(".operator").join("running.json"));
        let data_dir = resolve_data_dir(&env, &home, is_packaged)
            .unwrap_or(home.join(".operator").join("data"));
        let acp_runtime_dir = resolve_acp_runtime_dir(&env, is_packaged, &resources, &app_p);
        let app_version = crate::daemon::app_version();
        let app_run_id = std::env::var("OPERATOR_APP_RUN_ID")
            .ok()
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| format!("apprun-{}", uuid::Uuid::new_v4().simple()));
        Self {
            run_file,
            data_dir,
            acp_runtime_dir,
            app_version,
            resources_dir: resources,
            home_dir: home,
            is_packaged,
            app_run_id,
            launch_spec,
        }
    }
}

pub struct DaemonManager {
    inner: Arc<Mutex<Inner>>,
    config: DaemonConfig,
    discovery_timeout: Duration,
}

impl DaemonManager {
    pub fn new() -> Self {
        Self::with_config(DaemonConfig::from_env())
    }
    pub fn with_config(config: DaemonConfig) -> Self {
        Self::with_timeout(config, PORT_DISCOVERY_TIMEOUT)
    }
    pub fn with_timeout(config: DaemonConfig, timeout: Duration) -> Self {
        let inner = Inner {
            status: DaemonStatus::default(),
            output: String::new(),
            child: None,
            supervisor: None,
            start_epoch: 0,
        };
        Self {
            inner: Arc::new(Mutex::new(inner)),
            config,
            discovery_timeout: timeout,
        }
    }
    pub fn with_config_and_timeout(config: DaemonConfig, timeout: Duration) -> Self {
        Self::with_timeout(config, timeout)
    }
    pub fn app_run_id(&self) -> String {
        self.config.app_run_id.clone()
    }
    pub fn run_file_path(&self) -> PathBuf {
        self.config.run_file.clone()
    }
    pub fn data_dir(&self) -> PathBuf {
        self.config.data_dir.clone()
    }
    pub async fn status(&self) -> DaemonStatus {
        let guard = self.inner.lock().await;
        if guard.child.is_some() {
            return guard.status.clone();
        }
        drop(guard);
        if let Some(attached) = self.try_attach().await {
            let mut g = self.inner.lock().await;
            g.status = attached.clone();
            return attached;
        }
        let g = self.inner.lock().await;
        if g.status.state == "ready" {
            let mut new_status = DaemonStatus::default();
            new_status.state = "stopped".to_string();
            new_status.message = Some("Operator daemon is no longer reachable.".to_string());
            new_status.code = Some("daemon_unreachable".to_string());
            return new_status;
        }
        g.status.clone()
    }
    pub async fn start(&self) -> DaemonStatus {
        {
            let g = self.inner.lock().await;
            if g.child.is_some() {
                return g.status.clone();
            }
            if g.status.state == "starting" {
                return g.status.clone();
            }
        }
        if let Some(attached) = self.try_attach().await {
            let mut g = self.inner.lock().await;
            if should_link_on_attach(attached_owner(&attached).as_deref()) {
                self.establish_supervisor_link(&mut g).await;
            }
            g.status = attached.clone();
            return attached;
        }
        {
            let mut g = self.inner.lock().await;
            g.status.state = "starting".to_string();
            g.status.message = None;
            g.status.code = None;
            g.start_epoch += 1;
        }
        let launch = self.config.launch_spec.clone().or_else(|| {
            let env: HashMap<String, String> = std::env::vars().collect();
            let platform = if cfg!(windows) { "win32" } else { "darwin" };
            resolve_daemon_launch(
                &env,
                self.config.is_packaged,
                &self.config.resources_dir,
                &crate::daemon::app_path(),
                &self.config.home_dir,
                platform,
            )
        });
        let launch = match launch {
            Some(l) => l,
            None => {
                let mut g = self.inner.lock().await;
                g.status = DaemonStatus {
                    state: "error".to_string(),
                    message: Some("OPERATOR_DAEMON_COMMAND is not configured".to_string()),
                    code: Some("not_configured".to_string()),
                    ..Default::default()
                };
                return g.status.clone();
            }
        };
        if launch.source == "bundled" {
            let cmd_path = PathBuf::from(&launch.command);
            if !cmd_path.exists() {
                let mut g = self.inner.lock().await;
                g.status = DaemonStatus {
                    state: "error".to_string(),
                    message: Some(format!("Bundled Operator daemon binary was not found at {}. Rebuild the desktop package.", launch.command)),
                    code: Some("binary_missing".to_string()),
                    executable_path: Some(launch.command.clone()),
                    working_directory: Some(launch.cwd.to_string_lossy().to_string()),
                    ..Default::default()
                };
                return g.status.clone();
            }
            if let Err(e) = tokio::fs::create_dir_all(&launch.cwd).await {
                let mut g = self.inner.lock().await;
                g.status = DaemonStatus {
                    state: "error".to_string(),
                    message: Some(format!(
                        "Could not create the Operator data directory at {}: {}",
                        launch.cwd.display(),
                        e
                    )),
                    code: Some("datadir_unwritable".to_string()),
                    ..Default::default()
                };
                return g.status.clone();
            }
        }
        let env_map = self.build_daemon_env(&launch).await;
        let keep = keep_daemon_alive(&env_map.clone().into_iter().collect());
        let mut cmd = if launch.shell {
            let mut c = Command::new("sh");
            c.arg("-c").arg(&launch.command);
            c
        } else {
            let mut c = Command::new(&launch.command);
            c.args(&launch.args);
            c
        };
        cmd.current_dir(&launch.cwd);
        cmd.env_clear();
        for (k, v) in env_map.iter() {
            cmd.env(k, v);
        }
        cmd.stdout(std::process::Stdio::piped());
        cmd.stderr(std::process::Stdio::piped());
        cmd.stdin(std::process::Stdio::null());
        let child = match cmd.spawn() {
            Ok(c) => c,
            Err(e) => {
                let mut g = self.inner.lock().await;
                g.status = DaemonStatus {
                    state: "error".to_string(),
                    message: Some(e.to_string()),
                    details: Some(g.output.clone()),
                    code: Some("spawn_failed".to_string()),
                    executable_path: Some(launch.command.clone()),
                    working_directory: Some(launch.cwd.to_string_lossy().to_string()),
                    ..Default::default()
                };
                return g.status.clone();
            }
        };
        let pid = child.id();
        {
            let mut g = self.inner.lock().await;
            g.child = Some(child);
            g.output.clear();
        }
        let spawned_at = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64;
        let (port, pid_result) = self.wait_for_ready(spawned_at).await;
        let mut g = self.inner.lock().await;
        if let Some(p) = port {
            g.status = DaemonStatus {
                state: "ready".to_string(),
                port: Some(p),
                pid: pid_result.or(pid),
                ..Default::default()
            };
            if !keep {
                self.establish_supervisor_link(&mut g).await;
            }
            return g.status.clone();
        }
        if let Some(mut child) = g.child.take() {
            let _ = child.kill().await;
        }
        let details = if g.output.trim().is_empty() {
            format!(
                "No startup output was captured.\nExecutable: {}\nWorking directory: {}\nExpected port confirmation from: {}",
                launch.command,
                launch.cwd.display(),
                self.config.run_file.display()
            )
        } else {
            g.output.trim().to_string()
        };
        g.status = DaemonStatus {
            state: "error".to_string(),
            message: Some("Operator daemon did not finish starting within 30 seconds.".to_string()),
            details: Some(details),
            code: Some("not_ready".to_string()),
            executable_path: Some(launch.command.clone()),
            working_directory: Some(launch.cwd.to_string_lossy().to_string()),
            ..Default::default()
        };
        g.status.clone()
    }
    pub async fn stop(&self) -> DaemonStatus {
        let mut g = self.inner.lock().await;
        g.start_epoch += 1;
        if let Some(mut child) = g.child.take() {
            if let Some(s) = g.supervisor.take() {
                s.dispose();
            }
            let _ = child.kill().await;
            let _ = tokio::time::timeout(Duration::from_millis(200), child.wait()).await;
        } else {
            if let Some(s) = g.supervisor.take() {
                s.dispose();
            }
        }
        g.status = DaemonStatus {
            state: "stopped".to_string(),
            ..Default::default()
        };
        g.output.clear();
        g.status.clone()
    }
    pub async fn restart(&self) -> DaemonStatus {
        let has_child = { self.inner.lock().await.child.is_some() };
        if !has_child {
            return self.start().await;
        }
        let child_pid = {
            let mut g = self.inner.lock().await;
            g.child.as_ref().and_then(|c| c.id())
        };
        self.stop().await;
        if let Some(pid) = child_pid {
            let deadline = tokio::time::Instant::now() + DAEMON_RESTART_STOP_TIMEOUT;
            loop {
                if tokio::time::Instant::now() >= deadline {
                    let mut g = self.inner.lock().await;
                    g.status = DaemonStatus {
                        state: "error".to_string(),
                        message: Some("Operator daemon is still stopping. It will restart automatically when shutdown completes.".to_string()),
                        details: Some(g.output.trim().to_string()),
                        code: Some("not_ready".to_string()),
                        ..Default::default()
                    };
                    return g.status.clone();
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
                if !is_pid_alive(pid) {
                    break;
                }
            }
        }
        self.start().await
    }
    async fn try_attach(&self) -> Option<DaemonStatus> {
        let run_file = self.config.run_file.clone();
        let contents = tokio::fs::read_to_string(&run_file).await.ok();
        let is_alive = |pid: u32| crate::daemon::discovery::process_alive(pid);
        if let Some(c) = contents {
            if let Some(info) = parse_run_file(&c) {
                if is_alive(info.pid) {
                    if let Some(health) = probe_daemon(info.port, "healthz").await {
                        if health.pid == info.pid {
                            let identity = |probe: &DaemonProbe| {
                                let env: HashMap<String, String> = std::env::vars().collect();
                                let platform = if cfg!(windows) { "win32" } else { "darwin" };
                                let launch = resolve_daemon_launch(
                                    &env,
                                    self.config.is_packaged,
                                    &self.config.resources_dir,
                                    &crate::daemon::app_path(),
                                    &self.config.home_dir,
                                    platform,
                                );
                                if let Some(l) = launch {
                                    daemon_identity_error(&l, probe)
                                } else {
                                    None
                                }
                            };
                            if let Some(status) =
                                readiness_status_direct(info.port, health.pid, health, identity)
                                    .await
                            {
                                return Some(status);
                            }
                        }
                    }
                }
            }
        }
        let env: HashMap<String, String> = std::env::vars().collect();
        let expected =
            crate::daemon::discovery::expected_daemon_port(&env, !self.config.is_packaged);
        if let Some(health) = probe_daemon(expected, "healthz").await {
            let pid = health.pid;
            let status = readiness_status_direct(expected, pid, health, |p| {
                let env2: HashMap<String, String> = std::env::vars().collect();
                let plat = if cfg!(windows) { "win32" } else { "darwin" };
                let l = resolve_daemon_launch(
                    &env2,
                    self.config.is_packaged,
                    &self.config.resources_dir,
                    &crate::daemon::app_path(),
                    &self.config.home_dir,
                    plat,
                );
                if let Some(launch) = l {
                    daemon_identity_error(&launch, p)
                } else {
                    None
                }
            })
            .await;
            if status.is_some() {
                return status;
            }
        }
        None
    }
    async fn wait_for_ready(&self, spawned_at_ms: i64) -> (Option<u16>, Option<u32>) {
        let run_file = self.config.run_file.clone();
        let deadline = tokio::time::Instant::now() + self.discovery_timeout;
        let mut interval = tokio::time::interval(RUN_FILE_POLL_INTERVAL);
        loop {
            if tokio::time::Instant::now() >= deadline {
                break;
            }
            {
                let mut g = self.inner.lock().await;
                if let Some(child) = g.child.as_mut() {
                    match child.try_wait() {
                        Ok(Some(status)) => {
                            let code = status.code();
                            append_output(&mut g.output, &format!("\nexit code {:?}", code));
                            g.status = DaemonStatus {
                                state: "error".to_string(),
                                message: Some(format!(
                                    "Daemon exited with code {:?}",
                                    code.unwrap_or(-1)
                                )),
                                details: Some(g.output.trim().to_string()),
                                code: Some("exited".to_string()),
                                exit_code: code,
                                signal: None,
                                ..Default::default()
                            };
                            return (None, None);
                        }
                        _ => {}
                    }
                }
            }
            if let Ok(contents) = tokio::fs::read_to_string(&run_file).await {
                if let Some(info) = parse_run_file(&contents) {
                    if info.started_at_ms >= spawned_at_ms - 2000 {
                        return (Some(info.port), Some(info.pid));
                    }
                }
            }
            interval.tick().await;
        }
        (None, None)
    }
    async fn build_daemon_env(&self, launch: &DaemonLaunchSpec) -> HashMap<String, String> {
        let mut env: HashMap<String, String> = std::env::vars().collect();
        let mut overrides: HashMap<String, String> = HashMap::new();
        let owner = if keep_daemon_alive(&env) {
            "persistent"
        } else {
            "app"
        };
        overrides.insert("OPERATOR_OWNER".to_string(), owner.to_string());
        overrides.insert(
            "OPERATOR_APP_RUN_ID".to_string(),
            self.config.app_run_id.clone(),
        );
        overrides.insert(
            "OPERATOR_RUN_FILE".to_string(),
            self.config.run_file.to_string_lossy().to_string(),
        );
        overrides.insert(
            "OPERATOR_DATA_DIR".to_string(),
            self.config.data_dir.to_string_lossy().to_string(),
        );
        overrides.insert(
            "OPERATOR_ACP_RUNTIME_DIR".to_string(),
            self.config.acp_runtime_dir.to_string_lossy().to_string(),
        );
        overrides.insert(
            "OPERATOR_TELEMETRY_APP_VERSION".to_string(),
            self.config.app_version.clone(),
        );
        if !self.config.is_packaged {
            if !env.contains_key("OPERATOR_PORT") {
                overrides.insert("OPERATOR_PORT".to_string(), "3002".to_string());
            }
            if !env.contains_key("OPERATOR_RUN_FILE") {
                overrides.insert(
                    "OPERATOR_RUN_FILE".to_string(),
                    self.config.run_file.to_string_lossy().to_string(),
                );
            }
            if !env.contains_key("OPERATOR_DATA_DIR") {
                overrides.insert(
                    "OPERATOR_DATA_DIR".to_string(),
                    self.config.data_dir.to_string_lossy().to_string(),
                );
            }
        }
        overrides.insert("OPERATOR_BROWSER_RUNTIME_TOKEN".to_string(), "".to_string());
        overrides.insert(
            "OPERATOR_BROWSER_RUNTIME_TOKEN_STDIN".to_string(),
            "1".to_string(),
        );
        let shell_env: Option<HashMap<String, String>> = None;
        crate::daemon::discovery::build_daemon_env(&env, shell_env.as_ref(), &overrides)
    }
    async fn establish_supervisor_link(&self, inner: &mut Inner) {
        #[cfg(not(windows))]
        {
            let addr = supervisor_addr(&self.config.run_file);
            if let Some(old) = inner.supervisor.take() {
                old.dispose();
            }
            inner.supervisor = Some(SupervisorLink::new(addr));
        }
        #[cfg(windows)]
        {
            let addr = supervisor_addr(&self.config.run_file);
            if let Some(old) = inner.supervisor.take() {
                old.dispose();
            }
            inner.supervisor = Some(SupervisorLink::new_windows(addr));
        }
    }
}

fn append_output(output: &mut String, text: &str) {
    output.push_str(text);
    if output.len() > MAX_DAEMON_OUTPUT_CHARS {
        let start = output.len() - MAX_DAEMON_OUTPUT_CHARS;
        *output = output[start..].to_string();
    }
}

fn attached_owner(status: &DaemonStatus) -> Option<String> {
    None
}

fn is_pid_alive(pid: u32) -> bool {
    crate::daemon::discovery::process_alive(pid)
}

fn daemon_identity_error(launch: &DaemonLaunchSpec, probe: &DaemonProbe) -> Option<String> {
    if launch.source == "dev" {
        let cwd_matches = probe
            .working_directory
            .as_ref()
            .map(|wd| same_path(wd, &launch.cwd.to_string_lossy().to_string()))
            .unwrap_or(false);
        let startup_matches = probe
            .startup_working_directory
            .as_ref()
            .map(|wd| same_path(wd, &launch.cwd.to_string_lossy().to_string()))
            .unwrap_or(false);
        let exec_matches = probe
            .executable_path
            .as_ref()
            .map(|ep| path_inside(ep, &launch.cwd.to_string_lossy().to_string()))
            .unwrap_or(false);
        if probe.working_directory.is_none()
            && probe.startup_working_directory.is_none()
            && probe.executable_path.is_none()
        {
            return Some("An older Operator daemon is already running, but it does not report its checkout identity. Stop it and restart this app.".to_string());
        }
        if !cwd_matches && !startup_matches && !exec_matches {
            let actual = probe
                .startup_working_directory
                .clone()
                .or(probe.working_directory.clone())
                .or(probe.executable_path.clone())
                .unwrap_or("an unknown location".to_string());
            return Some(format!(
                "Another Operator daemon is already running from {}; expected this checkout at {}. Stop the other daemon before using this checkout.",
                actual,
                launch.cwd.display()
            ));
        }
        return None;
    }
    if launch.source == "bundled" {
        if probe.executable_path.is_none() {
            return Some("An older Operator daemon is already running, but it does not report its binary path. Stop it and restart this app.".to_string());
        }
        if let Some(ep) = &probe.executable_path {
            if !same_path(ep, &launch.command) {
                return Some(format!(
                    "Another Operator daemon is already running from {}; expected {}. Stop the other daemon before using this app.",
                    ep, launch.command
                ));
            }
        }
    }
    None
}

fn same_path(a: &str, b: &str) -> bool {
    path_key(a) == path_key(b)
}

fn path_key(value: &str) -> String {
    let p = PathBuf::from(value);
    let s = p.to_string_lossy().to_string();
    if cfg!(windows) {
        s.to_lowercase()
    } else {
        s
    }
}

fn path_inside(child: &str, parent: &str) -> bool {
    let child_key = path_key(child);
    let parent_key = path_key(parent);
    if child_key == parent_key {
        return true;
    }
    child_key.starts_with(&format!("{}{}", parent_key, std::path::MAIN_SEPARATOR))
}

async fn probe_daemon(port: u16, endpoint: &str) -> Option<DaemonProbe> {
    let addr = format!("127.0.0.1:{}", port);
    let connect = tokio::time::timeout(DAEMON_PROBE_TIMEOUT, TcpStream::connect(&addr)).await;
    let mut stream = match connect {
        Ok(Ok(s)) => s,
        _ => return None,
    };
    let req = format!(
        "GET /{} HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nConnection: close\r\n\r\n",
        endpoint, port
    );
    if tokio::time::timeout(DAEMON_PROBE_TIMEOUT, stream.write_all(req.as_bytes()))
        .await
        .is_err()
    {
        return None;
    }
    let mut resp = Vec::new();
    let mut buf = [0u8; 4096];
    loop {
        match tokio::time::timeout(DAEMON_PROBE_TIMEOUT, stream.read(&mut buf)).await {
            Ok(Ok(0)) => break,
            Ok(Ok(n)) => resp.extend_from_slice(&buf[..n]),
            _ => return None,
        }
    }
    let resp_str = String::from_utf8_lossy(&resp);
    let header_end = resp_str.find("\r\n\r\n").map(|i| i + 4).unwrap_or(0);
    let body = &resp_str[header_end..];
    if !resp_str.starts_with("HTTP/1.1 200") && !resp_str.starts_with("HTTP/1.0 200") {
        return None;
    }
    let json: serde_json::Value = serde_json::from_str(body).ok()?;
    parse_daemon_probe(endpoint, &json)
}

async fn readiness_status_direct(
    port: u16,
    pid: u32,
    health: DaemonProbe,
    identity_error: impl Fn(&DaemonProbe) -> Option<String>,
) -> Option<DaemonStatus> {
    let ready = probe_daemon(port, "readyz").await;
    if ready.is_none() || ready.as_ref().map(|r| r.pid != pid).unwrap_or(true) {
        return Some(DaemonStatus {
            state: "error".to_string(),
            port: Some(port),
            pid: Some(pid),
            executable_path: health.executable_path.clone(),
            working_directory: health.working_directory.clone(),
            message: Some(
                "An Operator daemon is already running, but it is not ready yet.".to_string(),
            ),
            code: Some("not_ready".to_string()),
            ..Default::default()
        });
    }
    let ready_probe = ready.unwrap();
    if let Some(msg) = identity_error(&ready_probe) {
        return Some(DaemonStatus {
            state: "error".to_string(),
            port: Some(port),
            pid: Some(pid),
            executable_path: ready_probe.executable_path.clone(),
            working_directory: ready_probe.working_directory.clone(),
            message: Some(msg),
            code: Some("identity_mismatch".to_string()),
            ..Default::default()
        });
    }
    Some(DaemonStatus {
        state: "ready".to_string(),
        port: Some(port),
        pid: Some(pid),
        executable_path: ready_probe.executable_path.clone(),
        working_directory: ready_probe.working_directory.clone(),
        ..Default::default()
    })
}
