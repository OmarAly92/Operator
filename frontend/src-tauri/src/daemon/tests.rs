use crate::daemon::discovery::{
    bundled_daemon_binary_name, configured_shell_invocation, keep_daemon_alive,
    parse_daemon_listen_port, parse_daemon_probe, parse_run_file, resolve_acp_runtime_dir,
    resolve_agent_browser_binary_path, resolve_daemon_launch, resolve_data_dir,
    resolve_run_file_path, should_link_on_attach, supervisor_addr, with_fallback_path,
    with_fallback_path_for, ListenPortScanner,
};
use crate::daemon::supervisor::{
    allowed_origins_override, telemetry_renderer_env, DaemonConfig, DaemonManager,
};
use crate::daemon::DaemonStatus;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
#[cfg(unix)]
use tokio::net::UnixListener;

struct TestRoot(PathBuf);

impl TestRoot {
    fn track(path: PathBuf) -> Self {
        Self(path)
    }
}

impl std::ops::Deref for TestRoot {
    type Target = PathBuf;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl AsRef<Path> for TestRoot {
    fn as_ref(&self) -> &Path {
        &self.0
    }
}

impl Drop for TestRoot {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn env_from(pairs: &[(&str, &str)]) -> HashMap<String, String> {
    pairs
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

fn test_manager(config: DaemonConfig) -> DaemonManager {
    test_manager_with_timeout(config, Duration::from_secs(30))
}

fn test_manager_with_timeout(config: DaemonConfig, timeout: Duration) -> DaemonManager {
    let home = config.home_dir.to_string_lossy().to_string();
    let port = std::net::TcpListener::bind(("127.0.0.1", 0))
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
        .to_string();
    let process_env = env_from(&[
        ("HOME", &home),
        ("PATH", "/usr/bin:/bin"),
        ("SHELL", "/usr/bin/false"),
        ("OPERATOR_PORT", &port),
    ]);
    DaemonManager::with_runtime(
        config,
        process_env,
        std::env::current_dir().unwrap(),
        timeout,
    )
}

#[test]
fn daemon_status_wire_shape_is_camel_case_and_omits_absent_fields() {
    let status = DaemonStatus {
        state: "error".to_string(),
        executable_path: Some("/opt/Operator/opr".to_string()),
        exit_code: Some(17),
        ..Default::default()
    };

    assert_eq!(
        serde_json::to_value(status).unwrap(),
        serde_json::json!({
            "state": "error",
            "executablePath": "/opt/Operator/opr",
            "exitCode": 17
        })
    );
}

#[test]
fn daemon_keep_alive_allowlist() {
    assert!(!keep_daemon_alive(&env_from(&[])));
    assert!(!keep_daemon_alive(&env_from(&[(
        "OPERATOR_KEEP_DAEMON",
        ""
    )])));
    for v in ["1", "true", "TRUE", "yes", "on", "ON", "Yes"] {
        assert!(keep_daemon_alive(&env_from(&[("OPERATOR_KEEP_DAEMON", v)])));
    }
    for v in [
        "0", "false", "FALSE", "off", "OFF", "no", "No", "2", "random",
    ] {
        assert!(!keep_daemon_alive(&env_from(&[(
            "OPERATOR_KEEP_DAEMON",
            v
        )])));
    }
    assert!(keep_daemon_alive(&env_from(&[(
        "OPERATOR_KEEP_DAEMON",
        "  1  "
    )])));
}

#[test]
fn daemon_should_link_on_attach() {
    assert!(should_link_on_attach(Some("app")));
    assert!(!should_link_on_attach(None));
    assert!(!should_link_on_attach(Some("")));
    assert!(!should_link_on_attach(Some("persistent")));
    assert!(!should_link_on_attach(Some("cli")));
}

#[test]
fn daemon_discovery_bundled_dev() {
    let env = env_from(&[]);
    let resources = PathBuf::from("/Applications/Operator.app/Contents/Resources");
    let app_path = PathBuf::from("/repo/frontend");
    let home = PathBuf::from("/home/user");
    let spec = resolve_daemon_launch(&env, false, &resources, &app_path, &home, "darwin").unwrap();
    assert_eq!(spec.command, "go");
    assert_eq!(spec.args, vec!["run", "./cmd/opr", "daemon"]);
    assert_eq!(spec.source, "dev");
    assert_eq!(spec.cwd, PathBuf::from("/repo/backend"));
}

#[test]
fn daemon_discovery_dev_accepts_the_tauri_manifest_directory() {
    let env = env_from(&[]);
    let resources = PathBuf::from("/repo/frontend/src-tauri/target/debug/resources");
    let app_path = PathBuf::from("/repo/frontend/src-tauri");
    let home = PathBuf::from("/home/user");
    let spec = resolve_daemon_launch(&env, false, &resources, &app_path, &home, "darwin").unwrap();

    assert_eq!(spec.command, "go");
    assert_eq!(spec.cwd, PathBuf::from("/repo/backend"));
}

#[test]
fn daemon_discovery_bundled_packaged_macos() {
    let env = env_from(&[]);
    let resources = PathBuf::from("/Applications/Operator.app/Contents/Resources");
    let app_path = PathBuf::from("/app");
    let home = PathBuf::from("/Users/alice");
    let spec = resolve_daemon_launch(&env, true, &resources, &app_path, &home, "darwin").unwrap();
    assert_eq!(
        spec.command,
        "/Applications/Operator.app/Contents/Resources/daemon/opr"
    );
    assert_eq!(spec.args, vec!["daemon"]);
    assert_eq!(spec.source, "bundled");
    assert_eq!(spec.cwd, PathBuf::from("/Users/alice/.operator"));
}

#[test]
fn daemon_discovery_bundled_packaged_windows() {
    let env = env_from(&[]);
    let resources = PathBuf::from("C:\\Program Files\\Operator\\resources");
    let app_path = PathBuf::from("C:\\Program Files\\Operator\\resources\\app.asar");
    let home = PathBuf::from("C:\\Users\\alice");
    let spec = resolve_daemon_launch(&env, true, &resources, &app_path, &home, "win32").unwrap();
    assert!(spec.command.contains("opr.exe"));
    assert_eq!(spec.source, "bundled");
}

#[test]
fn daemon_discovery_agent_browser_dev_and_packaged() {
    let env = env_from(&[]);
    let resources = PathBuf::from("/resources");
    let app_path = PathBuf::from("/repo/frontend");
    let dev = resolve_agent_browser_binary_path(&env, false, &resources, &app_path, "darwin");
    assert!(dev.to_string_lossy().contains("agent-browser"));
    assert!(dev.to_string_lossy().contains("/repo/frontend"));
    let prod = resolve_agent_browser_binary_path(&env, true, &resources, &app_path, "darwin");
    assert!(prod.to_string_lossy().contains("/resources/agent-browser"));
}

#[test]
fn daemon_discovery_acp_runtime_dev_and_packaged() {
    let env = env_from(&[]);
    let resources = PathBuf::from("/resources");
    let app_path = PathBuf::from("/repo/frontend");
    let dev = resolve_acp_runtime_dir(&env, false, &resources, &app_path);
    assert!(dev.to_string_lossy().contains("resources/acp-runtime"));
    let prod = resolve_acp_runtime_dir(&env, true, &resources, &app_path);
    assert_eq!(prod, PathBuf::from("/resources/acp-runtime"));
}

#[test]
fn daemon_telemetry_renderer_intent_defaults_to_packaging() {
    assert_eq!(telemetry_renderer_env(&env_from(&[]), true), "on");
    assert_eq!(telemetry_renderer_env(&env_from(&[]), false), "off");
    assert_eq!(
        telemetry_renderer_env(&env_from(&[("OPERATOR_TELEMETRY_RENDERER", "off")]), true),
        "off"
    );
    assert_eq!(
        telemetry_renderer_env(&env_from(&[("OPERATOR_TELEMETRY_RENDERER", "on")]), false),
        "on"
    );
    assert_eq!(
        telemetry_renderer_env(&env_from(&[("OPERATOR_TELEMETRY_RENDERER", "  ")]), true),
        "on"
    );
}

#[test]
fn daemon_discovery_run_file_and_data_dir() {
    let env = env_from(&[]);
    let home = PathBuf::from("/home/user");
    let run_dev = resolve_run_file_path(&env, &home, false).unwrap();
    assert_eq!(
        run_dev,
        PathBuf::from("/home/user/.operator/dev/running.json")
    );
    let run_prod = resolve_run_file_path(&env, &home, true).unwrap();
    assert_eq!(run_prod, PathBuf::from("/home/user/.operator/running.json"));
    let data_dev = resolve_data_dir(&env, &home, false).unwrap();
    assert_eq!(data_dev, PathBuf::from("/home/user/.operator/dev/data"));
    let data_prod = resolve_data_dir(&env, &home, true).unwrap();
    assert_eq!(data_prod, PathBuf::from("/home/user/.operator/data"));
    let env2 = env_from(&[("OPERATOR_RUN_FILE", "/tmp/custom.json")]);
    assert_eq!(
        resolve_run_file_path(&env2, &home, false).unwrap(),
        PathBuf::from("/tmp/custom.json")
    );
}

#[test]
fn daemon_parse_listen_port() {
    assert_eq!(
        parse_daemon_listen_port(
            "time=2026 level=INFO msg=\"daemon listening\" addr=127.0.0.1:3001 pid=1"
        ),
        Some(3001)
    );
    assert_eq!(
        parse_daemon_listen_port("msg=\"daemon listening\" addr=\"127.0.0.1:3002\""),
        Some(3002)
    );
    assert_eq!(
        parse_daemon_listen_port("msg=\"daemon listening\" addr=[::1]:4000"),
        Some(4000)
    );
    assert_eq!(parse_daemon_listen_port("other log line"), None);
    assert_eq!(
        parse_daemon_listen_port("msg=\"daemon listening\" addr=invalid"),
        None
    );
}

#[test]
fn daemon_listen_port_scanner() {
    let mut scanner = ListenPortScanner::new();
    assert_eq!(scanner.feed("time"), None);
    assert_eq!(
        scanner.feed(" msg=\"daemon listening\" addr=127.0.0.1:3001\nrest"),
        Some(3001)
    );
    assert_eq!(scanner.feed("more"), None);
}

#[test]
fn daemon_parse_run_file() {
    let json = r#"{"pid":4242,"port":3001,"startedAt":"2026-06-10T16:15:04Z","owner":"app","appRunId":"apprun-abc"}"#;
    let info = parse_run_file(json).unwrap();
    assert_eq!(info.pid, 4242);
    assert_eq!(info.port, 3001);
    assert_eq!(info.owner, Some("app".to_string()));
    assert_eq!(info.app_run_id, Some("apprun-abc".to_string()));
    assert!(info.started_at_ms > 0);
    assert!(parse_run_file("{not json").is_none());
    assert!(parse_run_file(r#"{"pid":1,"port":99999}"#).is_none());
}

#[test]
fn daemon_parse_probe() {
    let health = serde_json::json!({"status":"ok","service":"operator-daemon","pid":4242});
    let p = parse_daemon_probe("healthz", &health).unwrap();
    assert_eq!(p.pid, 4242);
    assert_eq!(p.status, "ok");
    let ready = serde_json::json!({"status":"ready","service":"operator-daemon","pid":4242,"executablePath":"/bin/opr"});
    let r = parse_daemon_probe("readyz", &ready).unwrap();
    assert_eq!(r.executable_path, Some("/bin/opr".to_string()));
    assert!(parse_daemon_probe("healthz", &ready).is_none());
    assert!(parse_daemon_probe(
        "healthz",
        &serde_json::json!({"status":"ok","service":"other","pid":1})
    )
    .is_none());
}

#[test]
fn daemon_supervisor_addr() {
    let p = PathBuf::from("/home/user/.operator/running.json");
    let addr = supervisor_addr(&p);
    let p2 = PathBuf::from("/home/user/.operator/dev/running.json");
    let addr2 = supervisor_addr(&p2);
    #[cfg(not(windows))]
    {
        assert!(addr.to_string_lossy().contains("supervise.sock"));
        assert!(addr2.to_string_lossy().contains("supervise.sock"));
    }
    #[cfg(windows)]
    {
        assert!(addr.starts_with(r"\\.\pipe\opr-supervise"));
        assert!(addr2.starts_with(r"\\.\pipe\opr-supervise"));
    }
}

#[tokio::test]
async fn daemon_healthy_attachment_via_runfile_and_probe() {
    let tmp = TestRoot::track(
        std::env::temp_dir().join(format!("daemon-test-healthy-{}", uuid::Uuid::new_v4())),
    );
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let run_file = tmp.join("running.json");
    let data_dir = tmp.join("data");
    tokio::fs::create_dir_all(&data_dir).await.unwrap();
    let daemon_dir = tmp.join("daemon");
    tokio::fs::create_dir_all(&daemon_dir).await.unwrap();
    let daemon_bin = daemon_dir.join("opr");
    tokio::fs::write(&daemon_bin, b"").await.unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let pid = std::process::id();
    let started = chrono::Utc::now().to_rfc3339();
    let run_info = serde_json::json!({"pid": pid, "port": port, "startedAt": started, "owner":"app", "appRunId":"apprun-test"});
    tokio::fs::write(&run_file, serde_json::to_string(&run_info).unwrap())
        .await
        .unwrap();
    let daemon_bin_clone = daemon_bin.clone();
    let server = tokio::spawn(async move {
        loop {
            let (mut socket, _) = listener.accept().await.unwrap();
            let bin_path = daemon_bin_clone.clone();
            tokio::spawn(async move {
                let mut buf = [0u8; 2048];
                let n = socket.read(&mut buf).await.unwrap_or(0);
                let req = String::from_utf8_lossy(&buf[..n]);
                let bin_str = bin_path.to_string_lossy().to_string();
                let body = if req.contains("GET /healthz") {
                    format!(
                        r#"{{"status":"ok","service":"operator-daemon","pid":{},"executablePath":"{}"}}"#,
                        pid, bin_str
                    )
                } else if req.contains("GET /readyz") {
                    format!(
                        r#"{{"status":"ready","service":"operator-daemon","pid":{},"executablePath":"{}"}}"#,
                        pid, bin_str
                    )
                } else {
                    r#"{"status":"notfound"}"#.to_string()
                };
                let resp = format!("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}", body.len(), body);
                let _ = socket.write_all(resp.as_bytes()).await;
            });
        }
    });
    let config = DaemonConfig {
        run_file: run_file.clone(),
        data_dir: data_dir.clone(),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: "apprun-test".to_string(),
        launch_spec: None,
    };
    let manager = test_manager(config);
    let status = manager.status().await;
    assert_eq!(status.state, "ready");
    assert_eq!(status.port, Some(port));
    server.abort();
    tokio::fs::remove_dir_all(&tmp).await.unwrap_or(());
}

#[tokio::test]
async fn daemon_stale_runfile_treated_as_missing() {
    let tmp = TestRoot::track(
        std::env::temp_dir().join(format!("daemon-test-stale-{}", uuid::Uuid::new_v4())),
    );
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let run_file = tmp.join("running.json");
    let data_dir = tmp.join("data");
    tokio::fs::create_dir_all(&data_dir).await.unwrap();
    let dead_pid = 999999;
    let started = chrono::Utc::now().to_rfc3339();
    let run_info =
        serde_json::json!({"pid": dead_pid, "port": 3001, "startedAt": started, "owner":"app"});
    tokio::fs::write(&run_file, serde_json::to_string(&run_info).unwrap())
        .await
        .unwrap();
    let config = DaemonConfig {
        run_file: run_file.clone(),
        data_dir: data_dir.clone(),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: false,
        app_run_id: "apprun-new".to_string(),
        launch_spec: None,
    };
    let manager = test_manager(config);
    let status = manager.status().await;
    assert_eq!(status.state, "stopped");
    assert!(status.port.is_none());
    assert!(status.code.is_none());
    tokio::fs::remove_dir_all(&tmp).await.unwrap_or(());
}

#[tokio::test]
async fn daemon_one_start_concurrency() {
    let tmp = TestRoot::track(
        std::env::temp_dir().join(format!("daemon-test-conc-{}", uuid::Uuid::new_v4())),
    );
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let run_file = tmp.join("running.json");
    let data_dir = tmp.join("data");
    tokio::fs::create_dir_all(&data_dir).await.unwrap();
    let count_file = tmp.join("spawn_count");
    tokio::fs::write(&count_file, b"").await.unwrap();
    let fake_bin = tmp.join("fake-daemon.sh");
    let script = format!(
        "#!/bin/sh\necho 1 >> \"{}\"\nprintf '{{\"pid\":%s,\"port\":43208,\"startedAt\":\"2099-01-01T00:00:00Z\"}}\\n' \"$$\" > '{}'\nsleep 30\n",
        count_file.display(),
        run_file.display(),
    );
    tokio::fs::write(&fake_bin, script).await.unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perm = std::fs::metadata(&fake_bin).unwrap().permissions();
        perm.set_mode(0o755);
        std::fs::set_permissions(&fake_bin, perm).unwrap();
    }
    let launch = crate::daemon::discovery::DaemonLaunchSpec {
        command: fake_bin.to_string_lossy().to_string(),
        args: vec![],
        cwd: tmp.clone(),
        shell: false,
        source: "bundled".to_string(),
    };
    let config = DaemonConfig {
        run_file: run_file.clone(),
        data_dir: data_dir.clone(),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: format!("apprun-{}", uuid::Uuid::new_v4()),
        launch_spec: Some(launch),
    };
    let manager = Arc::new(test_manager_with_timeout(config, Duration::from_secs(5)));
    let m1 = manager.clone();
    let m2 = manager.clone();
    let h1 = tokio::spawn(async move { m1.start().await });
    let h2 = tokio::spawn(async move { m2.start().await });
    let (r1, r2) = tokio::join!(h1, h2);
    let s1 = r1.unwrap();
    let s2 = r2.unwrap();
    assert!(s1.state == "ready" || s2.state == "ready");
    assert!(s1.state == "ready" || s1.state == "starting");
    assert!(s2.state == "ready" || s2.state == "starting");
    let count = tokio::fs::read_to_string(&count_file)
        .await
        .unwrap_or_default();
    assert_eq!(count.lines().count(), 1);
    let _ = manager.stop().await;
    tokio::fs::remove_dir_all(&tmp).await.unwrap_or(());
}

#[tokio::test]
async fn daemon_readiness_timeout() {
    let tmp = TestRoot::track(
        std::env::temp_dir().join(format!("daemon-test-timeout-{}", uuid::Uuid::new_v4())),
    );
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let run_file = tmp.join("running.json");
    let data_dir = tmp.join("data");
    tokio::fs::create_dir_all(&data_dir).await.unwrap();
    let fake_bin = tmp.join("sleep.sh");
    tokio::fs::write(&fake_bin, "#!/bin/sh\nsleep 5\n")
        .await
        .unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perm = std::fs::metadata(&fake_bin).unwrap().permissions();
        perm.set_mode(0o755);
        std::fs::set_permissions(&fake_bin, perm).unwrap();
    }
    let launch = crate::daemon::discovery::DaemonLaunchSpec {
        command: fake_bin.to_string_lossy().to_string(),
        args: vec![],
        cwd: tmp.clone(),
        shell: false,
        source: "bundled".to_string(),
    };
    let config = DaemonConfig {
        run_file: run_file.clone(),
        data_dir: data_dir.clone(),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: format!("apprun-{}", uuid::Uuid::new_v4()),
        launch_spec: Some(launch),
    };
    let manager = test_manager_with_timeout(config, Duration::from_millis(600));
    let status = manager.start().await;
    assert_eq!(status.state, "error");
    assert_eq!(status.code, Some("not_ready".to_string()));
    let _ = manager.stop().await;
    tokio::fs::remove_dir_all(&tmp).await.unwrap_or(());
}

#[tokio::test]
async fn daemon_captured_error_output() {
    let tmp = TestRoot::track(
        std::env::temp_dir().join(format!("daemon-test-err-{}", uuid::Uuid::new_v4())),
    );
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let run_file = tmp.join("running.json");
    let data_dir = tmp.join("data");
    tokio::fs::create_dir_all(&data_dir).await.unwrap();
    let fake_bin = tmp.join("fail.sh");
    tokio::fs::write(
        &fake_bin,
        "#!/bin/sh\necho 'daemon failed to bind' >&2\nexit 1\n",
    )
    .await
    .unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perm = std::fs::metadata(&fake_bin).unwrap().permissions();
        perm.set_mode(0o755);
        std::fs::set_permissions(&fake_bin, perm).unwrap();
    }
    let launch = crate::daemon::discovery::DaemonLaunchSpec {
        command: fake_bin.to_string_lossy().to_string(),
        args: vec![],
        cwd: tmp.clone(),
        shell: false,
        source: "bundled".to_string(),
    };
    let config = DaemonConfig {
        run_file: run_file.clone(),
        data_dir: data_dir.clone(),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: format!("apprun-{}", uuid::Uuid::new_v4()),
        launch_spec: Some(launch),
    };
    let manager = test_manager_with_timeout(config, Duration::from_millis(4000));
    let status = manager.start().await;
    assert_eq!(status.state, "error");
    assert!(
        status.code == Some("not_ready".to_string()) || status.code == Some("exited".to_string())
    );
    let details = status.details.unwrap_or_default();
    assert!(details.contains("daemon failed") || details.contains("No startup output"));
    tokio::time::sleep(Duration::from_millis(200)).await;
    let details2 = manager.status().await.details.unwrap_or_default();
    assert!(
        details2.contains("daemon failed")
            || details.contains("daemon failed")
            || details.contains("No startup output")
    );
    let _ = manager.stop().await;
    tokio::fs::remove_dir_all(&tmp).await.unwrap_or(());
}

#[tokio::test]
async fn exited_child_is_reaped_and_a_later_start_can_spawn_again() {
    let tmp = TestRoot::track(std::env::temp_dir().join(format!(
        "daemon-test-reap-{}",
        uuid::Uuid::new_v4().simple()
    )));
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let count_file = tmp.join("count");
    let fake_bin = tmp.join("exit.sh");
    tokio::fs::write(
        &fake_bin,
        format!("#!/bin/sh\necho 1 >> '{}'\nexit 9\n", count_file.display()),
    )
    .await
    .unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = std::fs::metadata(&fake_bin).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&fake_bin, permissions).unwrap();
    }
    let config = DaemonConfig {
        run_file: tmp.join("running.json"),
        data_dir: tmp.join("data"),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: "apprun-reap".to_string(),
        launch_spec: Some(crate::daemon::discovery::DaemonLaunchSpec {
            command: fake_bin.to_string_lossy().to_string(),
            args: vec![],
            cwd: tmp.clone(),
            shell: false,
            source: "bundled".to_string(),
        }),
    };
    let manager = test_manager_with_timeout(config, Duration::from_secs(5));

