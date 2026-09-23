use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;

use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine as _;
use tauri::{AppHandle, Manager, UserAttentionType};
use tauri_plugin_clipboard_manager::ClipboardExt;
use tauri_plugin_dialog::DialogExt;
use tauri_plugin_notification::NotificationExt;
use tauri_plugin_opener::OpenerExt;

use crate::dropped_files::{self, MAX_INPUT_BYTES};
use crate::menu::MenuPlatform;
use crate::notification_policy::{
    dev_bounce_available, normalize_badge_count, show_plan, toast_backend,
};
use crate::tray::{self, OpenSessionTarget, PendingTarget, SessionEntry, Zone};

pub const DEFAULT_CHOOSER_TITLE: &str = "Choose a git repository";
pub const BADGE_OVERLAY_PNG: &[u8] = include_bytes!("../../assets/notification-badge.png");
pub const MAX_BASE64_LEN: usize = MAX_INPUT_BYTES.div_ceil(3) * 4;

pub const APP_EXTERNAL_SCHEMES: [&str; 3] = ["http", "https", "mailto"];

fn split_scheme(trimmed: &str) -> Option<(String, &str)> {
    let separator = trimmed.find(':')?;
    let scheme = trimmed[..separator].to_ascii_lowercase();
    Some((scheme, &trimmed[separator + 1..]))
}

fn http_s_authority(remainder: &str) -> bool {
    let Some(authority) = remainder.strip_prefix("//") else {
        return false;
    };
    authority
        .split(['/', '?', '#'])
        .next()
        .is_some_and(|host| !host.is_empty() && !host.contains('\\'))
}

/// Canonicalises a candidate terminal link against `base` -- the block's cwd or
/// the session's workspace path -- and answers only for a path that exists. A
/// relative candidate without a base is unanswerable, which is what keeps a bare
/// word in terminal output from resolving against the daemon's own cwd.
pub fn resolved_link_path(base: Option<&str>, path: &str) -> Option<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    link_path_in(base, home.as_deref(), path)
}

fn link_path_in(base: Option<&str>, home: Option<&Path>, path: &str) -> Option<PathBuf> {
    let trimmed = path.trim();
    if trimmed.is_empty() || trimmed.contains('\0') {
        return None;
    }
    let expanded = if trimmed == "~" {
        home?.to_path_buf()
    } else if let Some(rest) = trimmed.strip_prefix("~/") {
        home?.join(rest)
    } else {
        PathBuf::from(trimmed)
    };
    let candidate = if expanded.is_absolute() {
        expanded
    } else {
        PathBuf::from(base?).join(expanded)
    };
    let resolved = candidate.canonicalize().ok()?;
    resolved.exists().then_some(resolved)
}

pub const MAX_PATH_CANDIDATES: usize = 20;

#[derive(Clone, Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PathCandidate {
    pub path: String,
    pub allow_directory: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize)]
pub struct ResolvedPath {
    pub index: usize,
    pub path: String,
}

pub fn first_existing_path(
    base: Option<&str>,
    home: Option<&Path>,
    candidates: &[PathCandidate],
) -> Option<ResolvedPath> {
    candidates
        .iter()
        .take(MAX_PATH_CANDIDATES)
        .enumerate()
        .find_map(|(index, candidate)| {
            let resolved = link_path_in(base, home, &candidate.path)?;
            if resolved.is_dir() && !candidate.allow_directory {
                return None;
            }
            Some(ResolvedPath {
                index,
                path: resolved.to_string_lossy().to_string(),
            })
        })
}

pub fn is_allowed_app_external_url(raw_url: &str) -> bool {
    let trimmed = raw_url.trim();
    if trimmed.is_empty() {
        return false;
    }
    let Some((scheme, remainder)) = split_scheme(trimmed) else {
        return false;
    };
    match scheme.as_str() {
        "http" | "https" => http_s_authority(remainder),
        "mailto" => !remainder
            .chars()
            .any(|c| c.is_ascii_whitespace() || c.is_control()),
        _ => false,
    }
}

pub fn is_allowed_preview_url(raw_url: &str) -> bool {
    let trimmed = raw_url.trim();
    if trimmed.is_empty() {
        return false;
    }
    let Some((scheme, remainder)) = split_scheme(trimmed) else {
        return false;
    };
    matches!(scheme.as_str(), "http" | "https") && http_s_authority(remainder)
}

