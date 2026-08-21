use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq)]
pub struct DaemonLaunchSpec {
    pub command: String,
    pub args: Vec<String>,
    pub cwd: PathBuf,
    pub shell: bool,
    pub source: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RunFileInfo {
    pub pid: u32,
    pub port: u16,
    pub started_at_ms: i64,
    pub owner: Option<String>,
    pub app_run_id: Option<String>,
    pub browser_runtime_address: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DaemonProbe {
    pub status: String,
    pub service: String,
    pub pid: u32,
    pub executable_path: Option<String>,
    pub working_directory: Option<String>,
    pub startup_working_directory: Option<String>,
}

pub fn bundled_daemon_binary_name(platform: &str) -> &'static str {
    if platform == "win32" {
        "opr.exe"
    } else {
        "opr"
    }
}

pub fn bundled_agent_browser_binary_name(platform: &str) -> &'static str {
    if platform == "win32" {
        "agent-browser.exe"
    } else {
        "agent-browser"
    }
}

pub fn keep_daemon_alive(env: &HashMap<String, String>) -> bool {
    match env
        .get("OPERATOR_KEEP_DAEMON")
        .map(|v| v.trim().to_lowercase())
    {
        Some(s) => s == "1" || s == "true" || s == "yes" || s == "on",
        None => false,
    }
}

pub fn should_link_on_attach(owner: Option<&str>) -> bool {
    matches!(owner, Some("app"))
}

pub fn resolve_daemon_launch(
    env: &HashMap<String, String>,
    is_packaged: bool,
    resources_path: &Path,
    app_path: &Path,
    home_dir: &Path,
    platform: &str,
) -> Option<DaemonLaunchSpec> {
    if let Some(raw) = env.get("OPERATOR_DAEMON_COMMAND") {
        let trimmed = raw.trim();
        if !trimmed.is_empty() {
            return Some(DaemonLaunchSpec {
                command: trimmed.to_string(),
                args: vec![],
                cwd: app_path.to_path_buf(),
                shell: true,
                source: "configured".to_string(),
            });
        }
    }
    if !is_packaged {
        return Some(DaemonLaunchSpec {
            command: "go".to_string(),
            args: vec![
                "run".to_string(),
                "./cmd/opr".to_string(),
                "daemon".to_string(),
            ],
            cwd: app_path.join("../backend"),
            shell: false,
            source: "dev".to_string(),
        });
    }
    let bin = bundled_daemon_binary_name(platform);
    let command = resources_path.join("daemon").join(bin);
    let cwd = home_dir.join(".operator");
    Some(DaemonLaunchSpec {
        command: command.to_string_lossy().to_string(),
        args: vec!["daemon".to_string()],
        cwd,
        shell: false,
        source: "bundled".to_string(),
    })
}

pub fn resolve_agent_browser_binary_path(
    env: &HashMap<String, String>,
    is_packaged: bool,
    resources_path: &Path,
    app_path: &Path,
    platform: &str,
) -> PathBuf {
    if let Some(raw) = env.get("OPERATOR_AGENT_BROWSER_PATH") {
        let trimmed = raw.trim();
        if !trimmed.is_empty() {
            let p = PathBuf::from(trimmed);
            if p.is_absolute() {
                return p;
            }
            if let Ok(cwd) = std::env::current_dir() {
                return cwd.join(p);
            }
            return p;
        }
    }
    let bin = bundled_agent_browser_binary_name(platform);
    if is_packaged {
        resources_path.join("agent-browser").join(bin)
    } else {
        app_path.join("agent-browser").join(bin)
    }
}

pub fn resolve_acp_runtime_dir(
    env: &HashMap<String, String>,
    is_packaged: bool,
    resources_path: &Path,
    app_path: &Path,
) -> PathBuf {
    if let Some(raw) = env.get("OPERATOR_ACP_RUNTIME_DIR") {
        let trimmed = raw.trim();
        if !trimmed.is_empty() {
            let p = PathBuf::from(trimmed);
            if p.is_absolute() {
                return p;
            }
            if let Ok(cwd) = std::env::current_dir() {
                return cwd.join(p);
            }
            return p;
        }
    }
    if is_packaged {
        resources_path.join("acp-runtime")
    } else {
        app_path.join("resources").join("acp-runtime")
    }
}