    assert_eq!(manager.start().await.code.as_deref(), Some("exited"));
    assert_eq!(manager.start().await.code.as_deref(), Some("exited"));
    let count = tokio::fs::read_to_string(&count_file).await.unwrap();
    assert_eq!(count.lines().count(), 2);
    tokio::fs::remove_dir_all(&tmp).await.unwrap();
}

#[cfg(unix)]
#[tokio::test]
async fn spawned_daemon_does_not_claim_a_fresh_runfile_from_another_process() {
    let tmp = TestRoot::track(std::env::temp_dir().join(format!(
        "daemon-test-foreign-runfile-{}",
        uuid::Uuid::new_v4().simple()
    )));
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let fake_bin = tmp.join("wait.sh");
    tokio::fs::write(&fake_bin, b"#!/bin/sh\nsleep 30\n")
        .await
        .unwrap();
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = std::fs::metadata(&fake_bin).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&fake_bin, permissions).unwrap();
    }
    let run_file = tmp.join("running.json");
    let run_info = serde_json::json!({
        "pid": std::process::id(),
        "port": 43209,
        "startedAt": "2099-01-01T00:00:00Z",
        "owner": "app"
    });
    tokio::fs::write(&run_file, serde_json::to_vec(&run_info).unwrap())
        .await
        .unwrap();
    let config = DaemonConfig {
        run_file,
        data_dir: tmp.join("data"),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: "apprun-foreign-runfile".to_string(),
        launch_spec: Some(crate::daemon::discovery::DaemonLaunchSpec {
            command: fake_bin.to_string_lossy().to_string(),
            args: vec![],
            cwd: tmp.clone(),
            shell: false,
            source: "bundled".to_string(),
        }),
    };
    let manager = test_manager_with_timeout(config, Duration::from_millis(250));

    let status = manager.start().await;
    manager.stop().await;
    tokio::fs::remove_dir_all(&tmp).await.unwrap();

    assert_eq!(status.code.as_deref(), Some("not_ready"));
}

