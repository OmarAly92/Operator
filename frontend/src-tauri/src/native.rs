use std::path::PathBuf;
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
use crate::notification_policy::{dev_bounce_available, normalize_badge_count, show_plan};
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
    for action in plan {
        match action {
            crate::notification_policy::SignalAction::Toast => {
                let mut builder = window
                    .notification()
                    .builder()
                    .title(notification.title.clone());
                if let Some(body) = &notification.body {
                    builder = builder.body(body.clone());
                }
                builder.show().map_err(|error| error.to_string())?;
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
    Ok(())
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
    fn app_open_external_accepts_the_electron_allowlist() {
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
    fn chooser_titles_fall_back_like_the_electron_default() {
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
}