pub fn default_run_file_path(home_dir: &Path) -> Option<PathBuf> {
    if home_dir.as_os_str().is_empty() {
        return None;
    }
    Some(home_dir.join(".operator").join("running.json"))
}

pub fn resolve_run_file_path(
    env: &HashMap<String, String>,
    home_dir: &Path,
    is_packaged: bool,
) -> Option<PathBuf> {
    if let Some(raw) = env.get("OPERATOR_RUN_FILE") {
        let trimmed = raw.trim();
        if !trimmed.is_empty() {
            let p = PathBuf::from(trimmed);
            if p.is_absolute() {
                return Some(p);
            }
            if let Ok(cwd) = std::env::current_dir() {
                return Some(cwd.join(p));
            }
            return Some(p);
        }
    }
    if !is_packaged {
        return Some(home_dir.join(".operator").join("dev").join("running.json"));
    }
    default_run_file_path(home_dir)
}

pub fn resolve_data_dir(
    env: &HashMap<String, String>,
    home_dir: &Path,
    is_packaged: bool,
) -> Option<PathBuf> {
    if let Some(raw) = env.get("OPERATOR_DATA_DIR") {
        let trimmed = raw.trim();
        if !trimmed.is_empty() {
            let p = PathBuf::from(trimmed);
            if p.is_absolute() {
                return Some(p);
            }
            if let Ok(cwd) = std::env::current_dir() {
                return Some(cwd.join(p));
            }
            return Some(p);
        }
    }
    if !is_packaged {
        return Some(home_dir.join(".operator").join("dev").join("data"));
    }
    Some(home_dir.join(".operator").join("data"))
}

pub fn expected_daemon_port(env: &HashMap<String, String>, is_dev: bool) -> u16 {
    if is_dev {
        if let Some(v) = env.get("OPERATOR_PORT") {
            if v.trim().is_empty() {
                return 3002;
            }
        } else {
            return 3002;
        }
    }
    if let Some(raw) = env.get("OPERATOR_PORT") {
        let trimmed = raw.trim();
        if let Ok(n) = trimmed.parse::<u32>() {
            if n >= 1 && n <= 65535 {
                if trimmed
                    .parse::<f64>()
                    .map(|f| f.fract() == 0.0)
                    .unwrap_or(false)
                {
                    return n as u16;
                }
                if !trimmed.contains('.') {
                    return n as u16;
                }
            }
        }
        return 3001;
    }
    3001
}

pub fn parse_daemon_listen_port(line: &str) -> Option<u16> {
    if !line.contains("msg=\"daemon listening\"") {
        return None;
    }
    let addr_start = line.find("addr=")?;
    let mut rest = &line[addr_start + 5..];
    let quoted = rest.starts_with('"');
    if quoted {
        rest = &rest[1..];
        let end = rest.find('"')?;
        rest = &rest[..end];
    } else {
        let end = rest.find(|c: char| c.is_whitespace()).unwrap_or(rest.len());
        rest = &rest[..end];
    }
    port_from_addr(rest)
}

fn port_from_addr(addr: &str) -> Option<u16> {
    let sep = addr.rfind(':')?;
    let port_str = &addr[sep + 1..];
    let port = port_str.parse::<u32>().ok()?;
    if port >= 1 && port <= 65535 {
        Some(port as u16)
    } else {
        None
    }
}

pub struct ListenPortScanner {
    pending: String,
    done: bool,
    found: Option<u16>,
}