#[tokio::test]
async fn ready_child_exit_is_observed_and_published() {
    let tmp = TestRoot::track(std::env::temp_dir().join(format!(
        "daemon-test-post-ready-exit-{}",
        uuid::Uuid::new_v4().simple()
    )));
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let fake_bin = tmp.join("listen-then-exit.sh");
    let exit_file = tmp.join("exit-now");
    let run_file = tmp.join("running.json");
    tokio::fs::write(
        &fake_bin,
        format!(
            "#!/bin/sh\nprintf '{{\"pid\":%s,\"port\":43210,\"startedAt\":\"2099-01-01T00:00:00Z\"}}\\n' \"$$\" > '{}'\necho 'time=x level=INFO msg=\"daemon listening\" addr=127.0.0.1:43210'\nwhile [ ! -f '{}' ]; do sleep 0.05; done\nexit 4\n",
            run_file.display(),
            exit_file.display(),
        ),
    )
    .await
    .unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = std::fs::metadata(&fake_bin).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&fake_bin, permissions).unwrap();
    }
    let config = DaemonConfig {
        run_file,
        data_dir: tmp.join("data"),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: "apprun-post-ready-exit".to_string(),
        launch_spec: Some(crate::daemon::discovery::DaemonLaunchSpec {
            command: fake_bin.to_string_lossy().to_string(),
            args: vec![],
            cwd: tmp.clone(),
            shell: false,
            source: "bundled".to_string(),
        }),
    };
    let manager = test_manager_with_timeout(config, Duration::from_secs(5));
    let mut events = manager.subscribe();

    assert_eq!(manager.start().await.state, "ready");
    tokio::fs::write(&exit_file, b"exit").await.unwrap();
    let exit_event = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let event = events.recv().await.unwrap();
            if event.code.as_deref() == Some("exited") {
                return event;
            }
        }
    })
    .await
    .unwrap();
    let status = manager.status().await;

    assert_eq!(status.state, "error");
    assert_eq!(status.code.as_deref(), Some("exited"));
    assert_eq!(exit_event.exit_code, Some(4));
    tokio::fs::remove_dir_all(&tmp).await.unwrap();
}

