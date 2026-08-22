use std::collections::HashMap;
use std::{env, error::Error, fs, io, path::Path, path::PathBuf};

use chrono::Utc;

pub mod app_state;
pub mod daemon;
pub mod relocation;
use daemon::supervisor::DaemonManager;
use daemon::DaemonStatus;

#[cfg(test)]
mod app_state_tests;

/// Launch-time action derived from the macOS relocation decision.
#[cfg(target_os = "macos")]
enum MacosLaunchAction {
    Continue,
    HandOff(PathBuf),
    MoveTo(PathBuf, PathBuf),
}

fn marker_state_dir(home: &Path) -> Option<PathBuf> {
    let process_env: HashMap<String, String> = env::vars().collect();
    daemon::discovery::resolve_run_file_path(&process_env, home, daemon::is_packaged())
        .and_then(|run_file| run_file.parent().map(Path::to_path_buf))
}

/// Write the ~/.operator/app-state.json launch marker so `opr start`'s
/// resolveApp() can find this bundle. The app is the sole writer and writes on
/// every launch; a failure must not block startup.
fn write_launch_marker(home: &Path, installed_via: Option<&str>) -> Result<(), Box<dyn Error>> {
    let Some(state_dir) = marker_state_dir(home) else {
        return Err(std::io::Error::other(
            "cannot resolve the Operator run-file path; skipping app-state marker",
        )
        .into());
    };
    let exec_path = env::current_exe()?;
    let bundle_path = app_state::resolve_bundle_path(&exec_path);
    app_state::write_marker(
        &state_dir,
        &bundle_path.to_string_lossy(),
        &daemon::app_version(),
        installed_via,
        Utc::now(),
    )?;
    Ok(())
}

/// Capture install provenance BEFORE relocation, decide the macOS relocation,
/// then refresh the marker so appPath records the final bundle path while the
/// sticky installSource survives (mirrors main.ts app.whenReady ordering).
fn launch_app_state_flow() {
    let home = daemon::home_dir();
    let argv: Vec<String> = env::args().collect();
    let installed_via = app_state::parse_installed_via(&argv);

    // moveToApplicationsFolder relaunches without forwarding --installed-via, and
    // code past a successful move never runs in this instance, so the source must
    // be persisted first or the sticky logic would lock in "unknown".
    if installed_via.as_deref().is_some_and(|via| !via.is_empty()) {
        if let Err(error) = write_launch_marker(&home, installed_via.as_deref()) {
            eprintln!("failed to write pre-relocation app-state marker: {error}");
        }
    }

    #[cfg(target_os = "macos")]
    if daemon::is_packaged() {
        if let Some(action) = macos_relocation_action() {
            match action {
                MacosLaunchAction::Continue => {}
                MacosLaunchAction::HandOff(installed) => {
                    eprintln!(
                        "newer install at {}; handing off and quitting",
                        installed.display()
                    );
                    let _ = open_macos_bundle(&installed);
                    std::process::exit(0);
                }
                MacosLaunchAction::MoveTo(running, installed) => {
                    if let Err(error) = perform_macos_move(&home, &running, &installed) {
                        eprintln!("relocation to Applications failed: {error}");
                    } else {
                        let _ = open_macos_bundle(&installed);
                        std::process::exit(0);
                    }
                }
            }
        }
    }

    if let Err(error) = write_launch_marker(&home, installed_via.as_deref()) {
        eprintln!("failed to write app-state marker: {error}");
    }
}

#[cfg(target_os = "macos")]
fn macos_relocation_action() -> Option<MacosLaunchAction> {
    let exec_path = env::current_exe().ok()?;
    let bundle = app_state::resolve_bundle_path(&exec_path);
    let (installed_present, installed_version) = relocation::inspect_installed_bundle(&bundle);
    let action = relocation::decide_relocation(relocation::RelocationInputs {
        in_applications_folder: relocation::is_in_applications_folder(&bundle, &daemon::home_dir()),
        installed_present,
        installed_version: installed_version.as_deref(),
        running_version: &daemon::app_version(),
    });
    Some(match action {
        relocation::RelocationAction::Stay => MacosLaunchAction::Continue,
        relocation::RelocationAction::Handoff => {
            MacosLaunchAction::HandOff(relocation::installed_bundle_path(&bundle))
        }
        relocation::RelocationAction::Relocate => {
            let installed = relocation::installed_bundle_path(&bundle);
            MacosLaunchAction::MoveTo(bundle, installed)
        }
    })
}

