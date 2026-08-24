use std::collections::HashMap;
use std::{env, error::Error, fs, io, path::Path, path::PathBuf};

use chrono::Utc;
use tauri::{Emitter, Manager};
use tauri_plugin_dialog::DialogExt;

pub mod app_state;
pub mod daemon;
pub mod dropped_files;
pub mod menu;
pub mod native;
pub mod notification_policy;
pub mod relocation;
pub mod shortcuts;
pub mod tray;
pub mod window;
use daemon::supervisor::DaemonManager;
use daemon::DaemonStatus;

#[cfg(test)]
mod app_state_tests;

#[cfg(test)]
mod dropped_files_tests;

#[cfg(test)]
mod native_contract_tests;

/// Launch-time action derived from the macOS relocation decision.
#[cfg(target_os = "macos")]
enum MacosLaunchAction {
    Continue,
    HandOff(PathBuf),
    MoveTo(PathBuf, PathBuf, relocation::RelocationLock),
}

fn marker_state_dir(
    process_env: &HashMap<String, String>,
    home: &Path,
    is_packaged: bool,
) -> Option<PathBuf> {
    daemon::discovery::resolve_run_file_path(process_env, home, is_packaged)
        .and_then(|run_file| run_file.parent().map(Path::to_path_buf))
}

/// Write the ~/.operator/app-state.json launch marker so `opr start`'s
/// resolveApp() can find this bundle. The app is the sole writer and writes on
/// every launch; a failure must not block startup.
fn write_launch_marker(
    process_env: &HashMap<String, String>,
    home: &Path,
    is_packaged: bool,
    app_version: &str,
    installed_via: Option<&str>,
) -> Result<(), Box<dyn Error>> {
    let Some(state_dir) = marker_state_dir(process_env, home, is_packaged) else {
        return Err(std::io::Error::other(
            "cannot resolve the Operator run-file path; skipping app-state marker",
        )
        .into());
    };
    let exec_path = env::current_exe()?;
    let bundle_path = if is_packaged {
        app_state::resolve_bundle_path(&exec_path).ok_or_else(|| {
            std::io::Error::other("packaged executable is not inside a valid app bundle")
        })?
    } else {
        exec_path
    };
    app_state::write_marker(
        &state_dir,
        &bundle_path.to_string_lossy(),
        app_version,
        installed_via,
        Utc::now(),
    )?;
    Ok(())
}

/// Capture install provenance BEFORE relocation, decide the macOS relocation,
/// then refresh the marker so appPath records the final bundle path while the
/// sticky installSource survives (mirrors main.ts app.whenReady ordering).
fn launch_app_state_flow(
    process_env: &HashMap<String, String>,
    home: &Path,
    is_packaged: bool,
    app_version: &str,
    #[cfg_attr(not(target_os = "macos"), allow(unused_variables))] state_root: &Path,
) {
    let argv: Vec<String> = env::args().collect();
    let installed_via = app_state::parse_installed_via(&argv);

    // moveToApplicationsFolder relaunches without forwarding --installed-via, and
    // code past a successful move never runs in this instance, so the source must
    // be persisted first or the sticky logic would lock in "unknown".
    if installed_via.as_deref().is_some_and(|via| !via.is_empty()) {
        if let Err(error) = write_launch_marker(
            process_env,
            home,
            is_packaged,
            app_version,
            installed_via.as_deref(),
        ) {
            eprintln!("failed to write pre-relocation app-state marker: {error}");
        }
    }

    #[cfg(target_os = "macos")]
    if is_packaged {
        if let Some(action) = macos_relocation_action(home, app_version, state_root) {
            match action {
                MacosLaunchAction::Continue => {}
                MacosLaunchAction::HandOff(installed) => {
                    eprintln!(
                        "newer install at {}; handing off and quitting",
                        installed.display()
                    );
                    if open_macos_bundle(&installed) {
                        std::process::exit(0);
                    }
                    eprintln!("failed to launch installed Operator bundle");
                }
                MacosLaunchAction::MoveTo(running, installed, lock) => {
                    match perform_macos_move(home, &running, &installed, app_version, &lock) {
                        Ok(true) => std::process::exit(0),
                        Ok(false) => eprintln!("relocated Operator but failed to relaunch it"),
                        Err(error) => eprintln!("relocation to Applications failed: {error}"),
                    }
                }
            }
        }
    }

    if let Err(error) = write_launch_marker(
        process_env,
        home,
        is_packaged,
        app_version,
        installed_via.as_deref(),
    ) {
        eprintln!("failed to write app-state marker: {error}");
    }
}