#[cfg(unix)]
#[tokio::test]
async fn shutdown_hook_terminates_the_owned_process_group() {
    let tmp = TestRoot::track(std::env::temp_dir().join(format!(
        "daemon-test-process-group-{}",
        uuid::Uuid::new_v4().simple()
    )));
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let grandchild_file = tmp.join("grandchild-pid");
    let fake_bin = tmp.join("process-tree.sh");
    let run_file = tmp.join("running.json");
    tokio::fs::write(
        &fake_bin,
        format!(
            "#!/bin/sh\nsleep 30 &\necho $! > '{}'\nprintf '{{\"pid\":%s,\"port\":43211,\"startedAt\":\"2099-01-01T00:00:00Z\"}}\\n' \"$$\" > '{}'\necho 'msg=\"daemon listening\" addr=127.0.0.1:43211'\nwait\n",
            grandchild_file.display(),
            run_file.display(),
        ),
    )
    .await
    .unwrap();
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = std::fs::metadata(&fake_bin).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&fake_bin, permissions).unwrap();
    }
    let config = DaemonConfig {
        run_file,
        data_dir: tmp.join("data"),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: "apprun-process-group".to_string(),
        launch_spec: Some(crate::daemon::discovery::DaemonLaunchSpec {
            command: fake_bin.to_string_lossy().to_string(),
            args: vec![],
            cwd: tmp.clone(),
            shell: false,
            source: "bundled".to_string(),
        }),
    };
    let manager = test_manager_with_timeout(config, Duration::from_secs(5));
    assert_eq!(manager.start().await.state, "ready");
    let grandchild_pid: u32 = tokio::fs::read_to_string(&grandchild_file)
        .await
        .unwrap()
        .trim()
        .parse()
        .unwrap();

    manager.request_shutdown();
    let mut alive = true;
    for _ in 0..100 {
        alive = crate::daemon::discovery::process_alive(grandchild_pid);
        if !alive {
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    if alive {
        unsafe {
            libc::kill(grandchild_pid as i32, libc::SIGKILL);
        }
    }
    assert!(!alive);
    manager.stop().await;
    tokio::fs::remove_dir_all(&tmp).await.unwrap();
}

#[cfg(unix)]
#[tokio::test]
async fn dropping_the_last_manager_terminates_its_owned_process() {
    let tmp = TestRoot::track(std::env::temp_dir().join(format!(
        "daemon-test-drop-owner-{}",
        uuid::Uuid::new_v4().simple()
    )));
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let run_file = tmp.join("running.json");
    let fake_bin = tmp.join("owned.sh");
    tokio::fs::write(
        &fake_bin,
        format!(
            "#!/bin/sh\nprintf '{{\"pid\":%s,\"port\":43212,\"startedAt\":\"2099-01-01T00:00:00Z\"}}\\n' \"$$\" > '{}'\nsleep 30\n",
            run_file.display(),
        ),
    )
    .await
    .unwrap();
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = std::fs::metadata(&fake_bin).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&fake_bin, permissions).unwrap();
    }
    let config = DaemonConfig {
        run_file,
        data_dir: tmp.join("data"),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: "apprun-drop-owner".to_string(),
        launch_spec: Some(crate::daemon::discovery::DaemonLaunchSpec {
            command: fake_bin.to_string_lossy().to_string(),
            args: vec![],
            cwd: tmp.clone(),
            shell: false,
            source: "bundled".to_string(),
        }),
    };
    let manager = test_manager_with_timeout(config, Duration::from_secs(5));
    let status = manager.start().await;
    let pid = status.pid.unwrap();

    drop(manager);
    let mut alive = true;
    for _ in 0..40 {
        alive = crate::daemon::discovery::process_alive(pid);
        if !alive {
            break;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    if alive {
        unsafe {
            libc::kill(-(pid as i32), libc::SIGKILL);
        }
    }

    assert!(!alive);
}

#[tokio::test]
async fn daemon_keep_daemon_env_disables_supervisor() {
    let env = env_from(&[("OPERATOR_KEEP_DAEMON", "1")]);
    assert!(keep_daemon_alive(&env));
    assert!(!keep_daemon_alive(&env_from(&[(
        "OPERATOR_KEEP_DAEMON",
        "0"
    )])));
    assert!(!should_link_on_attach(Some("persistent")));
    assert!(should_link_on_attach(Some("app")));
    let tmp = TestRoot::track(
        std::env::temp_dir().join(format!("daemon-test-keep-{}", uuid::Uuid::new_v4())),
    );
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let run_file = tmp.join("running.json");
    let data_dir = tmp.join("data");
    tokio::fs::create_dir_all(&data_dir).await.unwrap();
    let daemon_dir = tmp.join("daemon");
    tokio::fs::create_dir_all(&daemon_dir).await.unwrap();
    let daemon_bin = daemon_dir.join("opr");
    tokio::fs::write(&daemon_bin, b"").await.unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let pid = std::process::id();
    let started = chrono::Utc::now().to_rfc3339();
    let run_info = serde_json::json!({"pid": pid, "port": port, "startedAt": started, "owner":"persistent", "appRunId":"apprun-keep"});
    tokio::fs::write(&run_file, serde_json::to_string(&run_info).unwrap())
        .await
        .unwrap();
    let daemon_bin_clone = daemon_bin.clone();
    let server = tokio::spawn(async move {
        loop {
            let (mut socket, _) = listener.accept().await.unwrap();
            let bin_path = daemon_bin_clone.clone();
            tokio::spawn(async move {
                let mut buf = [0u8; 2048];
                let n = socket.read(&mut buf).await.unwrap_or(0);
                let req = String::from_utf8_lossy(&buf[..n]);
                let bin_str = bin_path.to_string_lossy().to_string();
                let body = if req.contains("GET /healthz") {
                    format!(
                        r#"{{"status":"ok","service":"operator-daemon","pid":{},"executablePath":"{}"}}"#,
                        pid, bin_str
                    )
                } else {
                    format!(
                        r#"{{"status":"ready","service":"operator-daemon","pid":{},"executablePath":"{}"}}"#,
                        pid, bin_str
                    )
                };
                let resp = format!(
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{}",
                    body.len(),
                    body
                );
                let _ = socket.write_all(resp.as_bytes()).await;
            });
        }
    });
    let config = DaemonConfig {
        run_file: run_file.clone(),
        data_dir: data_dir.clone(),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: "apprun-keep".to_string(),
        launch_spec: None,
    };
    let manager = test_manager(config);
    let status = manager.status().await;
    assert_eq!(status.state, "ready");
    assert!(!manager.supervisor_connected());
    assert_eq!(manager.stop().await.state, "stopped");
    assert_eq!(manager.status().await.state, "stopped");
    server.abort();
    tokio::fs::remove_dir_all(&tmp).await.unwrap_or(());
}

#[tokio::test]
#[cfg(unix)]
async fn daemon_supervisor_reconnection_after_restart() {
    let tmp = TestRoot::track(PathBuf::from("/tmp").join(format!(
        "daemon-test-super-{}",
        uuid::Uuid::new_v4().simple()
    )));
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let sock_path = tmp.join("supervise.sock");
    let listener = UnixListener::bind(&sock_path).unwrap();
    let server_handle = tokio::spawn(async move {
        loop {
            let Ok((mut socket, _)) = listener.accept().await else {
                break;
            };
            tokio::spawn(async move {
                let mut buf = [0u8; 32];
                loop {
                    match socket.read(&mut buf).await {
                        Ok(0) => break,
                        Ok(_) => continue,
                        Err(_) => break,
                    }
                }
            });
        }
    });
    let link = crate::daemon::supervisor::SupervisorLink::new(sock_path.clone());
    for _ in 0..20 {
        if link.connected() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert!(link.connected());
    server_handle.abort();
    tokio::fs::remove_file(&sock_path).await.unwrap_or(());
    tokio::time::sleep(Duration::from_millis(500)).await;
    let listener2 = UnixListener::bind(&sock_path).unwrap();
    let _server2 = tokio::spawn(async move {
        loop {
            let Ok((mut socket, _)) = listener2.accept().await else {
                break;
            };
            tokio::spawn(async move {
                let mut buf = [0u8; 32];
                loop {
                    match socket.read(&mut buf).await {
                        Ok(0) => break,
                        Ok(_) => continue,
                        Err(_) => break,
                    }
                }
            });
        }
    });
    for _ in 0..20 {
        if link.connected() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert!(link.connected());
    link.dispose();
    server_handle.abort();
    tokio::fs::remove_dir_all(&tmp).await.unwrap_or(());
}

#[tokio::test]
async fn daemon_close_behavior() {
    let tmp = TestRoot::track(
        std::env::temp_dir().join(format!("daemon-test-close-{}", uuid::Uuid::new_v4())),
    );
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let run_file = tmp.join("running.json");
    let data_dir = tmp.join("data");
    tokio::fs::create_dir_all(&data_dir).await.unwrap();
    let fake_bin = tmp.join("sleep2.sh");
    tokio::fs::write(&fake_bin, "#!/bin/sh\nsleep 10\n")
        .await
        .unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perm = std::fs::metadata(&fake_bin).unwrap().permissions();
        perm.set_mode(0o755);
        std::fs::set_permissions(&fake_bin, perm).unwrap();
    }
    let launch = crate::daemon::discovery::DaemonLaunchSpec {
        command: fake_bin.to_string_lossy().to_string(),
        args: vec![],
        cwd: tmp.clone(),
        shell: false,
        source: "bundled".to_string(),
    };
    let config = DaemonConfig {
        run_file: run_file.clone(),
        data_dir: data_dir.clone(),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: format!("apprun-{}", uuid::Uuid::new_v4()),
        launch_spec: Some(launch),
    };
    let manager = test_manager_with_timeout(config, Duration::from_millis(800));
    let _ = manager.start().await;
    let status = manager.stop().await;
    assert_eq!(status.state, "stopped");
    let status2 = manager.status().await;
    assert_eq!(status2.state, "stopped");
    tokio::fs::remove_dir_all(&tmp).await.unwrap_or(());
}

#[tokio::test]
async fn stop_cancels_an_inflight_start_without_a_late_error() {
    let tmp = TestRoot::track(std::env::temp_dir().join(format!(
        "daemon-test-cancel-{}",
        uuid::Uuid::new_v4().simple()
    )));
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let fake_bin = tmp.join("wait.sh");
    tokio::fs::write(&fake_bin, "#!/bin/sh\nsleep 10\n")
        .await
        .unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = std::fs::metadata(&fake_bin).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&fake_bin, permissions).unwrap();
    }
    let config = DaemonConfig {
        run_file: tmp.join("running.json"),
        data_dir: tmp.join("data"),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: "apprun-cancel".to_string(),
        launch_spec: Some(crate::daemon::discovery::DaemonLaunchSpec {
            command: fake_bin.to_string_lossy().to_string(),
            args: vec![],
            cwd: tmp.clone(),
            shell: false,
            source: "bundled".to_string(),
        }),
    };
    let manager = Arc::new(test_manager_with_timeout(
        config,
        Duration::from_millis(500),
    ));
    let starter = {
        let manager = manager.clone();
        tokio::spawn(async move { manager.start().await })
    };
    tokio::time::sleep(Duration::from_millis(100)).await;

    assert_eq!(manager.stop().await.state, "stopped");
    assert_eq!(starter.await.unwrap().state, "stopped");
    assert_eq!(manager.status().await.state, "stopped");
    tokio::fs::remove_dir_all(&tmp).await.unwrap();
}