#[cfg(target_os = "macos")]
fn open_macos_bundle(path: &Path) -> bool {
    std::process::Command::new("open")
        .arg(path)
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

/// Replace a strictly-older /Applications bundle with the running one via ditto,
/// preserving the code signature. Like Electron's default
/// moveToApplicationsFolder conflict handling, the old bundle first moves to the
/// user's Trash under a uniquified name; when it cannot be trashed (all names
/// taken, cross-volume rename, no Trash) it stays in place and the move is
/// declined rather than deleting it. The decision layer guarantees `installed`
/// is either absent or strictly older before this runs.
#[cfg(target_os = "macos")]
fn perform_macos_move(home: &Path, running: &Path, installed: &Path) -> Result<(), Box<dyn Error>> {
    if installed.exists() {
        let Some(bundle_name) = installed.file_name().and_then(|name| name.to_str()) else {
            return Err(std::io::Error::other(format!(
                "cannot move unnameable install {} to the Trash; keeping it in place",
                installed.display()
            ))
            .into());
        };
        let destination =
            relocation::trashed_bundle_destination(home, bundle_name, |path| path.exists());
        match destination {
            Some(destination) => match fs::rename(installed, &destination) {
                Ok(()) => {}
                Err(error) if error.kind() == io::ErrorKind::CrossesDevices => {
                    return Err(std::io::Error::other(format!(
                        "old install {} sits on another volume than {}; keeping it in place",
                        installed.display(),
                        home.join(".Trash").display()
                    ))
                    .into());
                }
                Err(error) => return Err(error.into()),
            },
            None => {
                return Err(std::io::Error::other(format!(
                    "no free name in {} for {}; keeping it in place",
                    home.join(".Trash").display(),
                    installed.display()
                ))
                .into());
            }
        }
    }
    let status = std::process::Command::new("ditto")
        .arg(running)
        .arg(installed)
        .status()?;
    if !status.success() {
        return Err(std::io::Error::other(format!("ditto exited with {status}")).into());
    }
    Ok(())
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum StateProfile {
    Development,
    Production,
}

fn resolve_state_root(
    operator_data_dir: Option<&Path>,
    operator_run_file: Option<&Path>,
    home_dir: Option<&Path>,
    profile: StateProfile,
) -> Result<PathBuf, &'static str> {
    if let Some(override_path) = operator_data_dir.or(operator_run_file) {
        if !override_path.is_absolute() {
            return Err("Operator overrides must resolve to an absolute path");
        }
        return override_path
            .parent()
            .filter(|parent| parent.is_absolute())
            .map(|parent| parent.join("tauri"))
            .ok_or("Operator state root could not be resolved");
    }

    let operator_root = home_dir
        .filter(|home| home.is_absolute())
        .map(|home| home.join(".operator"))
        .ok_or("Operator state root could not be resolved")?;
    if profile == StateProfile::Development {
        Ok(operator_root.join("dev").join("tauri"))
    } else {
        Ok(operator_root.join("tauri"))
    }
}

fn absolute_environment_path(name: &str) -> Result<Option<PathBuf>, Box<dyn Error>> {
    match env::var_os(name)
        .filter(|path| !path.is_empty())
        .map(PathBuf::from)
    {
        Some(path) if path.is_absolute() => Ok(Some(path)),
        Some(path) => Ok(Some(env::current_dir()?.join(path))),
        None => Ok(None),
    }
}

fn state_environment(state_root: &Path) -> Vec<(&'static str, PathBuf)> {
    #[cfg(target_os = "macos")]
    {
        vec![
            ("CFFIXED_USER_HOME", state_root.to_path_buf()),
            ("HOME", state_root.to_path_buf()),
        ]
    }
    #[cfg(target_os = "linux")]
    {
        vec![
            ("HOME", state_root.to_path_buf()),
            ("XDG_CACHE_HOME", state_root.join("cache")),
            ("XDG_CONFIG_HOME", state_root.join("config")),
            ("XDG_DATA_HOME", state_root.join("data")),
        ]
    }
    #[cfg(target_os = "windows")]
    {
        vec![("WEBVIEW2_USER_DATA_FOLDER", state_root.join("webview"))]
    }
}

fn resolved_state_root() -> Result<PathBuf, Box<dyn Error>> {
    let operator_data_dir = absolute_environment_path("OPERATOR_DATA_DIR")?;
    let operator_run_file = absolute_environment_path("OPERATOR_RUN_FILE")?;
    #[cfg(not(target_os = "windows"))]
    let home_dir = env::var_os("HOME")
        .filter(|path| !path.is_empty())
        .map(PathBuf::from);
    #[cfg(target_os = "windows")]
    let home_dir = env::var_os("USERPROFILE")
        .filter(|path| !path.is_empty())
        .map(PathBuf::from);

    resolve_state_root(
        operator_data_dir.as_deref(),
        operator_run_file.as_deref(),
        home_dir.as_deref(),
        if cfg!(debug_assertions) {
            StateProfile::Development
        } else {
            StateProfile::Production
        },
    )
    .map_err(std::io::Error::other)
    .map_err(Into::into)
}

fn install_panic_reporter(state_root: &Path) {
    let panic_report = state_root.join("rust-panic-report");
    std::panic::set_hook(Box::new(move |_| {
        let exit_code = if fs::write(&panic_report, b"panic").is_ok() {
            101
        } else {
            70
        };
        std::process::exit(exit_code);
    }));
}

fn terminal_benchmark_context(raw: Option<&str>) -> Result<bool, &'static str> {
    match raw {
        None => Ok(false),
        Some("1") => Ok(true),
        Some(_) => Err("invalid OPERATOR_TAURI_TERMINAL_BENCHMARK"),
    }
}