/// Decide the macOS launch action under the cross-process relocation lock so a
/// second instance racing this one can never interleave with the decision or
/// the move. A contended instance declines to Stay without side effects; an
/// unobtainable lock also falls back to Stay rather than blocking startup.
#[cfg(target_os = "macos")]
fn macos_relocation_action(
    home: &Path,
    app_version: &str,
    state_root: &Path,
) -> Option<MacosLaunchAction> {
    let lock = match relocation::RelocationLock::try_acquire(state_root) {
        Ok(Some(lock)) => lock,
        Ok(None) => return Some(MacosLaunchAction::Continue),
        Err(error) => {
            eprintln!("relocation lock unavailable; continuing in place: {error}");
            return Some(MacosLaunchAction::Continue);
        }
    };
    let exec_path = env::current_exe().ok()?;
    let bundle = app_state::resolve_bundle_path(&exec_path)?;
    let (installed_present, installed_version) = relocation::inspect_installed_bundle(&bundle);
    let action = relocation::decide_relocation(relocation::RelocationInputs {
        in_applications_folder: relocation::is_in_applications_folder(&bundle, home),
        installed_present,
        installed_version: installed_version.as_deref(),
        running_version: app_version,
    });
    Some(match action {
        relocation::RelocationAction::Stay => MacosLaunchAction::Continue,
        relocation::RelocationAction::Handoff => {
            MacosLaunchAction::HandOff(relocation::installed_bundle_path(&bundle))
        }
        relocation::RelocationAction::Relocate => {
            let installed = relocation::installed_bundle_path(&bundle);
            MacosLaunchAction::MoveTo(bundle, installed, lock)
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

#[cfg(target_os = "macos")]
fn open_new_macos_bundle_instance(path: &Path) -> bool {
    std::process::Command::new("open")
        .arg("-n")
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
/// is either absent or strictly older before this runs, and `lock` proves this
/// process owns the cross-process relocation window.
#[cfg(target_os = "macos")]
fn perform_macos_move(
    home: &Path,
    running: &Path,
    installed: &Path,
    app_version: &str,
    lock: &relocation::RelocationLock,
) -> Result<bool, Box<dyn Error>> {
    let mut executor = MacosRelocationExecutor;
    Ok(relocation::execute_relocation(
        &mut executor,
        home,
        running,
        installed,
        app_version,
        &uuid::Uuid::new_v4().simple().to_string(),
        lock,
    )?)
}

#[cfg(target_os = "macos")]
struct MacosRelocationExecutor;

#[cfg(target_os = "macos")]
impl relocation::RelocationExecutor for MacosRelocationExecutor {
    fn exists(&self, path: &Path) -> bool {
        path.exists()
    }

    fn move_path(&mut self, from: &Path, to: &Path) -> io::Result<()> {
        fs::rename(from, to)
    }

    fn copy_bundle(&mut self, from: &Path, to: &Path) -> io::Result<()> {
        let status = std::process::Command::new("ditto")
            .arg(from)
            .arg(to)
            .status()?;
        if status.success() {
            Ok(())
        } else {
            Err(io::Error::other(format!("ditto exited with {status}")))
        }
    }

    fn valid_bundle(&self, path: &Path, expected_version: &str) -> bool {
        relocation::valid_macos_bundle(path, expected_version)
    }

    fn remove_staged(&mut self, path: &Path) -> io::Result<()> {
        let name = path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("");
        if !name.starts_with('.')
            || !name.contains(".operator-stage-")
            || path.extension().is_none_or(|ext| ext != "app")
        {
            return Err(io::Error::other("refusing to remove a non-staging path"));
        }
        match fs::remove_dir_all(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
    }

    fn launch_bundle(&mut self, path: &Path) -> bool {
        open_new_macos_bundle_instance(path)
    }
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
        if tauri::is_dev() {
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

fn build_main_window(
    app: &tauri::AppHandle,
    state_root: &Path,
    audit_script: Option<String>,
) -> Result<tauri::WebviewWindow, tauri::Error> {
    let mut builder = tauri::WebviewWindowBuilder::new(
        app,
        shortcuts::MAIN_WINDOW_LABEL,
        tauri::WebviewUrl::App("index.html".into()),
    )
    .title("Operator")
    .inner_size(1320.0, 860.0)
    .min_inner_size(960.0, 640.0)
    .background_color(tauri::window::Color(0x0f, 0x10, 0x14, 255))
    .data_directory(state_root.join("webview"))
    .use_https_scheme(false)
    .on_page_load(|webview, payload| {
        if matches!(payload.event(), tauri::webview::PageLoadEvent::Started) {
            if let Some(shell) = webview.app_handle().try_state::<native::ShellState>() {
                native::reset_native_shell(&shell);
                let sessions = shell
                    .sessions
                    .lock()
                    .map(|guard| guard.clone())
                    .unwrap_or_default();
                let _ = tray::apply_state(webview.app_handle(), &sessions);
            }
        }
    });
    if let Some(script) = audit_script {
        builder = builder.initialization_script(script);
    }
    builder.build()
}

fn rebuild_main_window(app: &tauri::AppHandle) -> Result<(), Box<dyn Error>> {
    let state_root = app
        .try_state::<native::ShellState>()
        .map(|shell| shell.state_root.clone())
        .ok_or_else(|| std::io::Error::other("Operator shell state was not initialized"))?;
    build_main_window(app, &state_root, None)?;
    Ok(())
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

struct ShortcutRegistry(
    std::sync::Mutex<Option<shortcuts::ShortcutEngine<shortcuts::GlobalShortcutRegistrar>>>,
);

struct FullscreenState(std::sync::Mutex<window::FullscreenTracker>);

struct ThemeState(std::sync::Mutex<window::ThemePreference>);

fn install_app_menu(app: &tauri::AppHandle) -> Result<(), Box<dyn Error>> {
    let mut menu_builder = tauri::menu::MenuBuilder::new(app);
    for submenu_spec in menu::app_menu_template(native::menu_platform()) {
        let mut submenu = tauri::menu::SubmenuBuilder::new(app, submenu_spec.label);
        for item in submenu_spec.items {
            submenu = match item.kind {
                menu::MenuItemKind::Action => submenu.item(&tauri::menu::MenuItem::with_id(
                    app,
                    item.action.unwrap_or_default(),
                    item.label,
                    true,
                    Some(item.accelerator),
                )?),
                menu::MenuItemKind::Separator => submenu.separator(),
                menu::MenuItemKind::NativeAbout => {
                    submenu.item(&tauri::menu::PredefinedMenuItem::about(app, None, None)?)
                }
                menu::MenuItemKind::NativeQuit => {
                    submenu.item(&tauri::menu::PredefinedMenuItem::quit(app, None)?)
                }
            };
        }
        menu_builder = menu_builder.item(&submenu.build()?);
    }
    let menu = menu_builder.build()?;
    app.set_menu(menu)?;
    if cfg!(target_os = "windows") {
        app.hide_menu()?;
    }
    Ok(())
}

fn route_native_menu_event(app: &tauri::AppHandle, event: &tauri::menu::MenuEvent) {
    let Some(window) = app.get_webview_window(shortcuts::MAIN_WINDOW_LABEL) else {
        return;
    };
    let zoom = app.state::<menu::ZoomState>();
    let mut host = ShellMenuHost {
        app,
        window: &window,
    };
    menu::dispatch_menu_action(event.id().as_ref(), &zoom, &mut host);
}

static WINDOW_FOCUS_DESIRED: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(true);

fn log_apply_report(context: &str, report: &shortcuts::ApplyReport) {
    for conflict in &report.conflicts {
        eprintln!(
            "shortcut conflict ({context}): {} claimed by {} shadows {}",
            conflict.accelerator,
            conflict.winner.event_name(),
            conflict.shadowed.event_name()
        );
    }
    for failure in &report.failures {
        eprintln!(
            "shortcut registration failed ({}): {} for {}: {}",
            context,
            failure.error,
            failure.accelerator,
            failure.id.event_name()
        );
    }
}

fn mutate_shortcuts(
    registry: &ShortcutRegistry,
    mutate: impl FnOnce(
        &mut shortcuts::ShortcutEngine<shortcuts::GlobalShortcutRegistrar>,
    ) -> shortcuts::ApplyReport,
) -> Result<(), String> {
    let mut guard = registry
        .0
        .lock()
        .map_err(|_| "shortcut registry poisoned".to_string())?;
    match guard.as_mut() {
        Some(engine) => {
            log_apply_report("shortcuts", &mutate(engine));
            Ok(())
        }
        None => {
            eprintln!("global shortcuts unavailable on this platform; ignoring shortcut update");
            Ok(())
        }
    }
}

#[tauri::command]
async fn keybindings_apply(
    registry: tauri::State<'_, ShortcutRegistry>,
    overrides: HashMap<String, Vec<shortcuts::Binding>>,
) -> Result<(), String> {
    mutate_shortcuts(&registry, |engine| engine.set_overrides(overrides))
}

#[tauri::command]
async fn keybindings_recording(
    registry: tauri::State<'_, ShortcutRegistry>,
    active: bool,
) -> Result<(), String> {
    mutate_shortcuts(&registry, |engine| engine.set_recording(active))
}

#[tauri::command]
async fn set_close_shell_terminal_shortcut_enabled(
    registry: tauri::State<'_, ShortcutRegistry>,
    enabled: bool,
) -> Result<(), String> {
    mutate_shortcuts(&registry, |engine| {
        engine.set_close_terminal_enabled(enabled)
    })
}

fn set_window_focus_state(app: &tauri::AppHandle) {
    let desired = WINDOW_FOCUS_DESIRED.load(std::sync::atomic::Ordering::SeqCst);
    if let Some(registry) = app.try_state::<ShortcutRegistry>() {
        let _ = mutate_shortcuts(&registry, |engine| engine.set_window_focused(desired));
    }
}

fn request_window_focus_state(focused: bool) {
    WINDOW_FOCUS_DESIRED.store(focused, std::sync::atomic::Ordering::SeqCst);
}

fn push_fullscreen_state(app: &tauri::AppHandle, full_screen: bool) {
    let _ = app.emit_to(
        shortcuts::MAIN_WINDOW_LABEL,
        "window:fullscreen",
        full_screen,
    );
}

fn poll_fullscreen_state(app: &tauri::AppHandle) {
    let Some(window) = app.get_webview_window(shortcuts::MAIN_WINDOW_LABEL) else {
        return;
    };
    let current = window.is_fullscreen().unwrap_or(false);
    let Some(state) = app.try_state::<FullscreenState>() else {
        return;
    };
    let changed = state
        .0
        .lock()
        .ok()
        .and_then(|mut tracker| tracker.update(current));
    if let Some(full_screen) = changed {
        push_fullscreen_state(app, full_screen);
    }
}

#[tauri::command]
fn window_set_overlay(
    window: tauri::WebviewWindow,
    color: String,
    symbol_color: String,
) -> Result<(), String> {
    let colors = window::overlay_colors(&color, &symbol_color)
        .ok_or_else(|| format!("invalid title bar overlay colors: {color:?} / {symbol_color:?}"))?;
    set_title_bar_overlay_colors(&window, colors)
}

#[cfg(target_os = "windows")]
fn set_title_bar_overlay_colors(
    window: &tauri::WebviewWindow,
    colors: window::OverlayColors,
) -> Result<(), String> {
    let hwnd = window.hwnd().map_err(|error| error.to_string())?;
    let hwnd = windows_sys::Win32::Foundation::HWND(hwnd.0);
    for (attribute, value) in [
        (
            windows_sys::Win32::Graphics::Dwm::DWMWA_CAPTION_COLOR,
            colors.caption_colorref(),
        ),
        (
            windows_sys::Win32::Graphics::Dwm::DWMWA_TEXT_COLOR,
            colors.text_colorref(),
        ),
    ] {
        let result = unsafe {
            windows_sys::Win32::Graphics::Dwm::DwmSetWindowAttribute(
                hwnd,
                attribute as u32,
                std::ptr::from_ref(&value).cast(),
                4,
            )
        };
        if result < 0 {
            eprintln!("this Windows build does not support title bar overlay tinting ({result})");
            return Ok(());
        }
    }
    Ok(())
}

#[cfg(not(target_os = "windows"))]
fn set_title_bar_overlay_colors(
    _window: &tauri::WebviewWindow,
    _colors: window::OverlayColors,
) -> Result<(), String> {
    Ok(())
}

#[tauri::command]
fn window_is_fullscreen(window: tauri::WebviewWindow) -> Result<bool, String> {
    window.is_fullscreen().map_err(|error| error.to_string())
}

#[tauri::command]
fn theme_set(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    theme_state: tauri::State<'_, ThemeState>,
    preference: String,
) -> Result<(), String> {
    let Some(preference) = window::theme_preference(&preference) else {
        return Ok(());
    };
    if let Ok(mut current) = theme_state.0.lock() {
        *current = preference;
    }
    apply_theme_preference(&app, &window, preference);
    Ok(())
}

fn apply_theme_preference(
    app: &tauri::AppHandle,
    window: &tauri::WebviewWindow,
    preference: window::ThemePreference,
) {
    let theme = match preference {
        window::ThemePreference::Light => Some(tauri::Theme::Light),
        window::ThemePreference::Dark => Some(tauri::Theme::Dark),
        window::ThemePreference::System => None,
    };
    app.set_theme(theme);
    apply_window_background(window, preference);
}

fn apply_window_background(window: &tauri::WebviewWindow, preference: window::ThemePreference) {
    let os_dark = matches!(
        window.theme().unwrap_or(tauri::Theme::Dark),
        tauri::Theme::Dark
    );
    if let Some((red, green, blue)) = window::resolved_background(preference, os_dark) {
        let _ = window.set_background_color(Some(tauri::window::Color(red, green, blue, 255)));
    }
}

fn follow_system_theme(app: &tauri::AppHandle) {
    let Some(theme_state) = app.try_state::<ThemeState>() else {
        return;
    };
    let preference = match theme_state.0.lock() {
        Ok(current) => *current,
        Err(poisoned) => *poisoned.into_inner(),
    };
    if preference != window::ThemePreference::System {
        return;
    }
    if let Some(window) = app.get_webview_window(shortcuts::MAIN_WINDOW_LABEL) {
        apply_window_background(&window, preference);
    }
}

struct ShellMenuHost<'a> {
    app: &'a tauri::AppHandle,
    window: &'a tauri::WebviewWindow,
}

impl menu::MenuHost for ShellMenuHost<'_> {
    fn edit(&mut self, command: menu::EditCommand) {
        let _ = self.window.eval(command.exec_script());
    }

    fn reload(&mut self) {
        let _ = self.window.reload();
    }

    fn toggle_devtools(&mut self) {
        if self.window.is_devtools_open() {
            self.window.close_devtools();
        } else {
            self.window.open_devtools();
        }
    }

    fn zoom(&mut self, scale: f64) {
        let _ = self.window.set_zoom(scale);
    }

    fn toggle_fullscreen(&mut self) {
        let current = self.window.is_fullscreen().unwrap_or(false);
        if let Err(error) = self.window.set_fullscreen(!current) {
            eprintln!("failed to toggle fullscreen: {error}");
        }
        push_fullscreen_state(self.app, !current);
    }

    fn minimize(&mut self) {
        let _ = self.window.minimize();
    }

    fn toggle_maximize(&mut self) {
        if self.window.is_maximized().unwrap_or(false) {
            let _ = self.window.unmaximize();
        } else {
            let _ = self.window.maximize();
        }
    }

    fn close(&mut self) {
        let _ = self.window.close();
    }

    fn quit(&mut self) {
        self.app.exit(0);
    }

    fn show_shortcuts_help(&mut self) {
        push_shortcuts_help(self.app);
    }

    fn about(&mut self) {
        self.app
            .dialog()
            .message(format!(
                "Operator\nVersion {}",
                self.app.package_info().version
            ))
            .title("About Operator")
            .kind(tauri_plugin_dialog::MessageDialogKind::Info)
            .buttons(tauri_plugin_dialog::MessageDialogButtons::Ok)
            .show(|_| {});
    }
}

fn push_shortcuts_help(app: &tauri::AppHandle) {
    let _ = app.emit_to(shortcuts::MAIN_WINDOW_LABEL, "shortcut:help", ());
}

#[tauri::command]
fn menu_action(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    action: String,
    zoom: tauri::State<'_, menu::ZoomState>,
) -> Result<(), String> {
    let mut host = ShellMenuHost {
        app: &app,
        window: &window,
    };
    menu::dispatch_menu_action(&action, &zoom, &mut host);
    Ok(())
}

#[tauri::command]
fn shell_focus() {}

pub fn run() -> Result<(), Box<dyn Error>> {
    let context = tauri::generate_context!();
    let process_env: HashMap<String, String> = env::vars().collect();
    let original_home = daemon::home_dir()
        .ok_or_else(|| std::io::Error::other("Operator home directory could not be resolved"))?;
    let original_app_path = env::current_dir()?;
    let is_packaged = !tauri::is_dev();
    let app_version = context.package_info().version.to_string();
    let state_root = resolved_state_root()?;
    fs::create_dir_all(&state_root)?;
    install_panic_reporter(&state_root);
    match dropped_files::prune_stale(&state_root, dropped_files::unix_millis_now()) {
        Ok(removed) if removed > 0 => {
            eprintln!("pruned {removed} staged terminal drops older than seven days");
        }
        Ok(_) => {}
        Err(error) => eprintln!("failed to prune staged terminal drops: {error}"),
    }
    launch_app_state_flow(
        &process_env,
        &original_home,
        is_packaged,
        &app_version,
        &state_root,
    );
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

    let mut builder = tauri::Builder::default();
    let mut global_shortcuts_available = false;
    if audit_mode.is_none() && !terminal_benchmark {
        builder = builder
            .plugin(tauri_plugin_clipboard_manager::init())
            .plugin(tauri_plugin_dialog::init())
            .plugin(tauri_plugin_notification::init())
            .plugin(
                tauri_plugin_opener::Builder::new()
                    .open_js_links_on_click(false)
                    .build(),
            );
        global_shortcuts_available = shortcuts::probe_global_shortcuts();
        if global_shortcuts_available {
            builder = builder.plugin(tauri_plugin_global_shortcut::Builder::new().build());
        }
    }
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
            daemon_restart,
            window_set_overlay,
            window_is_fullscreen,
            theme_set,
            menu_action,
            shell_focus,
            keybindings_apply,
            keybindings_recording,
            set_close_shell_terminal_shortcut_enabled,
            native::choose_directory,
            native::open_external,
            native::clipboard_write,
            native::clipboard_read,
            native::notification_show,
            native::notification_badge,
            native::notification_dev_bounce,
            native::stage_dropped_file,
            native::delete_dropped_file,
            native::tray_attention_state,
            native::tray_renderer_ready,
            native::tray_set_locale
        ]);
    }
    let app = builder
        .setup(move |app| {
            let resources_dir = app.path().resource_dir()?;
            let daemon_config = daemon::supervisor::DaemonConfig::from_runtime(
                &process_env,
                original_home.clone(),
                resources_dir,
                original_app_path.clone(),
                is_packaged,
                app_version.clone(),
            );
            let daemon_manager = DaemonManager::with_runtime(
                daemon_config,
                process_env.clone(),
                original_app_path.clone(),
                std::time::Duration::from_secs(30),
            );
            if !app.manage(daemon_manager.clone()) {
                return Err(std::io::Error::other("daemon manager was already initialized").into());
            }
            let app_handle = app.handle().clone();
            let mut status_events = daemon_manager.subscribe();
            tauri::async_runtime::spawn(async move {
                loop {
                    match status_events.recv().await {
                        Ok(status) => {
                            let _ = app_handle.emit("daemon:status", status);
                        }
                        Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                        Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                    }
                }
            });
            if audit_mode.is_none() && !terminal_benchmark {
                let manager = daemon_manager.clone();
                tauri::async_runtime::spawn(async move {
                    manager.start().await;
                });
            }
            build_main_window(app.handle(), &state_root, audit_script.clone())?;
            if !app.manage(native::ShellState {
                state_root: state_root.clone(),
                tray: std::sync::Mutex::new(None),
                gate: std::sync::Mutex::new(tray::PendingTarget::default()),
                sessions: std::sync::Mutex::new(Vec::new()),
                locale: std::sync::Mutex::new("en".to_string()),
            }) || !app.manage(ShortcutRegistry(std::sync::Mutex::new(
                global_shortcuts_available.then(|| {
                    shortcuts::ShortcutEngine::new(
                        shortcuts::GlobalShortcutRegistrar {
                            app: app.handle().clone(),
                        },
                        cfg!(target_os = "macos"),
                    )
                }),
            ))) || !app.manage(FullscreenState(std::sync::Mutex::new(
                window::FullscreenTracker::default(),
            ))) || !app.manage(menu::ZoomState::default())
                || !app.manage(ThemeState(std::sync::Mutex::new(
                    window::ThemePreference::System,
                )))
            {
                return Err(std::io::Error::other("shell state was already initialized").into());
            }
            if audit_mode.is_none() && !terminal_benchmark {
                match tray::create_tray(app.handle(), "en") {
                    Ok(Some(handle)) => {
                        if let Some(shell) = app.try_state::<native::ShellState>() {
                            match shell.tray.lock() {
                                Ok(mut slot) => *slot = Some(handle),
                                Err(_) => {
                                    return Err(
                                        std::io::Error::other("tray state was poisoned").into()
                                    )
                                }
                            }
                        }
                    }
                    Ok(None) => {}
                    Err(error) => {
                        eprintln!("failed to initialize the Operator tray icon: {error}")
                    }
                }
                install_app_menu(app.handle())?;
                app.handle().on_menu_event(|app_handle, event| {
                    route_native_menu_event(app_handle, &event);
                });
            }
            Ok(())
        })
        .build(context)?;
    app.run(|app_handle, event| match event {
        tauri::RunEvent::Exit => {
            if let Some(manager) = app_handle.try_state::<DaemonManager>() {
                manager.request_shutdown();
            }
        }
        tauri::RunEvent::ExitRequested { code, api, .. } if code.is_none() => {
            if cfg!(target_os = "macos") {
                api.prevent_exit();
            }
        }
        tauri::RunEvent::Reopen {
            has_visible_windows,
            ..
        } => {
            if !has_visible_windows {
                native::focus_main_window(app_handle);
            }
        }
        tauri::RunEvent::WindowEvent { label, event, .. }
            if label == shortcuts::MAIN_WINDOW_LABEL =>
        {
            match event {
                tauri::WindowEvent::Resized(_) => poll_fullscreen_state(app_handle),
                tauri::WindowEvent::Focused(focused) => {
                    request_window_focus_state(focused);
                    let app_handle = app_handle.clone();
                    tauri::async_runtime::spawn(async move {
                        set_window_focus_state(&app_handle);
                    });
                }
                tauri::WindowEvent::ThemeChanged(_) => {
                    let app_handle = app_handle.clone();
                    tauri::async_runtime::spawn(async move {
                        follow_system_theme(&app_handle);
                    });
                }
                _ => {}
            }
        }
        _ => {}
    });
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