#[cfg(unix)]
#[tokio::test]
async fn shutdown_cancels_an_inflight_start_as_stopped() {
    let tmp = TestRoot::track(std::env::temp_dir().join(format!(
        "daemon-test-shutdown-start-{}",
        uuid::Uuid::new_v4().simple()
    )));
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let pid_file = tmp.join("pid");
    let fake_bin = tmp.join("wait.sh");
    tokio::fs::write(
        &fake_bin,
        format!("#!/bin/sh\necho $$ > '{}'\nsleep 30\n", pid_file.display()),
    )
    .await
    .unwrap();
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = std::fs::metadata(&fake_bin).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&fake_bin, permissions).unwrap();
    }
    let config = DaemonConfig {
        run_file: tmp.join("running.json"),
        data_dir: tmp.join("data"),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: "apprun-shutdown-start".to_string(),
        launch_spec: Some(crate::daemon::discovery::DaemonLaunchSpec {
            command: fake_bin.to_string_lossy().to_string(),
            args: vec![],
            cwd: tmp.clone(),
            shell: false,
            source: "bundled".to_string(),
        }),
    };
    let manager = test_manager_with_timeout(config, Duration::from_secs(5));
    let starter = {
        let manager = manager.clone();
        tokio::spawn(async move { manager.start().await })
    };
    for _ in 0..100 {
        if pid_file.exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }

    manager.request_shutdown();
    let result = tokio::time::timeout(Duration::from_secs(2), starter).await;
    manager.stop().await;
    tokio::fs::remove_dir_all(&tmp).await.unwrap();

    let status = result.expect("start did not cancel").unwrap();
    assert_eq!(status.state, "stopped");
    assert!(status.code.is_none());
}