pub fn chooser_title(title: Option<&str>) -> String {
    match title.map(str::trim).filter(|title| !title.is_empty()) {
        Some(title) => title.to_string(),
        None => DEFAULT_CHOOSER_TITLE.to_string(),
    }
}

pub fn chooser_selection(path: Option<PathBuf>) -> Option<String> {
    path.map(|path| path.to_string_lossy().into_owned())
}

pub fn writes_primary_selection(platform: MenuPlatform) -> bool {
    platform == MenuPlatform::Linux
}

pub fn menu_platform() -> MenuPlatform {
    if cfg!(target_os = "macos") {
        MenuPlatform::Macos
    } else if cfg!(target_os = "windows") {
        MenuPlatform::Windows
    } else {
        MenuPlatform::Linux
    }
}

pub struct ShellState {
    pub state_root: PathBuf,
    pub tray: Mutex<Option<tray::TrayHandle>>,
    pub gate: Mutex<PendingTarget>,
    pub sessions: Mutex<Vec<SessionEntry>>,
    pub locale: Mutex<String>,
}

#[derive(Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionEntryInput {
    pub project_id: String,
    #[serde(default)]
    pub project_name: String,
    pub session_id: String,
    #[serde(default)]
    pub title: String,
    pub zone: String,
}

#[derive(serde::Deserialize)]
pub struct TrayAttentionInput {
    #[serde(default)]
    pub sessions: Vec<SessionEntryInput>,
}

impl From<&SessionEntryInput> for Option<SessionEntry> {
    fn from(input: &SessionEntryInput) -> Self {
        Zone::parse(&input.zone).map(|zone| SessionEntry {
            project_id: input.project_id.clone(),
            project_name: input.project_name.clone(),
            session_id: input.session_id.clone(),
            title: input.title.clone(),
            zone,
        })
    }
}

#[tauri::command]
pub async fn choose_directory(
    app: AppHandle,
    title: Option<String>,
) -> Result<Option<String>, String> {
    let dialog_title = chooser_title(title.as_deref());
    tauri::async_runtime::spawn_blocking(move || {
        let picked = app
            .dialog()
            .file()
            .set_title(dialog_title)
            .blocking_pick_folder();
        Ok::<Option<String>, String>(chooser_selection(
            picked.and_then(|path| path.simplified().into_path().ok()),
        ))
    })
    .await
    .map_err(|error| error.to_string())?
}