impl ListenPortScanner {
    pub fn new() -> Self {
        Self {
            pending: String::new(),
            done: false,
            found: None,
        }
    }
    pub fn feed(&mut self, chunk: &str) -> Option<u16> {
        if self.done {
            return None;
        }
        self.pending.push_str(chunk);
        let lines: Vec<String> = self.pending.split('\n').map(|s| s.to_string()).collect();
        let pending = lines.last().cloned().unwrap_or_default();
        self.pending = pending;
        for line in lines.iter().take(lines.len().saturating_sub(1)) {
            if let Some(port) = parse_daemon_listen_port(line) {
                self.done = true;
                self.found = Some(port);
                return Some(port);
            }
        }
        if lines.len() == 1 && self.pending.is_empty() {
            return None;
        }
        if self.pending.is_empty() {
            return None;
        }
        None
    }
    pub fn found(&self) -> Option<u16> {
        self.found
    }
}

impl Default for ListenPortScanner {
    fn default() -> Self {
        Self::new()
    }
}

pub fn parse_run_file(contents: &str) -> Option<RunFileInfo> {
    let v: serde_json::Value = serde_json::from_str(contents).ok()?;
    let obj = v.as_object()?;
    let port_u64 = obj.get("port")?.as_u64()?;
    if port_u64 < 1 || port_u64 > 65535 {
        return None;
    }
    let port = port_u64 as u16;
    let pid = obj.get("pid").and_then(|x| x.as_u64()).unwrap_or(0) as u32;
    let started_at_ms = obj
        .get("startedAt")
        .and_then(|x| x.as_str())
        .and_then(|s| parse_started_at_ms(s))
        .unwrap_or(0);
    let owner = obj
        .get("owner")
        .and_then(|x| x.as_str())
        .map(|s| s.to_string());
    let app_run_id = obj
        .get("appRunId")
        .and_then(|x| x.as_str())
        .map(|s| s.to_string());
    let browser_runtime_address = obj
        .get("browserRuntimeAddress")
        .and_then(|x| x.as_str())
        .map(|s| s.to_string());
    Some(RunFileInfo {
        pid,
        port,
        started_at_ms,
        owner,
        app_run_id,
        browser_runtime_address,
    })
}

fn parse_started_at_ms(s: &str) -> Option<i64> {
    let dt = chrono::DateTime::parse_from_rfc3339(s).ok()?;
    Some(dt.timestamp_millis())
}

#[cfg(not(windows))]
pub fn supervisor_addr(run_file: &Path) -> PathBuf {
    run_file
        .parent()
        .unwrap_or(Path::new("."))
        .join("supervise.sock")
}

#[cfg(windows)]
pub fn supervisor_addr(run_file: &Path) -> String {
    if run_file.as_os_str().is_empty() {
        return r"\\.\pipe\opr-supervise".to_string();
    }
    let dir = run_file
        .parent()
        .and_then(|p| p.file_name())
        .and_then(|s| s.to_str())
        .unwrap_or("");
    if dir == ".operator" || dir == "." || dir.is_empty() {
        return r"\\.\pipe\opr-supervise".to_string();
    }
    let sanitized: String = dir
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' {
                c
            } else {
                '-'
            }
        })
        .collect();
    format!(r"\\.\pipe\opr-supervise-{}", sanitized)
}

pub fn parse_daemon_probe(endpoint: &str, body: &serde_json::Value) -> Option<DaemonProbe> {
    let obj = body.as_object()?;
    let status = obj.get("status")?.as_str()?;
    let expected = if endpoint == "healthz" { "ok" } else { "ready" };
    if status != expected {
        return None;
    }
    let service = obj.get("service")?.as_str()?;
    if service != "operator-daemon" {
        return None;
    }
    let pid = obj.get("pid")?.as_u64()? as u32;
    if obj
        .get("pid")
        .and_then(|v| v.as_f64())
        .map(|f| f.fract() != 0.0)
        .unwrap_or(false)
    {
        return None;
    }
    let executable_path = obj
        .get("executablePath")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());
    let working_directory = obj
        .get("workingDirectory")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());
    let startup_working_directory = obj
        .get("startupWorkingDirectory")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());
    Some(DaemonProbe {
        status: status.to_string(),
        service: service.to_string(),
        pid,
        executable_path,
        working_directory,
        startup_working_directory,
    })
}

