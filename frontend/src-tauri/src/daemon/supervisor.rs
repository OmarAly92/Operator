use crate::daemon::discovery::{
    keep_daemon_alive, parse_daemon_probe, parse_run_file, resolve_acp_runtime_dir,
    resolve_agent_browser_binary_path, resolve_daemon_launch, resolve_data_dir,
    resolve_run_file_path, should_link_on_attach, supervisor_addr, DaemonProbe, ListenPortScanner,
};
use crate::daemon::{DaemonLaunchSpec, DaemonStatus};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
#[cfg(not(windows))]
use tokio::net::UnixStream;
use tokio::process::{Child, Command};
use tokio::sync::{broadcast, Mutex, OnceCell};

const RUN_FILE_POLL_INTERVAL: Duration = Duration::from_millis(300);
const RUN_FILE_FRESHNESS_SKEW: Duration = Duration::from_millis(2000);
const DAEMON_PROBE_TIMEOUT: Duration = Duration::from_millis(2000);
const DAEMON_RESTART_STOP_TIMEOUT: Duration = Duration::from_millis(5000);
const MAX_DAEMON_OUTPUT_CHARS: usize = 12000;
const SHELL_ENV_TIMEOUT: Duration = Duration::from_millis(3000);

pub fn telemetry_renderer_env(process_env: &HashMap<String, String>, is_packaged: bool) -> String {
    match process_env.get("OPERATOR_TELEMETRY_RENDERER") {
        Some(v) if !v.trim().is_empty() => v.trim().to_string(),
        _ => {
            if is_packaged {
                "on".to_string()
            } else {
                "off".to_string()
            }
        }
    }
}

pub fn allowed_origins_override(
    process_env: &HashMap<String, String>,
    is_packaged: bool,
) -> Option<String> {
    if is_packaged {
        return None;
    }
    if let Some(v) = process_env.get("OPERATOR_ALLOWED_ORIGINS") {
        if !v.trim().is_empty() {
            return None;
        }
    }
    dev_renderer_origin()
}

fn dev_renderer_origin() -> Option<String> {
    let config: serde_json::Value =
        serde_json::from_str(include_str!("../../tauri.conf.json")).ok()?;
    let url = config.get("build")?.get("devUrl")?.as_str()?;
    origin_of(url)
}

fn origin_of(url: &str) -> Option<String> {
    let trimmed = url.trim().trim_end_matches('/');
    let (scheme, rest) = trimmed.split_once("://")?;
    if scheme != "http" && scheme != "https" {
        return None;
    }
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let authority = &rest[..end];
    if authority.is_empty() {
        return None;
    }
    Some(format!("{}://{}", scheme, authority))
}

#[derive(Debug)]
pub struct SupervisorLink {
    disposed: Arc<AtomicBool>,
    connected: Arc<AtomicBool>,
    handle: Option<tokio::task::JoinHandle<()>>,
}