#[tauri::command]
pub async fn open_external(app: AppHandle, url: String) -> Result<(), String> {
    if !is_allowed_app_external_url(&url) {
        return Err("Unsupported external URL".to_string());
    }
    app.opener()
        .open_url(url, None::<&str>)
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn resolve_path(base: Option<String>, path: String) -> Result<Option<String>, String> {
    tauri::async_runtime::spawn_blocking(move || {
        resolved_link_path(base.as_deref(), &path)
            .map(|resolved| resolved.to_string_lossy().to_string())
    })
    .await
    .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn resolve_first_path(
    base: Option<String>,
    candidates: Vec<PathCandidate>,
) -> Result<Option<ResolvedPath>, String> {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    tauri::async_runtime::spawn_blocking(move || {
        first_existing_path(base.as_deref(), home.as_deref(), &candidates)
    })
    .await
    .map_err(|error| error.to_string())
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ExternalEditor {
    Vscode,
    Cursor,
    Zed,
}

impl ExternalEditor {
    fn bundled_cli(self) -> &'static str {
        match self {
            Self::Vscode => "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
            Self::Cursor => "/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
            Self::Zed => "/Applications/Zed.app/Contents/MacOS/cli",
        }
    }

    fn cli_name(self) -> &'static str {
        match self {
            Self::Vscode => "code",
            Self::Cursor => "cursor",
            Self::Zed => "zed",
        }
    }
}

pub fn editor_args(
    editor: ExternalEditor,
    path: &Path,
    line: Option<u32>,
    column: Option<u32>,
) -> Vec<OsString> {
    let Some(line) = line else {
        return vec![path.as_os_str().to_os_string()];
    };
    let mut target = path.as_os_str().to_os_string();
    target.push(format!(":{line}"));
    if let Some(column) = column {
        target.push(format!(":{column}"));
    }
    match editor {
        ExternalEditor::Zed => vec![target],
        ExternalEditor::Vscode | ExternalEditor::Cursor => vec![OsString::from("-g"), target],
    }
}

pub fn editor_cli(
    editor: ExternalEditor,
    path_var: Option<&OsStr>,
    exists: impl Fn(&Path) -> bool,
) -> Option<PathBuf> {
    let bundled = PathBuf::from(editor.bundled_cli());
    if exists(&bundled) {
        return Some(bundled);
    }
    path_var
        .into_iter()
        .flat_map(std::env::split_paths)
        .map(|dir| dir.join(editor.cli_name()))
        .find(|candidate| exists(candidate))
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum OpenPlan {
    Editor { cli: PathBuf, args: Vec<OsString> },
    System { cli_missing: bool },
}

pub fn open_plan(
    editor: Option<ExternalEditor>,
    path: &Path,
    line: Option<u32>,
    column: Option<u32>,
    path_var: Option<&OsStr>,
    exists: impl Fn(&Path) -> bool,
) -> OpenPlan {
    let Some(editor) = editor else {
        return OpenPlan::System { cli_missing: false };
    };
    match editor_cli(editor, path_var, exists) {
        Some(cli) => OpenPlan::Editor {
            cli,
            args: editor_args(editor, path, line, column),
        },
        None => OpenPlan::System { cli_missing: true },
    }
}

pub fn spawn_editor(cli: &Path, args: &[OsString]) -> std::io::Result<Child> {
    Command::new(cli)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenPathOutcome {
    pub cli_missing: bool,
}

#[tauri::command]
pub async fn open_path(
    app: AppHandle,
    path: String,
    line: Option<u32>,
    column: Option<u32>,
    editor: Option<ExternalEditor>,
) -> Result<OpenPathOutcome, String> {
    let resolved = resolved_link_path(None, &path).ok_or_else(|| "Unknown path".to_string())?;
    let path_var = std::env::var_os("PATH");
    let cli_missing = match open_plan(
        editor,
        &resolved,
        line,
        column,
        path_var.as_deref(),
        Path::is_file,
    ) {
        OpenPlan::Editor { cli, args } => match spawn_editor(&cli, &args) {
            Ok(mut child) => {
                std::thread::spawn(move || child.wait());
                return Ok(OpenPathOutcome { cli_missing: false });
            }
            Err(_) => true,
        },
        OpenPlan::System { cli_missing } => cli_missing,
    };
    app.opener()
        .open_path(resolved.to_string_lossy().to_string(), None::<&str>)
        .map_err(|error| error.to_string())?;
    Ok(OpenPathOutcome { cli_missing })
}

#[tauri::command]
pub async fn clipboard_write(app: AppHandle, text: String) -> Result<(), String> {
    app.clipboard()
        .write_text(text.clone())
        .map_err(|error| error.to_string())?;
    if writes_primary_selection(menu_platform()) {
        if let Err(error) = write_primary_selection(&text) {
            eprintln!("failed to mirror clipboard text to the primary selection: {error}");
        }
    }
    Ok(())
}

#[cfg(target_os = "linux")]
fn write_primary_selection(text: &str) -> Result<(), String> {
    use arboard::{LinuxClipboardKind, SetExtLinux};

    let mut clipboard = arboard::Clipboard::new().map_err(|error| error.to_string())?;
    clipboard
        .set()
        .clipboard(LinuxClipboardKind::Primary)
        .text(text.to_string())
        .map_err(|error| error.to_string())
}

#[cfg(not(target_os = "linux"))]
fn write_primary_selection(_text: &str) -> Result<(), String> {
    Ok(())
}

#[tauri::command]
pub async fn clipboard_read(app: AppHandle) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || {
        app.clipboard()
            .read_text()
            .map_err(|error| error.to_string())
    })
    .await
    .map_err(|error| error.to_string())?
}

#[derive(serde::Deserialize)]
pub struct NotificationInput {
    pub id: String,
    pub title: String,
    pub body: Option<String>,
    #[serde(rename = "type")]
    pub notification_type: Option<String>,
}

#[tauri::command]
pub async fn notification_show(
    window: tauri::WebviewWindow,
    notification: NotificationInput,
) -> Result<(), String> {
    if notification.id.is_empty() {
        return Ok(());
    }
    let focused = window.is_focused().unwrap_or(false);
    let plan = show_plan(
        focused,
        true,
        Some(&notification.title),
        notification.notification_type.as_deref(),
    );
    let mut toast_result = Ok(());
    for action in plan {
        match action {
            crate::notification_policy::SignalAction::Toast => {
                toast_result = show_toast(&window, &notification).await;
            }
            crate::notification_policy::SignalAction::Attention => {
                let request_type = if cfg!(target_os = "macos") {
                    UserAttentionType::Informational
                } else {
                    UserAttentionType::Critical
                };
                if let Err(error) = window.request_user_attention(Some(request_type)) {
                    eprintln!("failed to request user attention: {error}");
                }
            }
        }
    }
    toast_result
}

pub fn current_toast_backend() -> crate::notification_policy::ToastBackend {
    #[cfg(target_os = "macos")]
    let has_bundle_id = crate::mac_notifications::has_main_bundle_identifier();
    #[cfg(not(target_os = "macos"))]
    let has_bundle_id = false;
    toast_backend(cfg!(target_os = "macos"), tauri::is_dev(), has_bundle_id)
}

async fn show_toast(
    window: &tauri::WebviewWindow,
    notification: &NotificationInput,
) -> Result<(), String> {
    match current_toast_backend() {
        #[cfg(target_os = "macos")]
        crate::notification_policy::ToastBackend::UserNotifications => {
            crate::mac_notifications::post(
                &notification.id,
                &notification.title,
                notification.body.as_deref(),
            )
            .await
        }
        _ => {
            let mut builder = window
                .notification()
                .builder()
                .title(notification.title.clone());
            if let Some(body) = &notification.body {
                builder = builder.body(body.clone());
            }
            builder.show().map_err(|error| error.to_string())
        }
    }
}

#[tauri::command]
pub async fn notification_permission() -> Result<String, String> {
    match current_toast_backend() {
        #[cfg(target_os = "macos")]
        crate::notification_policy::ToastBackend::UserNotifications => {
            Ok(crate::mac_notifications::authorization().await.to_string())
        }
        _ => Ok("unsupported".to_string()),
    }
}

#[tauri::command]
pub async fn notification_request_permission() -> Result<String, String> {
    match current_toast_backend() {
        #[cfg(target_os = "macos")]
        crate::notification_policy::ToastBackend::UserNotifications => {
            Ok(crate::mac_notifications::ensure_authorization()
                .await
                .to_string())
        }
        _ => Ok("unsupported".to_string()),
    }
}

#[tauri::command]
pub async fn notification_open_settings(app: AppHandle) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        let url = crate::mac_notifications::settings_url(&app.config().identifier);
        app.opener()
            .open_url(url, None::<&str>)
            .map_err(|error| error.to_string())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = app;
        Ok(())
    }
}