pub fn should_replace_port_holder(probe: Option<&DaemonProbe>, holder_pid_alive: bool) -> bool {
    probe.is_some() || holder_pid_alive
}

#[derive(Debug, PartialEq)]
pub enum BrowserDaemonOwnershipDecision {
    Attach,
    Replace { keep_alive: bool },
}

pub fn browser_daemon_ownership_decision(
    current_app_run_id: &str,
    existing: &RunFileInfo,
) -> BrowserDaemonOwnershipDecision {
    if existing.app_run_id.as_deref() == Some(current_app_run_id) {
        BrowserDaemonOwnershipDecision::Attach
    } else {
        let keep_alive = existing.owner.as_deref() != Some("app");
        BrowserDaemonOwnershipDecision::Replace { keep_alive }
    }
}

pub fn with_fallback_path(current_path: Option<&str>) -> String {
    let mut result: Vec<String> = current_path
        .unwrap_or("")
        .split(':')
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .collect();
    let present: std::collections::HashSet<String> = result.iter().cloned().collect();
    let floor = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ];
    for dir in floor.iter() {
        if !present.contains(*dir) {
            result.push(dir.to_string());
        }
    }
    result.join(":")
}

pub fn normalize_term(term: Option<&str>) -> String {
    let trimmed = term.map(|s| s.trim()).unwrap_or("");
    if trimmed.is_empty() || trimmed == "dumb" {
        "xterm-256color".to_string()
    } else {
        trimmed.to_string()
    }
}

pub fn shell_env_args() -> Vec<String> {
    vec![
        "-ilc".to_string(),
        "printf '%s' '__OPERATOR_SHELL_ENV__'; env -0".to_string(),
    ]
}

pub fn parse_env_block(stdout: &str) -> HashMap<String, String> {
    let sentinel = "__OPERATOR_SHELL_ENV__";
    let at = stdout
        .rfind(sentinel)
        .map(|i| i + sentinel.len())
        .unwrap_or(0);
    let block = &stdout[at..];
    let mut out = HashMap::new();
    for rec in block.split('\0') {
        if rec.is_empty() {
            continue;
        }
        let eq = rec.find('=');
        if let Some(idx) = eq {
            if idx == 0 {
                continue;
            }
            out.insert(rec[..idx].to_string(), rec[idx + 1..].to_string());
        }
    }
    out
}

pub fn resolve_shell_path(env: &HashMap<String, String>) -> String {
    if let Some(shell) = env.get("SHELL") {
        let trimmed = shell.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }
    "/bin/zsh".to_string()
}

pub fn build_daemon_env(
    process_env: &HashMap<String, String>,
    shell_env: Option<&HashMap<String, String>>,
    overrides: &HashMap<String, String>,
) -> HashMap<String, String> {
    let mut merged: HashMap<String, String> = HashMap::new();
    merged.insert("TERM".to_string(), "xterm-256color".to_string());
    if let Some(se) = shell_env {
        for (k, v) in se.iter() {
            merged.insert(k.clone(), v.clone());
        }
    }
    for (k, v) in process_env.iter() {
        merged.insert(k.clone(), v.clone());
    }
    let shell_path = shell_env.and_then(|m| m.get("PATH")).map(|s| s.as_str());
    let proc_path = process_env.get("PATH").map(|s| s.as_str());
    let chosen = shell_path.or(proc_path);
    let with_floor = with_fallback_path(chosen);
    merged.insert("PATH".to_string(), with_floor);
    let term_val = merged.get("TERM").map(|s| s.as_str());
    let normalized = normalize_term(term_val);
    merged.insert("TERM".to_string(), normalized);
    for (k, v) in overrides.iter() {
        merged.insert(k.clone(), v.clone());
    }
    merged
}

#[cfg(unix)]
pub fn process_alive(pid: u32) -> bool {
    if pid == 0 {
        return false;
    }
    unsafe { libc::kill(pid as i32, 0) == 0 }
}

#[cfg(windows)]
pub fn process_alive(pid: u32) -> bool {
    pid != 0
}