#[tokio::test]
async fn daemon_missing_resource_error() {
    let tmp = TestRoot::track(
        std::env::temp_dir().join(format!("missing-test-{}", uuid::Uuid::new_v4().simple())),
    );
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let launch = crate::daemon::discovery::DaemonLaunchSpec {
        command: "/nonexistent/path/opr".to_string(),
        args: vec!["daemon".to_string()],
        cwd: tmp.clone(),
        shell: false,
        source: "bundled".to_string(),
    };
    assert_eq!(bundled_daemon_binary_name("darwin"), "opr");
    assert_eq!(bundled_daemon_binary_name("win32"), "opr.exe");
    let config = DaemonConfig {
        run_file: tmp.join("running.json"),
        data_dir: tmp.join("data"),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: format!("apprun-{}", uuid::Uuid::new_v4()),
        launch_spec: Some(launch),
    };
    let manager = test_manager(config);
    let status = manager.start().await;
    assert_eq!(status.state, "error");
    assert_eq!(status.code, Some("binary_missing".to_string()));
    assert!(status
        .message
        .unwrap_or_default()
        .contains("/nonexistent/path/opr"));
    tokio::fs::remove_dir_all(&tmp).await.unwrap_or(());
}

#[tokio::test]
async fn daemon_status_transitions_are_published() {
    let tmp = TestRoot::track(std::env::temp_dir().join(format!(
        "daemon-test-events-{}",
        uuid::Uuid::new_v4().simple()
    )));
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let launch = crate::daemon::discovery::DaemonLaunchSpec {
        command: tmp.join("missing-opr").to_string_lossy().to_string(),
        args: vec!["daemon".to_string()],
        cwd: tmp.clone(),
        shell: false,
        source: "bundled".to_string(),
    };
    let config = DaemonConfig {
        run_file: tmp.join("running.json"),
        data_dir: tmp.join("data"),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged: true,
        app_run_id: "apprun-events".to_string(),
        launch_spec: Some(launch),
    };
    let manager = test_manager(config);
    let mut events = manager.subscribe();

    let result = manager.start().await;

    assert_eq!(result.state, "error");
    assert_eq!(events.recv().await.unwrap().state, "starting");
    assert_eq!(events.recv().await.unwrap().state, "error");
    tokio::fs::remove_dir_all(&tmp).await.unwrap();
}