fn native_runtime_identity(webview_version: Result<String, String>) -> Result<String, String> {
    let webview_version = webview_version?;
    Ok(format!(
        "{} {} / WebView {} / Tauri {}",
        env::consts::OS,
        env::consts::ARCH,
        webview_version,
        tauri::VERSION
    ))
}

#[tauri::command]
fn terminal_benchmark_runtime_identity() -> Result<String, String> {
    native_runtime_identity(tauri::webview_version().map_err(|error| error.to_string()))
}

#[tauri::command]
async fn daemon_status(manager: tauri::State<'_, DaemonManager>) -> Result<DaemonStatus, String> {
    Ok(manager.status().await)
}

#[tauri::command]
async fn daemon_start(manager: tauri::State<'_, DaemonManager>) -> Result<DaemonStatus, String> {
    Ok(manager.start().await)
}

#[tauri::command]
async fn daemon_stop(manager: tauri::State<'_, DaemonManager>) -> Result<DaemonStatus, String> {
    Ok(manager.stop().await)
}

#[tauri::command]
async fn daemon_restart(manager: tauri::State<'_, DaemonManager>) -> Result<DaemonStatus, String> {
    Ok(manager.restart().await)
}

#[tauri::command]
fn complete_state_audit(app: tauri::AppHandle) -> Result<(), String> {
    let mode = env::var("OPERATOR_TAURI_STATE_AUDIT_MODE").map_err(|error| error.to_string())?;
    let state_root = resolved_state_root().map_err(|error| error.to_string())?;
    fs::write(
        state_root.join(format!("renderer-{mode}-complete")),
        b"complete",
    )
    .map_err(|error| error.to_string())?;
    if mode == "crash" {
        panic!("Operator Tauri state audit crash");
    }
    app.exit(0);
    Ok(())
}