impl SupervisorLink {
    #[cfg(not(windows))]
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
        if let Ok(mut stream) = UnixStream::connect(&addr).await {
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
    manual_stopped: bool,
    terminate_on_drop: bool,
    #[cfg(windows)]
    job: Option<WindowsJob>,
}

impl Drop for Inner {
    fn drop(&mut self) {
        if !self.terminate_on_drop || self.child.is_none() {
            return;
        }
        #[cfg(unix)]
        if let Some(pid) = self.child.as_ref().and_then(Child::id) {
            unsafe {
                libc::kill(-(pid as i32), libc::SIGTERM);
            }
        }
        #[cfg(windows)]
        if let Some(job) = self.job.take() {
            job.terminate();
        }
        if let Some(child) = self.child.as_mut() {
            let _ = child.start_kill();
        }
    }
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
    pub fn from_runtime(
        process_env: &HashMap<String, String>,
        home: PathBuf,
        resources: PathBuf,
        app_path: PathBuf,
        is_packaged: bool,
        app_version: String,
    ) -> Self {
        let platform = crate::daemon::runtime_platform();
        let launch_spec = resolve_daemon_launch(
            process_env,
            is_packaged,
            &resources,
            &app_path,
            &home,
            platform,
        );
        let run_file = resolve_run_file_path(process_env, &home, is_packaged)
            .unwrap_or(home.join(".operator").join("running.json"));
        let data_dir = resolve_data_dir(process_env, &home, is_packaged)
            .unwrap_or(home.join(".operator").join("data"));
        let acp_runtime_dir =
            resolve_acp_runtime_dir(process_env, is_packaged, &resources, &app_path);
        let app_run_id = process_env
            .get("OPERATOR_APP_RUN_ID")
            .cloned()
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

#[derive(Clone)]
pub struct DaemonManager {
    inner: Arc<Mutex<Inner>>,
    config: DaemonConfig,
    discovery_timeout: Duration,
    start_lock: Arc<Mutex<()>>,
    shell_env_cell: Arc<OnceCell<Option<HashMap<String, String>>>>,
    log_port: Arc<Mutex<Option<u16>>>,
    process_env: Arc<HashMap<String, String>>,
    app_path: PathBuf,
    status_events: broadcast::Sender<DaemonStatus>,
    lifecycle_epoch: Arc<AtomicU64>,
}

impl DaemonManager {
    pub fn with_runtime(
        config: DaemonConfig,
        process_env: HashMap<String, String>,
        app_path: PathBuf,
        timeout: Duration,
    ) -> Self {
        let (status_events, _) = broadcast::channel(32);
        let inner = Inner {
            status: DaemonStatus::default(),
            output: String::new(),
            child: None,
            supervisor: None,
            manual_stopped: false,
            terminate_on_drop: !keep_daemon_alive(&process_env),
            #[cfg(windows)]
            job: None,
        };
        Self {
            inner: Arc::new(Mutex::new(inner)),
            config,
            discovery_timeout: timeout,
            start_lock: Arc::new(Mutex::new(())),
            shell_env_cell: Arc::new(OnceCell::new()),
            log_port: Arc::new(Mutex::new(None)),
            process_env: Arc::new(process_env),
            app_path,
            status_events,
            lifecycle_epoch: Arc::new(AtomicU64::new(0)),
        }
    }
    pub fn subscribe(&self) -> broadcast::Receiver<DaemonStatus> {
        self.status_events.subscribe()
    }
    fn publish(&self, status: &DaemonStatus) {
        let _ = self.status_events.send(status.clone());
    }
    pub fn supervisor_connected(&self) -> bool {
        let inner = self.inner.try_lock();
        if let Ok(g) = inner {
            if let Some(s) = g.supervisor.as_ref() {
                return s.connected();
            }
        }
        false
    }
    pub fn request_shutdown(&self) {
        self.lifecycle_epoch.fetch_add(1, Ordering::SeqCst);
        let Ok(mut inner) = self.inner.try_lock() else {
            return;
        };
        let supervisor_connected = inner
            .supervisor
            .as_ref()
            .is_some_and(SupervisorLink::connected);
        if let Some(supervisor) = inner.supervisor.take() {
            supervisor.dispose();
        }
        if inner.child.is_none() || keep_daemon_alive(&self.process_env) || supervisor_connected {
            return;
        }
        #[cfg(unix)]
        if let Some(pid) = inner.child.as_ref().and_then(Child::id) {
            unsafe {
                libc::kill(-(pid as i32), libc::SIGTERM);
            }
        }
        #[cfg(windows)]
        {
            if let Some(job) = inner.job.take() {
                job.terminate();
            } else if let Some(child) = inner.child.as_mut() {
                let _ = child.start_kill();
            }
        }
    }
    async fn ensure_shell_env(&self) -> Option<HashMap<String, String>> {
        if cfg!(windows) {
            return None;
        }
        let cell = self.shell_env_cell.clone();
        let res = cell
            .get_or_init(|| async {
                let shell_path = crate::daemon::discovery::resolve_shell_path(&self.process_env);
                let args = crate::daemon::discovery::shell_env_args();
                let output = run_login_shell(&shell_path, &args, &self.process_env).await;
                if let Some(stdout) = output {
                    let parsed = crate::daemon::discovery::parse_env_block(&stdout);
                    if parsed.contains_key("PATH") {
                        return Some(parsed);
                    }
                }
                None
            })
            .await;
        res.clone()
    }
    pub async fn status(&self) -> DaemonStatus {
        {
            let guard = self.inner.lock().await;
            if guard.child.is_some() {
                return guard.status.clone();
            }
            if guard.manual_stopped {
                return guard.status.clone();
            }
        }
        if let Some((attached, info)) = self.try_attach().await {
            let should_link = info
                .as_ref()
                .and_then(|i| i.owner.as_deref())
                .map(|o| should_link_on_attach(Some(o)))
                .unwrap_or(false);
            let mut g = self.inner.lock().await;
            if should_link {
                self.establish_supervisor_link(&mut g).await;
            }
            let changed = g.status != attached;
            g.status = attached.clone();
            drop(g);
            if changed {
                self.publish(&attached);
            }
            return attached;
        }
        let mut g = self.inner.lock().await;
        if g.status.state == "ready" {
            let new_status = DaemonStatus {
                state: "stopped".to_string(),
                message: Some("Operator daemon is no longer reachable.".to_string()),
                code: Some("daemon_unreachable".to_string()),
                ..Default::default()
            };
            g.status = new_status.clone();
            drop(g);
            self.publish(&new_status);
            return new_status;
        }
        g.status.clone()
    }
    pub async fn start(&self) -> DaemonStatus {
        let guard = self.start_lock.lock().await;
        {
            let mut g = self.inner.lock().await;
            g.manual_stopped = false;
            if g.child.is_some() {
                return g.status.clone();
            }
            if g.status.state == "starting" {
                return g.status.clone();
            }
        }
        if let Some((attached, info)) = self.try_attach().await {
            let should_link = info
                .as_ref()
                .and_then(|i| i.owner.as_deref())
                .map(|o| should_link_on_attach(Some(o)))
                .unwrap_or(false);
            let mut g = self.inner.lock().await;
            if should_link {
                self.establish_supervisor_link(&mut g).await;
            }
            g.status = attached.clone();
            drop(g);
            self.publish(&attached);
            return attached;
        }
        {
            let mut g = self.inner.lock().await;
            if g.child.is_some() {
                return g.status.clone();
            }
            if g.status.state == "starting" {
                return g.status.clone();
            }
            g.status = DaemonStatus {
                state: "starting".to_string(),
                ..Default::default()
            };
            let mut log = self.log_port.lock().await;
            *log = None;
        }
        let epoch = self.lifecycle_epoch.fetch_add(1, Ordering::SeqCst) + 1;
        self.publish(&DaemonStatus {
            state: "starting".to_string(),
            ..Default::default()
        });
        let launch = self.config.launch_spec.clone().or_else(|| {
            let env = self.process_env.as_ref();
            let platform = crate::daemon::runtime_platform();
            resolve_daemon_launch(
                env,
                self.config.is_packaged,
                &self.config.resources_dir,
                &self.app_path,
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
                let status = g.status.clone();
                drop(g);
                self.publish(&status);
                return status;
            }
        };
        if launch.source == "bundled" {
            let cmd_path = PathBuf::from(&launch.command);
            if !cmd_path.exists() {
                let mut g = self.inner.lock().await;
                g.status = DaemonStatus {
                    state: "error".to_string(),
                    message: Some(format!(
                        "Bundled Operator daemon binary was not found at {}. Rebuild the desktop package.",
                        launch.command
                    )),
                    code: Some("binary_missing".to_string()),
                    executable_path: Some(launch.command.clone()),
                    working_directory: Some(launch.cwd.to_string_lossy().to_string()),
                    ..Default::default()
                };
                let status = g.status.clone();
                drop(g);
                self.publish(&status);
                return status;
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
                let status = g.status.clone();
                drop(g);
                self.publish(&status);
                return status;
            }
        }
        let env_map = self.daemon_environment(&launch).await;
        let keep = keep_daemon_alive(&env_map.clone().into_iter().collect());
        let mut cmd = if launch.shell {
            let (program, arguments) = crate::daemon::discovery::configured_shell_invocation(
                crate::daemon::runtime_platform(),
                &launch.command,
            );
            let mut command = Command::new(program);
            command.args(arguments);
            command
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
        #[cfg(unix)]
        cmd.process_group(0);
        let mut child = match cmd.spawn() {
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
                let status = g.status.clone();
                drop(g);
                self.publish(&status);
                return status;
            }
        };
        #[cfg(windows)]
        let job = match WindowsJob::assign(&child) {
            Ok(job) => job,
            Err(error) => {
                let _ = child.kill().await;
                let _ = child.wait().await;
                let status = DaemonStatus {
                    state: "error".to_string(),
                    message: Some(error.to_string()),
                    code: Some("spawn_failed".to_string()),
                    executable_path: Some(launch.command.clone()),
                    working_directory: Some(launch.cwd.to_string_lossy().to_string()),
                    ..Default::default()
                };
                let mut inner = self.inner.lock().await;
                inner.status = status.clone();
                drop(inner);
                self.publish(&status);
                return status;
            }
        };
        let pid = child.id();
        let stdout = child.stdout.take();
        let stderr = child.stderr.take();
        {
            let mut g = self.inner.lock().await;
            g.child = Some(child);
            #[cfg(windows)]
            {
                g.job = Some(job);
            }
            g.output.clear();
        }
        drop(guard);
        self.spawn_drain_tasks(stdout, stderr);
        let spawned_at = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64;
        let (port, pid_result) = self.wait_for_ready(spawned_at, pid, epoch).await;
        if self.lifecycle_epoch.load(Ordering::SeqCst) != epoch {
            let mut inner = self.inner.lock().await;
            if let Some(mut child) = inner.child.take() {
                #[cfg(windows)]
                if let Some(job) = inner.job.take() {
                    job.terminate();
                }
                terminate_owned_child(&mut child).await;
            }
            if let Some(supervisor) = inner.supervisor.take() {
                supervisor.dispose();
            }
            inner.status = DaemonStatus {
                state: "stopped".to_string(),
                ..Default::default()
            };
            inner.manual_stopped = true;
            inner.output.clear();
            let status = inner.status.clone();
            drop(inner);
            *self.log_port.lock().await = None;
            self.publish(&status);
            return status;
        }
        let mut g = self.inner.lock().await;
        if g.status.code.as_deref() == Some("exited") {
            let status = g.status.clone();
            drop(g);
            self.publish(&status);
            return status;
        }
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
            let status = g.status.clone();
            drop(g);
            self.publish(&status);
            self.spawn_child_monitor(epoch);
            return status;
        }
        if let Some(existing_port) = *self.log_port.lock().await {
            g.status = DaemonStatus {
                state: "ready".to_string(),
                port: Some(existing_port),
                pid: pid_result.or(pid),
                ..Default::default()
            };
            if !keep {
                self.establish_supervisor_link(&mut g).await;
            }
            let status = g.status.clone();
            drop(g);
            self.publish(&status);
            self.spawn_child_monitor(epoch);
            return status;
        }
        if let Some(mut child) = g.child.take() {
            #[cfg(windows)]
            if let Some(job) = g.job.take() {
                job.terminate();
            }
            terminate_owned_child(&mut child).await;
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
            message: Some(format!(
                "Operator daemon did not finish starting within {:.1} seconds.",
                self.discovery_timeout.as_secs_f64()
            )),
            details: Some(details),
            code: Some("not_ready".to_string()),
            executable_path: Some(launch.command.clone()),
            working_directory: Some(launch.cwd.to_string_lossy().to_string()),
            ..Default::default()
        };
        let status = g.status.clone();
        drop(g);
        self.publish(&status);
        status
    }
    fn spawn_child_monitor(&self, epoch: u64) {
        let inner = Arc::downgrade(&self.inner);
        let lifecycle_epoch = self.lifecycle_epoch.clone();
        let status_events = self.status_events.clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_millis(200));
            loop {
                interval.tick().await;
                if lifecycle_epoch.load(Ordering::SeqCst) != epoch {
                    return;
                }
                let Some(inner) = inner.upgrade() else {
                    return;
                };
                let exited = {
                    let mut inner = inner.lock().await;
                    let Some(child) = inner.child.as_mut() else {
                        return;
                    };
                    match child.try_wait() {
                        Ok(Some(exit)) => {
                            let exit_code = exit.code();
                            #[cfg(unix)]
                            let signal = {
                                use std::os::unix::process::ExitStatusExt;
                                exit.signal().map(|value| value.to_string())
                            };
                            #[cfg(not(unix))]
                            let signal = None;
                            inner.child.take();
                            #[cfg(windows)]
                            inner.job.take();
                            append_output(
                                &mut inner.output,
                                &format!("\nexit code {:?}", exit_code),
                            );
                            inner.status = DaemonStatus {
                                state: "error".to_string(),
                                message: Some(format!(
                                    "Daemon exited with code {:?}",
                                    exit_code.unwrap_or(-1)
                                )),
                                details: Some(inner.output.trim().to_string()),
                                code: Some("exited".to_string()),
                                exit_code,
                                signal,
                                ..Default::default()
                            };
                            Some(inner.status.clone())
                        }
                        Ok(None) => None,
                        Err(error) => {
                            inner.child.take();
                            #[cfg(windows)]
                            inner.job.take();
                            inner.status = DaemonStatus {
                                state: "error".to_string(),
                                message: Some(error.to_string()),
                                details: Some(inner.output.trim().to_string()),
                                code: Some("exited".to_string()),
                                ..Default::default()
                            };
                            Some(inner.status.clone())
                        }
                    }
                };
                if let Some(status) = exited {
                    let _ = status_events.send(status);
                    return;
                }
            }
        });
    }
    pub async fn stop(&self) -> DaemonStatus {
        self.lifecycle_epoch.fetch_add(1, Ordering::SeqCst);
        let _start_guard = self.start_lock.lock().await;
        let mut g = self.inner.lock().await;
        if let Some(mut child) = g.child.take() {
            if let Some(s) = g.supervisor.take() {
                s.dispose();
            }
            #[cfg(windows)]
            if let Some(job) = g.job.take() {
                job.terminate();
            }
            terminate_owned_child(&mut child).await;
        } else {
            if let Some(s) = g.supervisor.take() {
                s.dispose();
            }
        }
        g.status = DaemonStatus {
            state: "stopped".to_string(),
            ..Default::default()
        };
        g.manual_stopped = true;
        g.output.clear();
        let mut log = self.log_port.lock().await;
        *log = None;
        let status = g.status.clone();
        drop(log);
        drop(g);
        self.publish(&status);
        status
    }
    pub async fn restart(&self) -> DaemonStatus {
        let has_child = { self.inner.lock().await.child.is_some() };
        if !has_child {
            return self.start().await;
        }
        let child_pid = {
            let g = self.inner.lock().await;
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
                        message: Some(
                            "Operator daemon is still stopping. It will restart automatically when shutdown completes.".to_string(),
                        ),
                        details: Some(g.output.trim().to_string()),
                        code: Some("not_ready".to_string()),
                        ..Default::default()
                    };
                    let status = g.status.clone();
                    drop(g);
                    self.publish(&status);
                    return status;
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
                if !is_pid_alive(pid) {
                    break;
                }
            }
        }
        self.start().await
    }
    async fn try_attach(
        &self,
    ) -> Option<(DaemonStatus, Option<crate::daemon::discovery::RunFileInfo>)> {
        let run_file = self.config.run_file.clone();
        let contents = tokio::fs::read_to_string(&run_file).await.ok();
        let is_alive = |pid: u32| crate::daemon::discovery::process_alive(pid);
        if let Some(c) = contents {
            if let Some(info) = parse_run_file(&c) {
                if is_alive(info.pid) {
                    if let Some(health) = probe_daemon(info.port, "healthz").await {
                        if health.pid == info.pid {
                            let identity = |probe: &DaemonProbe| {
                                let env = self.process_env.as_ref();
                                let platform = crate::daemon::runtime_platform();
                                let launch = resolve_daemon_launch(
                                    env,
                                    self.config.is_packaged,
                                    &self.config.resources_dir,
                                    &self.app_path,
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
                                return Some((status, Some(info)));
                            }
                        }
                    }
                }
            }
        }
        let env = self.process_env.as_ref();
        let expected =
            crate::daemon::discovery::expected_daemon_port(env, !self.config.is_packaged);
        if let Some(health) = probe_daemon(expected, "healthz").await {
            let pid = health.pid;
            let status = readiness_status_direct(expected, pid, health, |p| {
                let env2 = self.process_env.as_ref();
                let plat = crate::daemon::runtime_platform();
                let l = resolve_daemon_launch(
                    env2,
                    self.config.is_packaged,
                    &self.config.resources_dir,
                    &self.app_path,
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
            if let Some(s) = status {
                return Some((s, None));
            }
        }
        None
    }
    async fn wait_for_ready(
        &self,
        spawned_at_ms: i64,
        spawned_pid: Option<u32>,
        epoch: u64,
    ) -> (Option<u16>, Option<u32>) {
        let run_file = self.config.run_file.clone();
        let deadline = tokio::time::Instant::now() + self.discovery_timeout;
        let mut interval = tokio::time::interval(RUN_FILE_POLL_INTERVAL);
        loop {
            if self.lifecycle_epoch.load(Ordering::SeqCst) != epoch {
                break;
            }
            {
                let mut g = self.inner.lock().await;
                if let Some(child) = g.child.as_mut() {
                    if let Ok(Some(status)) = child.try_wait() {
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
                        g.child.take();
                        #[cfg(windows)]
                        g.job.take();
                        return (None, None);
                    }
                }
            }
            if let Some(p) = *self.log_port.lock().await {
                if let Ok(contents) = tokio::fs::read_to_string(&run_file).await {
                    if let Some(info) = parse_run_file(&contents) {
                        if info.started_at_ms
                            >= spawned_at_ms - RUN_FILE_FRESHNESS_SKEW.as_millis() as i64
                            && Some(info.pid) == spawned_pid
                        {
                            return (Some(p), Some(info.pid));
                        }
                    }
                }
                return (Some(p), spawned_pid);
            }
            if let Ok(contents) = tokio::fs::read_to_string(&run_file).await {
                if let Some(info) = parse_run_file(&contents) {
                    if info.started_at_ms
                        >= spawned_at_ms - RUN_FILE_FRESHNESS_SKEW.as_millis() as i64
                        && Some(info.pid) == spawned_pid
                    {
                        return (Some(info.port), Some(info.pid));
                    }
                }
            }
            if tokio::time::Instant::now() >= deadline {
                break;
            }
            interval.tick().await;
        }
        (None, None)
    }
    fn spawn_drain_tasks(
        &self,
        stdout: Option<tokio::process::ChildStdout>,
        stderr: Option<tokio::process::ChildStderr>,
    ) {
        let inner_clone = Arc::downgrade(&self.inner);
        let log_port_clone = self.log_port.clone();
        if let Some(mut out) = stdout {
            let inner = inner_clone.clone();
            let log_port = log_port_clone.clone();
            tokio::spawn(async move {
                let mut buf = [0u8; 1024];
                let mut scanner = ListenPortScanner::new();
                loop {
                    match out.read(&mut buf).await {
                        Ok(0) => break,
                        Ok(n) => {
                            let chunk = String::from_utf8_lossy(&buf[..n]).to_string();
                            if let Some(inner) = inner.upgrade() {
                                let mut g = inner.lock().await;
                                append_output(&mut g.output, &chunk);
                            } else {
                                break;
                            }
                            if let Some(port) = scanner.feed(&chunk) {
                                let mut lp = log_port.lock().await;
                                if lp.is_none() {
                                    *lp = Some(port);
                                }
                            }
                        }
                        Err(_) => break,
                    }
                }
            });
        }
        if let Some(mut err) = stderr {
            let inner = inner_clone.clone();
            let log_port = log_port_clone.clone();
            tokio::spawn(async move {
                let mut buf = [0u8; 1024];
                let mut scanner = ListenPortScanner::new();
                loop {
                    match err.read(&mut buf).await {
                        Ok(0) => break,
                        Ok(n) => {
                            let chunk = String::from_utf8_lossy(&buf[..n]).to_string();
                            if let Some(inner) = inner.upgrade() {
                                let mut g = inner.lock().await;
                                append_output(&mut g.output, &chunk);
                            } else {
                                break;
                            }
                            if let Some(port) = scanner.feed(&chunk) {
                                let mut lp = log_port.lock().await;
                                if lp.is_none() {
                                    *lp = Some(port);
                                }
                            }
                        }
                        Err(_) => break,
                    }
                }
            });
        }
    }
    pub(crate) async fn daemon_environment(
        &self,
        _launch: &DaemonLaunchSpec,
    ) -> HashMap<String, String> {
        let env = self.process_env.as_ref();
        let mut overrides: HashMap<String, String> = HashMap::new();
        let owner = if keep_daemon_alive(env) {
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
        let agent_browser_path = resolve_agent_browser_binary_path(
            env,
            self.config.is_packaged,
            &self.config.resources_dir,
            &self.app_path,
            crate::daemon::runtime_platform(),
        );
        overrides.insert(
            "OPERATOR_AGENT_BROWSER_PATH".to_string(),
            agent_browser_path.to_string_lossy().to_string(),
        );
        overrides.insert(
            "OPERATOR_TELEMETRY_APP_VERSION".to_string(),
            self.config.app_version.clone(),
        );
        overrides.insert(
            "OPERATOR_TELEMETRY_RENDERER".to_string(),
            telemetry_renderer_env(env, self.config.is_packaged),
        );
        if let Some(origin) = allowed_origins_override(env, self.config.is_packaged) {
            overrides.insert("OPERATOR_ALLOWED_ORIGINS".to_string(), origin);
        }
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
        let shell_env = self.ensure_shell_env().await;
        let mut daemon_env =
            crate::daemon::discovery::build_daemon_env(env, shell_env.as_ref(), &overrides);
        daemon_env.remove("OPERATOR_BROWSER_RUNTIME_TOKEN");
        daemon_env.remove("OPERATOR_BROWSER_RUNTIME_TOKEN_STDIN");
        daemon_env
    }
    async fn establish_supervisor_link(&self, inner: &mut Inner) {
        #[cfg(not(windows))]
        {
            if inner.supervisor.is_none() {
                let addr = supervisor_addr(&self.config.run_file);
                inner.supervisor = Some(SupervisorLink::new(addr));
            }
        }
        #[cfg(windows)]
        {
            if inner.supervisor.is_none() {
                let addr = supervisor_addr(&self.config.run_file);
                inner.supervisor = Some(SupervisorLink::new_windows(addr));
            }
        }
    }
}

#[cfg(windows)]
#[derive(Debug)]
struct WindowsJob {
    handle: isize,
}

#[cfg(windows)]
impl WindowsJob {
    fn assign(child: &Child) -> std::io::Result<Self> {
        use std::ffi::c_void;
        use windows_sys::Win32::Foundation::{CloseHandle, HANDLE};
        use windows_sys::Win32::System::JobObjects::{
            AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
            SetInformationJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
            JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
        };

        let handle = unsafe { CreateJobObjectW(std::ptr::null(), std::ptr::null()) };
        if handle.is_null() {
            return Err(std::io::Error::last_os_error());
        }
        let mut limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        let configured = unsafe {
            SetInformationJobObject(
                handle,
                JobObjectExtendedLimitInformation,
                &limits as *const _ as *const c_void,
                std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            )
        };
        let Some(process) = child.raw_handle() else {
            unsafe {
                CloseHandle(handle);
            }
            return Err(std::io::Error::other(
                "spawned daemon has no process handle",
            ));
        };
        if configured == 0 || unsafe { AssignProcessToJobObject(handle, process as HANDLE) } == 0 {
            let error = std::io::Error::last_os_error();
            unsafe {
                CloseHandle(handle);
            }
            return Err(error);
        }
        Ok(Self {
            handle: handle as isize,
        })
    }

    fn terminate(self) {
        use windows_sys::Win32::Foundation::HANDLE;
        use windows_sys::Win32::System::JobObjects::TerminateJobObject;
        unsafe {
            TerminateJobObject(self.handle as HANDLE, 1);
        }
    }
}

#[cfg(windows)]
impl Drop for WindowsJob {
    fn drop(&mut self) {
        use windows_sys::Win32::Foundation::{CloseHandle, HANDLE};
        unsafe {
            CloseHandle(self.handle as HANDLE);
        }
    }
}

async fn terminate_owned_child(child: &mut Child) {
    #[cfg(unix)]
    {
        if let Some(pid) = child.id() {
            unsafe {
                libc::kill(-(pid as i32), libc::SIGTERM);
            }
        }
        if tokio::time::timeout(Duration::from_secs(2), child.wait())
            .await
            .is_err()
        {
            if let Some(pid) = child.id() {
                unsafe {
                    libc::kill(-(pid as i32), libc::SIGKILL);
                }
            }
            let _ = child.wait().await;
        }
    }
    #[cfg(windows)]
    {
        let _ = child.kill().await;
        let _ = child.wait().await;
    }
}

async fn run_login_shell(
    shell_path: &str,
    args: &[String],
    process_env: &HashMap<String, String>,
) -> Option<String> {
    let mut cmd = Command::new(shell_path);
    cmd.args(args);
    cmd.env_clear();
    cmd.envs(process_env);
    cmd.stdin(std::process::Stdio::null());
    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::null());
    let mut child = cmd.spawn().ok()?;
    let stdout = child.stdout.take()?;
    let output = tokio::time::timeout(SHELL_ENV_TIMEOUT, async {
        let mut out = Vec::new();
        let mut reader = tokio::io::BufReader::new(stdout);
        let mut buf = vec![0u8; 4096];
        loop {
            match reader.read(&mut buf).await {
                Ok(0) => break,
                Ok(n) => out.extend_from_slice(&buf[..n]),
                Err(_) => break,
            }
        }
        let _ = child.wait().await;
        String::from_utf8(out).ok()
    })
    .await;
    match output {
        Ok(Some(s)) => Some(s),
        _ => {
            let _ = child.kill().await;
            None
        }
    }
}

fn append_output(output: &mut String, text: &str) {
    output.push_str(text);
    if output.len() > MAX_DAEMON_OUTPUT_CHARS {
        let start = output.len() - MAX_DAEMON_OUTPUT_CHARS;
        let boundary = output.floor_char_boundary(start);
        *output = output[boundary..].to_string();
    }
}

fn is_pid_alive(pid: u32) -> bool {
    crate::daemon::discovery::process_alive(pid)
}

fn daemon_identity_error(launch: &DaemonLaunchSpec, probe: &DaemonProbe) -> Option<String> {
    if launch.source == "dev" {
        let cwd_matches = probe
            .working_directory
            .as_ref()
            .map(|wd| same_path(wd, launch.cwd.to_string_lossy().as_ref()))
            .unwrap_or(false);
        let startup_matches = probe
            .startup_working_directory
            .as_ref()
            .map(|wd| same_path(wd, launch.cwd.to_string_lossy().as_ref()))
            .unwrap_or(false);
        let exec_matches = probe
            .executable_path
            .as_ref()
            .map(|ep| path_inside(ep, launch.cwd.to_string_lossy().as_ref()))
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
    let path = PathBuf::from(value);
    let normalized = std::fs::canonicalize(&path)
        .unwrap_or_else(|_| crate::daemon::discovery::normalize_path(&path));
    let s = normalized.to_string_lossy().to_string();
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