#[test]
fn daemon_env_passes_required_keys() {
    let config = DaemonConfig {
        run_file: PathBuf::from("/tmp/.operator/running.json"),
        data_dir: PathBuf::from("/tmp/.operator/data"),
        acp_runtime_dir: PathBuf::from("/tmp/acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: PathBuf::from("/resources"),
        home_dir: PathBuf::from("/tmp"),
        is_packaged: true,
        app_run_id: "apprun-123".to_string(),
        launch_spec: None,
    };
    assert_eq!(config.app_run_id, "apprun-123");
    assert_eq!(config.app_version, "0.10.3");
}

#[tokio::test]
async fn daemon_env_uses_original_process_home_without_fake_stdin_token() {
    let config = DaemonConfig {
        run_file: PathBuf::from("/original-home/.operator/running.json"),
        data_dir: PathBuf::from("/original-home/.operator/data"),
        acp_runtime_dir: PathBuf::from("/resources/acp-runtime"),
        app_version: "1.2.3".to_string(),
        resources_dir: PathBuf::from("/resources"),
        home_dir: PathBuf::from("/original-home"),
        is_packaged: true,
        app_run_id: "apprun-env".to_string(),
        launch_spec: None,
    };
    let launch = resolve_daemon_launch(
        &HashMap::new(),
        true,
        Path::new("/resources"),
        Path::new("/application"),
        Path::new("/original-home"),
        "darwin",
    )
    .unwrap();
    let process_env = env_from(&[
        ("HOME", "/original-home"),
        ("PATH", "/usr/bin:/bin"),
        ("OPERATOR_BROWSER_RUNTIME_TOKEN", "secret"),
        ("OPERATOR_BROWSER_RUNTIME_TOKEN_STDIN", "1"),
    ]);
    let manager = DaemonManager::with_runtime(
        config,
        process_env,
        PathBuf::from("/application"),
        Duration::from_secs(1),
    );

    let child_env = manager.daemon_environment(&launch).await;

    assert_eq!(
        child_env.get("HOME").map(String::as_str),
        Some("/original-home")
    );
    assert_eq!(
        child_env
            .get("OPERATOR_AGENT_BROWSER_PATH")
            .map(PathBuf::from),
        Some(PathBuf::from("/resources").join("agent-browser").join(
            crate::daemon::discovery::bundled_agent_browser_binary_name(
                crate::daemon::runtime_platform(),
            ),
        ))
    );
    assert!(!child_env.contains_key("OPERATOR_BROWSER_RUNTIME_TOKEN"));
    assert!(!child_env.contains_key("OPERATOR_BROWSER_RUNTIME_TOKEN_STDIN"));
}

#[test]
fn daemon_with_fallback_path() {
    let p = with_fallback_path(Some("/usr/bin:/bin"));
    assert!(p.contains("/opt/homebrew/bin"));
    assert!(p.contains("/usr/bin"));
}

#[test]
fn daemon_windows_path_keeps_semicolon_entries_without_unix_directories() {
    let path = with_fallback_path_for(
        Some(r"C:\Windows\System32;C:\Program Files\Git\cmd"),
        "win32",
    );

    assert_eq!(path, r"C:\Windows\System32;C:\Program Files\Git\cmd");
    assert!(!path.contains("/usr/bin"));
}

#[test]
fn daemon_configured_command_uses_the_native_platform_shell() {
    assert_eq!(
        configured_shell_invocation("win32", "opr daemon --flag"),
        (
            "cmd.exe".to_string(),
            vec![
                "/S".to_string(),
                "/C".to_string(),
                "opr daemon --flag".to_string()
            ]
        )
    );
    assert_eq!(
        configured_shell_invocation("linux", "opr daemon --flag"),
        (
            "sh".to_string(),
            vec!["-c".to_string(), "opr daemon --flag".to_string()]
        )
    );
}

#[test]
fn allowed_origins_override_stamps_only_unpackaged_shells_without_explicit_config() {
    let dev_origin = "http://127.0.0.1:5173".to_string();
    assert_eq!(
        allowed_origins_override(&HashMap::new(), false),
        Some(dev_origin.clone())
    );
    assert_eq!(allowed_origins_override(&HashMap::new(), true), None);
    assert_eq!(
        allowed_origins_override(
            &env_from(&[("OPERATOR_ALLOWED_ORIGINS", "http://localhost:9999")]),
            false
        ),
        None
    );
    assert_eq!(
        allowed_origins_override(&env_from(&[("OPERATOR_ALLOWED_ORIGINS", "")]), false),
        Some(dev_origin)
    );
}

#[tokio::test]
async fn daemon_environment_stamps_dev_origin_only_when_unpackaged() {
    let tmp = TestRoot::track(
        std::env::temp_dir().join(format!("daemon-test-origin-{}", uuid::Uuid::new_v4())),
    );
    tokio::fs::create_dir_all(&tmp).await.unwrap();
    let launch = crate::daemon::discovery::DaemonLaunchSpec {
        command: "opr".to_string(),
        args: vec![],
        cwd: tmp.clone(),
        shell: false,
        source: "dev".to_string(),
    };
    let config_for = |is_packaged: bool| DaemonConfig {
        run_file: tmp.join("running.json"),
        data_dir: tmp.join("data"),
        acp_runtime_dir: tmp.join("acp"),
        app_version: "0.10.3".to_string(),
        resources_dir: tmp.clone(),
        home_dir: tmp.clone(),
        is_packaged,
        app_run_id: format!("apprun-{}", uuid::Uuid::new_v4()),
        launch_spec: None,
    };

    let dev = test_manager(config_for(false));
    let env_map = dev.daemon_environment(&launch).await;
    assert_eq!(
        env_map.get("OPERATOR_ALLOWED_ORIGINS").map(String::as_str),
        Some("http://127.0.0.1:5173")
    );

    let packaged = test_manager(config_for(true));
    let env_map = packaged.daemon_environment(&launch).await;
    assert!(!env_map.contains_key("OPERATOR_ALLOWED_ORIGINS"));

    let home = tmp.to_string_lossy().to_string();
    let mut process_env = env_from(&[
        ("HOME", &home),
        ("PATH", "/usr/bin:/bin"),
        ("SHELL", "/usr/bin/false"),
    ]);
    process_env.insert(
        "OPERATOR_ALLOWED_ORIGINS".to_string(),
        "http://localhost:9999".to_string(),
    );
    let explicit = DaemonManager::with_runtime(
        config_for(false),
        process_env,
        std::env::current_dir().unwrap(),
        Duration::from_secs(30),
    );
    let env_map = explicit.daemon_environment(&launch).await;
    assert_eq!(
        env_map.get("OPERATOR_ALLOWED_ORIGINS").map(String::as_str),
        Some("http://localhost:9999")
    );
}