#[tauri::command]
fn fail_state_audit(app: tauri::AppHandle, failure: String) {
    eprintln!("{failure}");
    app.exit(70);
}

pub fn run() -> Result<(), Box<dyn Error>> {
    let state_root = resolved_state_root()?;
    fs::create_dir_all(&state_root)?;
    install_panic_reporter(&state_root);
    launch_app_state_flow();
    for (name, path) in state_environment(&state_root) {
        env::set_var(name, path);
    }

    let audit_mode = env::var("OPERATOR_TAURI_STATE_AUDIT_MODE").ok();
    if !matches!(
        audit_mode.as_deref(),
        None | Some("shutdown") | Some("crash")
    ) {
        return Err(std::io::Error::other("invalid OPERATOR_TAURI_STATE_AUDIT_MODE").into());
    }
    let terminal_benchmark = terminal_benchmark_context(
        env::var("OPERATOR_TAURI_TERMINAL_BENCHMARK")
            .ok()
            .as_deref(),
    )
    .map_err(std::io::Error::other)?;
    if terminal_benchmark && audit_mode.is_some() {
        return Err(std::io::Error::other("Tauri audit contexts are mutually exclusive").into());
    }
    let audit_script = audit_mode.as_ref().map(|_| {
        r##"
void (async () => {
  localStorage.setItem("operator-state-audit", "local");
  sessionStorage.setItem("operator-state-audit", "session");
  document.cookie = "operator_state_audit=cookie; SameSite=Strict";
  history.pushState({ audit: true }, "", "#operator-state-audit");
  const cache = await caches.open("operator-state-audit");
  await cache.put("https://tauri.localhost/operator-state-audit", new Response("cache"));
  await window.__TAURI_INTERNALS__.invoke("complete_state_audit");
})().catch((error) => window.__TAURI_INTERNALS__.invoke("fail_state_audit", {
  failure: String(error),
}));
"##
        .to_owned()
    });

    let daemon_manager = DaemonManager::new();
    let mut builder = tauri::Builder::default().manage(daemon_manager);
    if audit_mode.is_some() {
        builder = builder.invoke_handler(tauri::generate_handler![
            daemon_status,
            daemon_start,
            daemon_stop,
            daemon_restart,
            complete_state_audit,
            fail_state_audit
        ]);
    } else if terminal_benchmark {
        builder = builder.invoke_handler(tauri::generate_handler![
            daemon_status,
            daemon_start,
            daemon_stop,
            daemon_restart,
            terminal_benchmark_runtime_identity
        ]);
    } else {
        builder = builder.invoke_handler(tauri::generate_handler![
            daemon_status,
            daemon_start,
            daemon_stop,
            daemon_restart
        ]);
    }
    builder
        .setup(move |app| {
            let mut window = tauri::WebviewWindowBuilder::new(
                app,
                "main",
                tauri::WebviewUrl::App("index.html".into()),
            )
            .title("Operator")
            .inner_size(1280.0, 800.0)
            .data_directory(state_root.join("webview"))
            .use_https_scheme(false);
            if let Some(script) = audit_script.clone() {
                window = window.initialization_script(script);
            }
            window.build()?;
            Ok(())
        })
        .run(tauri::generate_context!())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::{env, fs, path::Path, path::PathBuf, process, process::Command};

    use super::install_panic_reporter;
    use super::native_runtime_identity;
    use super::resolve_state_root;
    use super::state_environment;
    use super::terminal_benchmark_context;
    use super::StateProfile;

    fn test_root() -> PathBuf {
        if cfg!(target_os = "windows") {
            PathBuf::from(r"C:\operator-test")
        } else {
            PathBuf::from("/operator-test")
        }
    }

    #[test]
    fn state_root_prefers_operator_data_dir() {
        let override_root = test_root().join("override");
        let ignored_root = test_root().join("ignored");
        let home_root = test_root().join("home");
        let root = resolve_state_root(
            Some(&override_root.join("data")),
            Some(&ignored_root.join("running.json")),
            Some(&home_root),
            StateProfile::Production,
        )
        .unwrap();

        assert_eq!(root, override_root.join("tauri"));
    }

    #[test]
    fn terminal_runtime_command_requires_exact_benchmark_context() {
        assert!(!terminal_benchmark_context(None).unwrap());
        assert!(terminal_benchmark_context(Some("1")).unwrap());
        assert_eq!(
            terminal_benchmark_context(Some("true")).unwrap_err(),
            "invalid OPERATOR_TAURI_TERMINAL_BENCHMARK"
        );
    }

    #[test]
    fn terminal_runtime_identity_fails_without_native_webview_version() {
        assert_eq!(
            native_runtime_identity(Err("unavailable".to_owned())).unwrap_err(),
            "unavailable"
        );
    }

    #[test]
    fn terminal_runtime_identity_contains_only_native_runtime_fields() {
        let identity = native_runtime_identity(Ok("WebKit 619.3".to_owned())).unwrap();

        assert!(identity.contains(std::env::consts::OS));
        assert!(identity.contains(std::env::consts::ARCH));
        assert!(identity.contains("WebKit 619.3"));
        assert!(identity.contains(tauri::VERSION));
        assert!(!identity.contains("http"));
        assert!(!identity.contains('@'));
    }

    #[test]
    fn state_root_uses_operator_run_file_without_data_override() {
        let override_root = test_root().join("override");
        let home_root = test_root().join("home");
        let root = resolve_state_root(
            None,
            Some(&override_root.join("running.json")),
            Some(&home_root),
            StateProfile::Production,
        )
        .unwrap();

        assert_eq!(root, override_root.join("tauri"));
    }

    #[test]
    fn state_root_separates_development_state() {
        let home_root = test_root().join("home");
        let root =
            resolve_state_root(None, None, Some(&home_root), StateProfile::Development).unwrap();

        assert_eq!(root, home_root.join(".operator").join("dev").join("tauri"));
    }

    #[test]
    fn state_root_fails_without_a_safe_base() {
        let error = resolve_state_root(None, None, None, StateProfile::Production).unwrap_err();

        assert_eq!(error, "Operator state root could not be resolved");
    }

    #[test]
    fn state_root_reparents_platform_state() {
        let root = Path::new("/tmp/operator/tauri");
        let environment = state_environment(root);

        #[cfg(target_os = "macos")]
        assert_eq!(
            environment,
            vec![
                ("CFFIXED_USER_HOME", root.to_path_buf()),
                ("HOME", root.to_path_buf()),
            ]
        );
        #[cfg(target_os = "linux")]
        assert_eq!(
            environment,
            vec![
                ("HOME", root.to_path_buf()),
                ("XDG_CACHE_HOME", root.join("cache")),
                ("XDG_CONFIG_HOME", root.join("config")),
                ("XDG_DATA_HOME", root.join("data")),
            ]
        );
        #[cfg(target_os = "windows")]
        assert_eq!(
            environment,
            vec![("WEBVIEW2_USER_DATA_FOLDER", root.join("webview"))]
        );
    }

    #[test]
    fn panic_reporter_writes_under_state_root() {
        if let Some(probe_root) = env::var_os("OPERATOR_TAURI_PANIC_PROBE_ROOT") {
            install_panic_reporter(Path::new(&probe_root));
            panic!("panic reporter probe");
        }

        let probe_root = env::temp_dir().join(format!("tauri-panic-test-{}", process::id()));
        fs::create_dir(&probe_root).unwrap();
        let status = Command::new(env::current_exe().unwrap())
            .args(["--exact", "tests::panic_reporter_writes_under_state_root"])
            .env("OPERATOR_TAURI_PANIC_PROBE_ROOT", &probe_root)
            .status()
            .unwrap();

        assert_eq!(status.code(), Some(101));
        assert_eq!(
            fs::read(probe_root.join("rust-panic-report")).unwrap(),
            b"panic"
        );
        fs::remove_dir_all(probe_root).unwrap();
    }
}
