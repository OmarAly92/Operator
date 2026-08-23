use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};

#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;

use chrono::{DateTime, SecondsFormat, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Current marker format version (spec §5 `schemaVersion`).
pub const SCHEMA_VERSION: i64 = 2;

/// File name of the marker beside the daemon run file under the Operator state root.
pub const APP_STATE_FILE_NAME: &str = "app-state.json";

/// One migration report payload inside the preserved migration block.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MigrationReport {
    pub projects_imported: u64,
    pub projects_skipped: u64,
}

/// The desktop-migration block carried on the marker; this process never writes
/// a new one, it only preserves what earlier launches or Electron recorded.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MigrationState {
    #[serde(default)]
    pub status: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_attempt_at: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub report: Option<MigrationReport>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

/// The launch marker `opr start` reads as its fast-path hint; the JSON keys
/// mirror backend/internal/cli/start.go `appState` exactly (camelCase).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppStateMarker {
    pub schema_version: i64,
    #[serde(default)]
    pub app_path: String,
    #[serde(default)]
    pub version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub installed_at: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_reconciled_at: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub install_source: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub migration: Option<MigrationState>,
}

/// Read the marker on disk; None when absent or unparseable so the caller treats
/// the launch as a first creation (self-healing).
pub fn read_marker(state_dir: &Path) -> Option<AppStateMarker> {
    let raw = fs::read_to_string(state_dir.join(APP_STATE_FILE_NAME)).ok()?;
    serde_json::from_str(&raw).ok()
}

/// Render an instant the way the Electron writer did: UTC ISO-8601, millisecond
/// precision, trailing Z.
pub fn format_timestamp(now: DateTime<Utc>) -> String {
    now.to_rfc3339_opts(SecondsFormat::Millis, true)
}

/// Write the launch marker. On first creation `installedAt` and `installSource`
/// capture provenance and then stay sticky across launches; `appPath`, `version`,
/// and `lastReconciledAt` refresh every launch; an existing migration block is
/// preserved unchanged.
pub fn write_marker(
    state_dir: &Path,
    app_path: &str,
    version: &str,
    installed_via: Option<&str>,
    now: DateTime<Utc>,
) -> io::Result<()> {
    let existing = read_marker(state_dir);
    let stamp = format_timestamp(now);
    let marker = AppStateMarker {
        schema_version: SCHEMA_VERSION,
        app_path: app_path.to_string(),
        version: version.to_string(),
        installed_at: Some(
            existing
                .as_ref()
                .and_then(|state| state.installed_at.clone())
                .unwrap_or_else(|| stamp.clone()),
        ),
        last_reconciled_at: Some(stamp),
        install_source: Some(
            existing
                .as_ref()
                .and_then(|state| state.install_source.clone())
                .unwrap_or_else(|| installed_via.unwrap_or("unknown").to_string()),
        ),
        migration: existing.and_then(|state| state.migration),
    };
    atomic_write(state_dir, &marker, now.timestamp_millis())
}

/// Atomic write mirroring backend/internal/runfile: temp file in the same dir,
/// then rename, so a concurrent `opr start` reader never sees a partial file.
fn atomic_write(state_dir: &Path, marker: &AppStateMarker, now_millis: i64) -> io::Result<()> {
    fs::create_dir_all(state_dir)?;
    let mut data = serde_json::to_string_pretty(marker)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
    data.push('\n');
    let tmp = state_dir.join(format!(
        ".app-state-{}-{}.json",
        std::process::id(),
        now_millis
    ));
    #[cfg(unix)]
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&tmp)?;
    #[cfg(not(unix))]
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(&tmp)?;
    file.write_all(data.as_bytes())?;
    atomic_replace(&tmp, &state_dir.join(APP_STATE_FILE_NAME))
}

#[cfg(not(windows))]
fn atomic_replace(from: &Path, to: &Path) -> io::Result<()> {
    fs::rename(from, to)
}

#[cfg(windows)]
fn atomic_replace(from: &Path, to: &Path) -> io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{
        MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH,
    };

    let from_wide: Vec<u16> = from.as_os_str().encode_wide().chain(Some(0)).collect();
    let to_wide: Vec<u16> = to.as_os_str().encode_wide().chain(Some(0)).collect();
    let result = unsafe {
        MoveFileExW(
            from_wide.as_ptr(),
            to_wide.as_ptr(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        )
    };
    if result == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

/// Parse the `--installed-via=<value>` flag out of argv; absent means the marker
/// defaults `installSource` to "unknown". An empty value stays `Some("")`, which
/// mirrors main.ts's falsy-string gate at the pre-relocation write.
pub fn parse_installed_via(argv: &[String]) -> Option<String> {
    const PREFIX: &str = "--installed-via=";
    argv.iter()
        .find(|arg| arg.starts_with(PREFIX))
        .map(|arg| arg[PREFIX.len()..].to_string())
}

/// Bundle path `opr start` later opens: on macOS walk the exec path up three
/// levels (MacOS -> Contents -> .app); elsewhere record the executable itself.
pub fn resolve_bundle_path(exec_path: &Path) -> Option<PathBuf> {
    #[cfg(target_os = "macos")]
    {
        if !exec_path.is_file() {
            return None;
        }
        let macos = exec_path.parent()?;
        if macos.file_name()? != "MacOS" {
            return None;
        }
        let contents = macos.parent()?;
        if contents.file_name()? != "Contents" {
            return None;
        }
        let bundle = contents.parent()?;
        if exec_path.file_name()? != "operator"
            || bundle.extension()? != "app"
            || !crate::relocation::macos_bundle_layout_valid(bundle)
        {
            return None;
        }
        Some(bundle.to_path_buf())
    }
    #[cfg(not(target_os = "macos"))]
    {
        Some(exec_path.to_path_buf())
    }
}