pub struct AppClickHost<'a>(pub &'a AppHandle);

impl crate::notification_policy::ClickHost for AppClickHost<'_> {
    fn focus_main_window(&mut self) {
        focus_main_window(self.0);
    }

    fn send_clicked(&mut self, id: &str) {
        use tauri::Emitter;
        let _ = self
            .0
            .emit(crate::notification_policy::CLICK_EVENT, id.to_string());
    }
}

#[cfg(target_os = "windows")]
fn badge_overlay_image() -> Result<tauri::image::Image<'static>, String> {
    tauri::image::Image::from_bytes(BADGE_OVERLAY_PNG).map_err(|error| error.to_string())
}

#[cfg(target_os = "macos")]
fn apply_badge(window: &tauri::WebviewWindow, count: i64) -> Result<(), String> {
    window
        .set_badge_label((count > 0).then(|| count.to_string()))
        .map_err(|error| error.to_string())
}

#[cfg(target_os = "linux")]
fn apply_badge(window: &tauri::WebviewWindow, count: i64) -> Result<(), String> {
    window
        .set_badge_count((count > 0).then_some(count))
        .map_err(|error| error.to_string())
}

#[cfg(target_os = "windows")]
fn apply_badge(window: &tauri::WebviewWindow, count: i64) -> Result<(), String> {
    let overlay = match count > 0 {
        true => Some(badge_overlay_image()?),
        false => None,
    };
    window
        .set_overlay_icon(overlay)
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn notification_badge(window: tauri::WebviewWindow, count: f64) -> Result<(), String> {
    let normalized = normalize_badge_count(count);
    if let Err(error) = apply_badge(&window, normalized) {
        eprintln!("failed to apply the notification badge: {error}");
    }
    Ok(())
}

#[tauri::command]
pub async fn notification_dev_bounce(window: tauri::WebviewWindow) -> Result<(), String> {
    if !dev_bounce_available(!tauri::is_dev()) {
        return Err("notifications:devBounce is only available in development builds".to_string());
    }
    window
        .request_user_attention(Some(UserAttentionType::Critical))
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn stage_dropped_file(
    shell: tauri::State<'_, ShellState>,
    name: String,
    data: String,
) -> Result<String, String> {
    if data.len() > MAX_BASE64_LEN {
        return Err(dropped_files::StageError::TooLarge {
            size: MAX_INPUT_BYTES + 1,
        }
        .to_string());
    }
    let bytes = BASE64_STANDARD
        .decode(data.as_bytes())
        .map_err(|_| "invalid base64 payload for the dropped file".to_string())?;
    let id = uuid::Uuid::new_v4().simple().to_string();
    let now_ms = dropped_files::unix_millis_now();
    let staged = dropped_files::stage(&shell.state_root, &name, &bytes, &id, now_ms)
        .map_err(|error| error.to_string())?;
    Ok(staged.to_string_lossy().into_owned())
}

#[tauri::command]
pub async fn delete_dropped_file(
    shell: tauri::State<'_, ShellState>,
    path: String,
) -> Result<(), String> {
    dropped_files::remove_staged(&shell.state_root, std::path::Path::new(&path))
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn tray_attention_state(
    app: AppHandle,
    shell: tauri::State<'_, ShellState>,
    attention: TrayAttentionInput,
) -> Result<(), String> {
    let sessions: Vec<SessionEntry> = attention
        .sessions
        .iter()
        .filter_map(<Option<SessionEntry>>::from)
        .collect();
    if let Ok(mut guard) = shell.sessions.lock() {
        *guard = sessions.clone();
    }
    tray::apply_state(&app, &sessions)?;
    Ok(())
}

#[tauri::command]
pub async fn tray_set_locale(
    app: AppHandle,
    shell: tauri::State<'_, ShellState>,
    locale: String,
) -> Result<(), String> {
    if !tray::APP_LOCALES.contains(&locale.as_str()) {
        return Ok(());
    }
    if let Ok(mut guard) = shell.locale.lock() {
        *guard = locale.clone();
    }
    let sessions = shell
        .sessions
        .lock()
        .map(|guard| guard.clone())
        .unwrap_or_default();
    tray::apply_state(&app, &sessions)?;
    Ok(())
}

#[tauri::command]
pub async fn tray_renderer_ready(
    app: AppHandle,
    shell: tauri::State<'_, ShellState>,
) -> Result<(), String> {
    let target = shell
        .gate
        .lock()
        .map(|mut gate| gate.renderer_ready())
        .unwrap_or(None);
    if let Some(target) = target {
        emit_open_session(&app, target);
    }
    Ok(())
}

pub fn emit_open_session(app: &AppHandle, target: OpenSessionTarget) {
    use tauri::Emitter;
    let _ = app.emit_to(
        crate::shortcuts::MAIN_WINDOW_LABEL,
        tray::TRAY_OPEN_SESSION_EVENT,
        target,
    );
}

pub fn open_session_from_tray(app: &AppHandle, target: OpenSessionTarget) {
    focus_main_window(app);
    let delivered = app.try_state::<ShellState>().and_then(|shell| {
        shell
            .gate
            .lock()
            .ok()
            .and_then(|mut gate| gate.open_session(target))
    });
    if let Some(target) = delivered {
        emit_open_session(app, target);
    }
}

pub fn focus_main_window(app: &AppHandle) {
    match app.get_webview_window(crate::shortcuts::MAIN_WINDOW_LABEL) {
        Some(window) => {
            if window.is_minimized().unwrap_or(false) {
                let _ = window.unminimize();
            }
            let _ = window.show();
            let _ = window.set_focus();
        }
        None => {
            if let Err(error) = crate::rebuild_main_window(app) {
                eprintln!("failed to recreate the Operator window: {error}");
            }
        }
    }
}

pub fn reset_native_shell(shell: &ShellState) {
    if let Ok(mut gate) = shell.gate.lock() {
        gate.reset();
    }
    if let Ok(mut sessions) = shell.sessions.lock() {
        sessions.clear();
    }
}

pub fn handle_tray_menu_event(app: &AppHandle, event: &tauri::menu::MenuEvent) {
    let id = event.id().as_ref();
    if id == "show" {
        focus_main_window(app);
        return;
    }
    if let Some(target) = tray::parse_session_item_id(id) {
        open_session_from_tray(app, target);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn app_open_external_accepts_the_scheme_allowlist() {
        for allowed in [
            "http://example.com",
            "https://example.com/path?query=1#fragment",
            "HTTPS://EXAMPLE.COM/UPPER",
            "http://127.0.0.1:3001/session",
            "https://localhost",
            "mailto:user@example.com",
            "MAILTO:user@example.com?subject=hi",
            "mailto:",
        ] {
            assert!(is_allowed_app_external_url(allowed), "{allowed}");
        }
    }

    #[test]
    fn app_open_external_still_rejects_dangerous_and_unknown_schemes() {
        for rejected in [
            "javascript:alert(1)",
            "data:text/html,hello",
            "file:///etc/passwd",
            "ftp://example.com/file",
            "tauri://localhost/index.html",
            "slack://channel?id=1",
            "//example.com/protocol-relative",
            "http://",
            "",
            "   ",
            "not a url",
            "mail to:user@example.com",
            "mailto:a@b\njavascript:alert(1)",
        ] {
            assert!(!is_allowed_app_external_url(rejected), "{rejected}");
        }
    }

    #[test]
    fn preview_targets_keep_the_strict_http_s_allowlist() {
        for allowed in [
            "http://example.com",
            "https://example.com/path?query=1#fragment",
            "HTTPS://EXAMPLE.COM/UPPER",
            "http://127.0.0.1:3001/session",
            "https://localhost",
        ] {
            assert!(is_allowed_preview_url(allowed), "{allowed}");
        }
        for rejected in [
            "mailto:user@example.com",
            "MAILTO:user@example.com",
            "javascript:alert(1)",
            "data:text/html,hello",
            "file:///etc/passwd",
            "ftp://example.com/file",
            "tauri://localhost/index.html",
            "//example.com/protocol-relative",
            "http://",
            "",
            "   ",
            "not a url",
        ] {
            assert!(!is_allowed_preview_url(rejected), "{rejected}");
        }
    }

    #[test]
    fn chooser_titles_fall_back_to_the_platform_default() {
        assert_eq!(chooser_title(None), DEFAULT_CHOOSER_TITLE);
        assert_eq!(chooser_title(Some("")), DEFAULT_CHOOSER_TITLE);
        assert_eq!(chooser_title(Some("   ")), DEFAULT_CHOOSER_TITLE);
        assert_eq!(chooser_title(Some("Pick a workspace")), "Pick a workspace");
    }

    #[test]
    fn chooser_cancellation_resolves_to_null() {
        assert_eq!(chooser_selection(None), None);
        assert_eq!(
            chooser_selection(Some(PathBuf::from("/repos/picked"))),
            Some("/repos/picked".to_string())
        );
    }

    #[test]
    fn primary_selection_writes_happen_only_on_linux() {
        assert!(writes_primary_selection(MenuPlatform::Linux));
        assert!(!writes_primary_selection(MenuPlatform::Macos));
        assert!(!writes_primary_selection(MenuPlatform::Windows));
    }

    #[test]
    fn attention_input_skips_entries_with_unknown_zones() {
        let entry = SessionEntryInput {
            project_id: "p".into(),
            project_name: "Alpha".into(),
            session_id: "s".into(),
            title: "t".into(),
            zone: "working".into(),
        };
        assert!(<Option<SessionEntry>>::from(&entry).is_none());

        let actionable = SessionEntryInput {
            zone: "merge".into(),
            ..entry
        };
        let parsed = <Option<SessionEntry>>::from(&actionable).unwrap();
        assert_eq!(parsed.zone, Zone::Merge);
        assert_eq!(parsed.project_name, "Alpha");
    }
    fn scratch(name: &str) -> PathBuf {
        let root =
            std::env::temp_dir().join(format!("operator-first-path-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::create_dir_all(root.join("home/notes")).unwrap();
        std::fs::write(root.join("src/a.ts"), "").unwrap();
        std::fs::write(root.join("home/todo.md"), "").unwrap();
        root.canonicalize().unwrap()
    }

    fn candidate(path: &str, allow_directory: bool) -> PathCandidate {
        PathCandidate {
            path: path.into(),
            allow_directory,
        }
    }

    #[test]
    fn first_existing_path_answers_with_the_first_candidate_that_exists() {
        let root = scratch("first");
        let base = root.to_str();
        let found = first_existing_path(
            base,
            None,
            &[
                candidate("see src/a.ts", false),
                candidate("src/a.ts", false),
                candidate("src", true),
            ],
        );
        assert_eq!(
            found,
            Some(ResolvedPath {
                index: 1,
                path: root.join("src/a.ts").to_string_lossy().to_string(),
            })
        );
        assert_eq!(
            first_existing_path(base, None, &[candidate("gone.ts", false)]),
            None
        );
        assert_eq!(
            first_existing_path(None, None, &[candidate("src/a.ts", false)]),
            None
        );
    }

    #[test]
    fn first_existing_path_expands_a_bare_tilde_and_a_tilde_slash_against_home() {
        let root = scratch("home");
        let home = root.join("home");
        let found = |path: &str| {
            first_existing_path(None, Some(&home), &[candidate(path, true)])
                .map(|resolved| resolved.path)
        };
        assert_eq!(found("~"), Some(home.to_string_lossy().to_string()));
        assert_eq!(
            found("~/todo.md"),
            Some(home.join("todo.md").to_string_lossy().to_string())
        );
        assert_eq!(
            found("~/notes"),
            Some(home.join("notes").to_string_lossy().to_string())
        );
        assert_eq!(
            first_existing_path(None, None, &[candidate("~", true)]),
            None
        );
    }

    #[test]
    fn first_existing_path_skips_a_directory_the_candidate_does_not_allow() {
        let root = scratch("directories");
        let base = root.to_str();
        assert_eq!(
            first_existing_path(base, None, &[candidate("src", false)]),
            None
        );
        assert_eq!(
            first_existing_path(
                base,
                None,
                &[candidate("src", false), candidate("src/a.ts", false)]
            )
            .map(|resolved| resolved.index),
            Some(1)
        );
        assert_eq!(
            first_existing_path(base, None, &[candidate("src/", true)])
                .map(|resolved| resolved.path),
            Some(root.join("src").to_string_lossy().to_string())
        );
    }

    #[test]
    fn first_existing_path_never_looks_past_the_candidate_cap() {
        let root = scratch("cap");
        let base = root.to_str();
        let mut candidates: Vec<PathCandidate> = (0..MAX_PATH_CANDIDATES)
            .map(|index| candidate(&format!("missing-{index}"), false))
            .collect();
        candidates.push(candidate("src/a.ts", false));
        assert_eq!(first_existing_path(base, None, &candidates), None);
        candidates.remove(0);
        assert_eq!(
            first_existing_path(base, None, &candidates).map(|resolved| resolved.index),
            Some(MAX_PATH_CANDIDATES - 1)
        );
    }

    #[test]
    fn path_candidates_arrive_in_the_renderer_s_camel_case() {
        let parsed: Vec<PathCandidate> =
            serde_json::from_str(r#"[{"path":"~/x","allowDirectory":true}]"#).unwrap();
        assert_eq!(parsed[0].path, "~/x");
        assert!(parsed[0].allow_directory);
        let sent = serde_json::to_value(ResolvedPath {
            index: 2,
            path: "/a".into(),
        })
        .unwrap();
        assert_eq!(sent, serde_json::json!({ "index": 2, "path": "/a" }));
    }
}
