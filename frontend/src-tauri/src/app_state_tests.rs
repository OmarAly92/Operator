use std::fs;
use std::ops::Deref;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::mpsc;
use std::sync::Barrier;
use std::thread;
use std::{collections::HashMap, env, io};

use chrono::{TimeZone, Utc};
use serde_json::json;

use crate::app_state::{
    format_timestamp, parse_installed_via, read_marker, resolve_bundle_path, write_marker,
    AppStateMarker, MigrationReport, MigrationState, APP_STATE_FILE_NAME, SCHEMA_VERSION,
};
use crate::relocation::{
    decide_relocation, execute_relocation, inspect_installed_bundle_in, installed_bundle_path,
    installed_bundle_path_in, is_in_applications_folder, macos_bundle_layout_valid,
    read_bundle_version, staged_bundle_path, trashed_bundle_destination, valid_macos_bundle,
    RelocationAction, RelocationExecutor, RelocationInputs, RelocationLock,
};

struct ScratchDir(PathBuf);

impl Deref for ScratchDir {
    type Target = Path;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl AsRef<Path> for ScratchDir {
    fn as_ref(&self) -> &Path {
        &self.0
    }
}

impl Drop for ScratchDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn scratch_dir(name: &str) -> ScratchDir {
    let dir = std::env::temp_dir().join(format!(
        "operator-app-state-test-{}-{}",
        name,
        uuid::Uuid::new_v4().simple()
    ));
    fs::create_dir_all(&dir).unwrap();
    ScratchDir(dir)
}

fn instant(seconds: i64, nanos: u32) -> chrono::DateTime<Utc> {
    Utc.timestamp_opt(seconds, nanos).single().unwrap()
}

fn marker_path(state_dir: &Path) -> PathBuf {
    state_dir.join(APP_STATE_FILE_NAME)
}

fn write_executable(path: &Path) {
    fs::write(path, b"binary").unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = fs::metadata(path).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(path, permissions).unwrap();
    }
}

fn real_bundle_plist(version: &str) -> String {
    format!(
        "<key>CFBundleIdentifier</key><string>dev.operator.desktop</string><key>CFBundleName</key><string>Operator</string><key>CFBundleExecutable</key><string>operator</string><key>CFBundleShortVersionString</key><string>{version}</string>"
    )
}

#[test]
fn app_state_file_name_matches_go_reader() {
    assert_eq!(APP_STATE_FILE_NAME, "app-state.json");
}

#[test]
fn first_write_captures_provenance_from_installed_via() {
    let dir = scratch_dir("first-write-via");
    write_marker(
        &dir,
        "/Applications/Operator.app",
        "0.10.3",
        Some("npm-bootstrap"),
        instant(1_700_000_000, 0),
    )
    .unwrap();

    let marker = read_marker(&dir).unwrap();
    assert_eq!(marker.schema_version, SCHEMA_VERSION);
    assert_eq!(marker.schema_version, 2);
    assert_eq!(marker.app_path, "/Applications/Operator.app");
    assert_eq!(marker.version, "0.10.3");
    assert_eq!(
        marker.installed_at.as_deref(),
        Some("2023-11-14T22:13:20.000Z")
    );
    assert_eq!(
        marker.last_reconciled_at.as_deref(),
        Some("2023-11-14T22:13:20.000Z")
    );
    assert_eq!(marker.install_source.as_deref(), Some("npm-bootstrap"));
    assert_eq!(marker.migration, None);
}

#[test]
fn first_write_without_installed_via_defaults_to_unknown() {
    let dir = scratch_dir("first-write-unknown");
    write_marker(
        &dir,
        "/Applications/Operator.app",
        "0.10.3",
        None,
        instant(1_700_000_000, 500_000_000),
    )
    .unwrap();

    let marker = read_marker(&dir).unwrap();
    assert_eq!(marker.install_source.as_deref(), Some("unknown"));
    assert_eq!(
        marker.installed_at.as_deref(),
        Some("2023-11-14T22:13:20.500Z")
    );
}

#[test]
fn relaunch_preserves_provenance_while_refreshing_facts() {
    let dir = scratch_dir("relaunch-sticky");
    write_marker(
        &dir,
        "/Users/me/Downloads/Operator.app",
        "0.10.2",
        Some("npm-bootstrap"),
        instant(1_700_000_000, 0),
    )
    .unwrap();
    write_marker(
        &dir,
        "/Applications/Operator.app",
        "0.10.3",
        None,
        instant(1_700_000_100, 0),
    )
    .unwrap();

    let marker = read_marker(&dir).unwrap();
    assert_eq!(
        marker.installed_at.as_deref(),
        Some("2023-11-14T22:13:20.000Z")
    );
    assert_eq!(marker.install_source.as_deref(), Some("npm-bootstrap"));
    assert_eq!(marker.app_path, "/Applications/Operator.app");
    assert_eq!(marker.version, "0.10.3");
    assert_eq!(
        marker.last_reconciled_at.as_deref(),
        Some("2023-11-14T22:15:00.000Z")
    );
}

#[test]
fn relaunch_preserves_migration_block_verbatim() {
    let dir = scratch_dir("migration-preserved");
    let seeded = json!({
        "schemaVersion": 2,
        "appPath": "/Applications/Operator.app",
        "version": "0.10.2",
        "installedAt": "2023-11-14T22:13:20.000Z",
        "lastReconciledAt": "2023-11-14T22:13:20.000Z",
        "installSource": "npm-bootstrap",
        "migration": {
            "status": "completed",
            "lastAttemptAt": "2023-11-15T08:00:00.000Z",
            "completedAt": "2023-11-15T08:00:01.000Z",
            "report": {"projectsImported": 2, "projectsSkipped": 1},
            "legacyExtra": {"kept": true}
        }
    });
    fs::write(marker_path(&dir), serde_json::to_vec(&seeded).unwrap()).unwrap();

    write_marker(
        &dir,
        "/Applications/Operator.app",
        "0.10.3",
        None,
        instant(1_700_000_200, 0),
    )
    .unwrap();

    let marker = read_marker(&dir).unwrap();
    assert_eq!(
        marker.migration,
        Some(MigrationState {
            status: "completed".to_string(),
            last_attempt_at: Some("2023-11-15T08:00:00.000Z".to_string()),
            completed_at: Some("2023-11-15T08:00:01.000Z".to_string()),
            report: Some(MigrationReport {
                projects_imported: 2,
                projects_skipped: 1,
            }),
            error: None,
            extra: [("legacyExtra".to_string(), json!({"kept": true}))]
                .into_iter()
                .collect(),
        })
    );
}

#[test]
fn write_drops_unknown_top_level_keys_like_the_electron_writer() {
    let dir = scratch_dir("top-level-keys");
    let seeded = r#"{"schemaVersion":9,"appPath":"/x","rogue":true}"#;
    fs::write(marker_path(&dir), seeded).unwrap();

    write_marker(&dir, "/y", "0.10.3", None, instant(1_700_000_000, 0)).unwrap();

    let raw = fs::read_to_string(marker_path(&dir)).unwrap();
    assert!(!raw.contains("rogue"));
    assert_eq!(read_marker(&dir).unwrap().schema_version, 2);
}

#[test]
fn corrupt_marker_recovers_as_first_creation() {
    let dir = scratch_dir("corrupt-recovery");
    fs::write(marker_path(&dir), "{not json at all").unwrap();

    write_marker(
        &dir,
        "/Applications/Operator.app",
        "0.10.3",
        Some("npm-bootstrap"),
        instant(1_700_000_300, 0),
    )
    .unwrap();

    let marker = read_marker(&dir).unwrap();
    assert_eq!(
        marker.installed_at.as_deref(),
        Some("2023-11-14T22:18:20.000Z")
    );
    assert_eq!(marker.install_source.as_deref(), Some("npm-bootstrap"));
    assert_eq!(marker.app_path, "/Applications/Operator.app");
}

#[test]
fn partial_legacy_marker_fields_are_tolerated() {
    let dir = scratch_dir("legacy-fields");
    fs::write(marker_path(&dir), r#"{"schemaVersion":1,"appPath":"/old"}"#).unwrap();

    write_marker(
        &dir,
        "/Applications/Operator.app",
        "0.10.3",
        Some("npm-bootstrap"),
        instant(1_700_000_400, 0),
    )
    .unwrap();

    let marker = read_marker(&dir).unwrap();
    assert_eq!(
        marker.installed_at.as_deref(),
        Some("2023-11-14T22:20:00.000Z")
    );
    assert_eq!(marker.install_source.as_deref(), Some("npm-bootstrap"));
}

#[test]
fn atomic_write_leaves_exactly_the_final_marker() {
    let dir = scratch_dir("atomic-write");
    write_marker(&dir, "/a", "0.10.2", None, instant(1_700_000_000, 0)).unwrap();
    write_marker(&dir, "/b", "0.10.3", None, instant(1_700_000_001, 0)).unwrap();

    let mut entries: Vec<String> = fs::read_dir(&dir)
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_string_lossy().to_string())
        .collect();
    entries.sort();
    assert_eq!(entries, vec![APP_STATE_FILE_NAME]);

    let raw = fs::read_to_string(marker_path(&dir)).unwrap();
    assert!(raw.ends_with('\n'));
    let parsed: AppStateMarker = serde_json::from_str(&raw).unwrap();
    assert_eq!(parsed.app_path, "/b");

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = fs::metadata(marker_path(&dir))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
    }
}

#[test]
fn marker_json_keys_match_the_go_reader_tags() {
    let dir = scratch_dir("wire-keys");
    write_marker(
        &dir,
        "/a",
        "0.10.3",
        Some("npm-bootstrap"),
        instant(1_700_000_000, 0),
    )
    .unwrap();
    let raw = fs::read_to_string(marker_path(&dir)).unwrap();
    for key in [
        "\"schemaVersion\"",
        "\"appPath\"",
        "\"version\"",
        "\"installedAt\"",
        "\"lastReconciledAt\"",
        "\"installSource\"",
    ] {
        assert!(raw.contains(key), "missing {key} in {raw}");
    }
}

#[test]
fn parse_installed_via_mirrors_main_ts() {
    let args = vec![
        "--installed-via=npm-bootstrap".to_string(),
        "--other".to_string(),
    ];
    assert_eq!(parse_installed_via(&args).as_deref(), Some("npm-bootstrap"));
    assert_eq!(parse_installed_via(&[]), None);
    assert_eq!(parse_installed_via(&["--other".to_string()]), None);
    assert_eq!(
        parse_installed_via(&["--installed-via=".to_string()]),
        Some(String::new())
    );
    assert_eq!(
        parse_installed_via(&["--installed-via=a=b".to_string()]).as_deref(),
        Some("a=b")
    );
    let doubled = vec![
        "--installed-via=first".to_string(),
        "--installed-via=second".to_string(),
    ];
    assert_eq!(parse_installed_via(&doubled).as_deref(), Some("first"));
}

#[test]
#[cfg(target_os = "macos")]
fn resolve_bundle_path_walks_to_the_enclosing_bundle() {
    let root = scratch_dir("strict-bundle");
    let bundle = root.join("Operator.app");
    let exec = bundle.join("Contents/MacOS/operator");
    fs::create_dir_all(exec.parent().unwrap()).unwrap();
    write_executable(&exec);
    fs::write(
        bundle.join("Contents/Info.plist"),
        real_bundle_plist("1.2.3"),
    )
    .unwrap();

    assert_eq!(resolve_bundle_path(&exec), Some(bundle));

    let fake = root.join("Fake.app/Contents/MacOS/operator");
    fs::create_dir_all(fake.parent().unwrap()).unwrap();
    fs::write(&fake, b"binary").unwrap();
    assert_eq!(resolve_bundle_path(&fake), None);

    let helper = root.join("Nested.app/Contents/Helpers/operator");
    fs::create_dir_all(helper.parent().unwrap()).unwrap();
    fs::write(&helper, b"binary").unwrap();
    fs::write(root.join("Nested.app/Contents/Info.plist"), b"<plist/>").unwrap();
    assert_eq!(resolve_bundle_path(&helper), None);
}

#[test]
#[cfg(not(target_os = "macos"))]
fn resolve_bundle_path_keeps_the_executable_on_win_linux() {
    let exec = Path::new("/opt/operator/bin/operator");
    assert_eq!(
        resolve_bundle_path(exec),
        Some(PathBuf::from("/opt/operator/bin/operator"))
    );
}

#[test]
fn format_timestamp_uses_utc_millis_z() {
    assert_eq!(
        format_timestamp(instant(1_700_000_000, 250_000_000)),
        "2023-11-14T22:13:20.250Z"
    );
}

fn relocation_inputs<'a>(
    in_applications_folder: bool,
    installed_present: bool,
    installed_version: Option<&'a str>,
    running_version: &'a str,
) -> RelocationInputs<'a> {
    RelocationInputs {
        in_applications_folder,
        installed_present,
        installed_version,
        running_version,
    }
}

#[test]
fn relocation_stays_inside_an_applications_folder() {
    assert_eq!(
        decide_relocation(relocation_inputs(true, false, None, "0.10.3")),
        RelocationAction::Stay
    );
    assert_eq!(
        decide_relocation(relocation_inputs(true, true, Some("0.0.1"), "0.10.3")),
        RelocationAction::Stay
    );
}

#[test]
fn relocation_relocates_when_no_install_exists() {
    assert_eq!(
        decide_relocation(relocation_inputs(false, false, None, "0.10.3")),
        RelocationAction::Relocate
    );
}

#[test]
fn relocation_hands_off_to_equal_or_newer_install() {
    assert_eq!(
        decide_relocation(relocation_inputs(false, true, Some("0.10.3"), "0.10.3")),
        RelocationAction::Handoff
    );
    assert_eq!(
        decide_relocation(relocation_inputs(false, true, Some("0.11.0"), "0.10.3")),
        RelocationAction::Handoff
    );
}

#[test]
fn relocation_moves_over_a_strictly_older_install() {
    assert_eq!(
        decide_relocation(relocation_inputs(false, true, Some("0.10.2"), "0.10.3")),
        RelocationAction::Relocate
    );
    assert_eq!(
        decide_relocation(relocation_inputs(false, true, Some("0.9.9"), "0.10.0")),
        RelocationAction::Relocate
    );
    assert_eq!(
        decide_relocation(relocation_inputs(false, true, Some("0.10.2"), "0.10.10")),
        RelocationAction::Relocate
    );
    assert_eq!(
        decide_relocation(relocation_inputs(
            false,
            true,
            Some("1.2.3-beta.1"),
            "1.2.3"
        )),
        RelocationAction::Relocate
    );
}

#[test]
fn relocation_never_overwrites_an_unreadable_version() {
    assert_eq!(
        decide_relocation(relocation_inputs(false, true, None, "0.10.3")),
        RelocationAction::Stay
    );
    assert_eq!(
        decide_relocation(relocation_inputs(false, true, Some(""), "0.10.3")),
        RelocationAction::Stay
    );
    assert_eq!(
        decide_relocation(relocation_inputs(false, true, Some("beta"), "0.10.3")),
        RelocationAction::Stay
    );
    assert_eq!(
        decide_relocation(relocation_inputs(false, true, Some("1.2"), "0.10.3")),
        RelocationAction::Stay
    );
    assert_eq!(
        decide_relocation(relocation_inputs(
            false,
            true,
            Some("0.10.3"),
            "not-a-version"
        )),
        RelocationAction::Stay
    );
}

#[test]
fn installed_bundle_path_joins_applications_with_the_bundle_name() {
    assert_eq!(
        installed_bundle_path(Path::new("/Users/me/Downloads/Operator.app")),
        PathBuf::from("/Applications/Operator.app")
    );
}

#[test]
fn read_bundle_version_parses_xml_plist_value() {
    let dir = scratch_dir("plist-valid");
    fs::create_dir_all(dir.join("Contents")).unwrap();
    fs::write(
        dir.join("Contents").join("Info.plist"),
        "<?xml version=\"1.0\"?>\n<plist>\n<dict>\n\
         <key>CFBundleShortVersionString</key>\n\t <string>1.2.3</string>\n\
         </dict>\n</plist>\n",
    )
    .unwrap();
    assert_eq!(read_bundle_version(&dir).as_deref(), Some("1.2.3"));
}

#[test]
fn read_bundle_version_degrades_to_none() {
    let missing = scratch_dir("plist-missing");
    assert_eq!(read_bundle_version(&missing), None);

    let empty_value = scratch_dir("plist-empty-value");
    fs::create_dir_all(empty_value.join("Contents")).unwrap();
    fs::write(
        empty_value.join("Contents").join("Info.plist"),
        "<key>CFBundleShortVersionString</key><string></string>",
    )
    .unwrap();
    assert_eq!(read_bundle_version(&empty_value), None);

    let markup_value = scratch_dir("plist-markup-value");
    fs::create_dir_all(markup_value.join("Contents")).unwrap();
    fs::write(
        markup_value.join("Contents").join("Info.plist"),
        "<key>CFBundleShortVersionString</key><string>a<b</string>",
    )
    .unwrap();
    assert_eq!(read_bundle_version(&markup_value), None);

    let wrong_gap = scratch_dir("plist-wrong-gap");
    fs::create_dir_all(wrong_gap.join("Contents")).unwrap();
    fs::write(
        wrong_gap.join("Contents").join("Info.plist"),
        "<key>CFBundleShortVersionString</key><other/><string>1.2.3</string>",
    )
    .unwrap();
    assert_eq!(read_bundle_version(&wrong_gap), None);

    let no_key = scratch_dir("plist-no-key");
    fs::create_dir_all(no_key.join("Contents")).unwrap();
    fs::write(
        no_key.join("Contents").join("Info.plist"),
        "<key>Other</key>",
    )
    .unwrap();
    assert_eq!(read_bundle_version(&no_key), None);
}

#[test]
fn real_bundle_validation_requires_app_layout_binary_and_exact_version() {
    let root = scratch_dir("real-bundle-validation");
    let bundle = root.join("Operator.app");
    fs::create_dir_all(bundle.join("Contents/MacOS")).unwrap();
    write_executable(&bundle.join("Contents/MacOS/operator"));
    fs::write(
        bundle.join("Contents/Info.plist"),
        real_bundle_plist("1.2.3"),
    )
    .unwrap();

    assert!(valid_macos_bundle(&bundle, "1.2.3"));
    assert!(!valid_macos_bundle(&bundle, "1.2.4"));
    assert!(!valid_macos_bundle(&root.join("Operator"), "1.2.3"));
    fs::write(
        bundle.join("Contents/Info.plist"),
        real_bundle_plist("1.2.3").replace("dev.operator.desktop", "other.app"),
    )
    .unwrap();
    assert!(!valid_macos_bundle(&bundle, "1.2.3"));
    fs::write(
        bundle.join("Contents/Info.plist"),
        real_bundle_plist("1.2.3"),
    )
    .unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let executable = bundle.join("Contents/MacOS/operator");
        let mut permissions = fs::metadata(&executable).unwrap().permissions();
        permissions.set_mode(0o644);
        fs::set_permissions(&executable, permissions).unwrap();
        assert!(!valid_macos_bundle(&bundle, "1.2.3"));
    }
    fs::remove_file(bundle.join("Contents/MacOS/operator")).unwrap();
    assert!(!valid_macos_bundle(&bundle, "1.2.3"));
}

#[test]
fn inspect_installed_bundle_reports_an_absent_install() {
    let root = scratch_dir("inspect-absent");
    let running = root.join("downloads/Operator.app");
    let applications = root.join("Applications");

    let (present, version) = inspect_installed_bundle_in(&running, &applications);
    assert!(!present);
    assert_eq!(version, None);
}

#[test]
fn inspect_installed_bundle_reads_a_present_bundle() {
    let root = scratch_dir("inspect-running");
    let running = root.join("downloads/Operator.app");
    let applications = root.join("Applications");
    fs::create_dir_all(running.join("Contents")).unwrap();
    fs::write(
        running.join("Contents").join("Info.plist"),
        "<key>CFBundleShortVersionString</key><string>9.9.8</string>",
    )
    .unwrap();
    let installed = installed_bundle_path_in(&running, &applications);
    fs::create_dir_all(&installed).unwrap();

    let (present, version) = inspect_installed_bundle_in(&running, &applications);
    assert!(present);
    assert_eq!(version.as_deref(), None);

    fs::create_dir_all(installed.join("Contents")).unwrap();
    fs::write(
        installed.join("Contents").join("Info.plist"),
        real_bundle_plist("9.9.9"),
    )
    .unwrap();
    let (present, version) = inspect_installed_bundle_in(&running, &applications);
    assert!(present);
    assert_eq!(version, None);

    fs::create_dir_all(installed.join("Contents/MacOS")).unwrap();
    write_executable(&installed.join("Contents/MacOS/operator"));
    let (present, version) = inspect_installed_bundle_in(&running, &applications);
    assert!(present);
    assert_eq!(version.as_deref(), Some("9.9.9"));
}

#[test]
fn applications_folder_detection_covers_system_and_user_roots() {
    let home = Path::new("/Users/me");
    assert!(is_in_applications_folder(
        Path::new("/Applications/Operator.app"),
        home
    ));
    assert!(is_in_applications_folder(
        Path::new("/Applications/Nested/Operator.app"),
        home
    ));
    assert!(is_in_applications_folder(
        Path::new("/Users/me/Applications/Operator.app"),
        home
    ));
    assert!(!is_in_applications_folder(
        Path::new("/Users/me/Downloads/Operator.app"),
        home
    ));
    assert!(!is_in_applications_folder(
        Path::new("/ApplicationsFoo/Operator.app"),
        home
    ));
}

fn exists_in<'a>(names: &'a [&'a str]) -> impl FnMut(&Path) -> bool + 'a {
    move |path: &Path| names.contains(&path.file_name().unwrap().to_str().unwrap())
}

#[test]
fn trash_destination_prefers_the_plain_bundle_name() {
    let destination = trashed_bundle_destination(Path::new("/Users/me"), "Operator.app", |_| false);
    assert_eq!(
        destination,
        Some(PathBuf::from("/Users/me/.Trash/Operator.app"))
    );
}

#[test]
fn trash_destination_uniquifies_collisions_like_finder() {
    let taken = exists_in(&["Operator.app"]);
    assert_eq!(
        trashed_bundle_destination(Path::new("/Users/me"), "Operator.app", taken),
        Some(PathBuf::from("/Users/me/.Trash/Operator 2.app"))
    );

    let taken = exists_in(&["Operator.app", "Operator 2.app", "Operator 3.app"]);
    assert_eq!(
        trashed_bundle_destination(Path::new("/Users/me"), "Operator.app", taken),
        Some(PathBuf::from("/Users/me/.Trash/Operator 4.app"))
    );
}

#[test]
fn trash_destination_uniquifies_names_without_extensions() {
    let taken = exists_in(&["operator"]);
    assert_eq!(
        trashed_bundle_destination(Path::new("/Users/me"), "operator", taken),
        Some(PathBuf::from("/Users/me/.Trash/operator 2"))
    );
}

#[test]
fn trash_destination_declines_when_every_name_is_taken() {
    let mut all_taken: Vec<String> = vec!["Operator.app".to_string()];
    for suffix in 2..=100 {
        all_taken.push(format!("Operator {suffix}.app"));
    }
    let refs: Vec<&str> = all_taken.iter().map(String::as_str).collect();
    let taken = exists_in(&refs);
    assert_eq!(
        trashed_bundle_destination(Path::new("/Users/me"), "Operator.app", taken),
        None
    );
}

#[test]
fn trash_destination_declines_unusable_names() {
    assert_eq!(
        trashed_bundle_destination(Path::new("/Users/me"), "", |_| false),
        None
    );
}

struct FakeRelocationExecutor {
    bundles: HashMap<PathBuf, String>,
    fail_copy: bool,
    fail_install_move: bool,
    fail_rollback: bool,
    invalid_path: Option<PathBuf>,
    launch_result: bool,
}

impl RelocationExecutor for FakeRelocationExecutor {
    fn exists(&self, path: &Path) -> bool {
        self.bundles.contains_key(path)
    }

    fn move_path(&mut self, from: &Path, to: &Path) -> io::Result<()> {
        if self.fail_rollback && from.to_string_lossy().contains("/.Trash/") {
            return Err(io::Error::other("rollback failed"));
        }
        if self.fail_install_move
            && from
                .file_name()
                .is_some_and(|name| name.to_string_lossy().contains("operator-stage"))
        {
            return Err(io::Error::other("install move failed"));
        }
        let value = self
            .bundles
            .remove(from)
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, from.display().to_string()))?;
        self.bundles.insert(to.to_path_buf(), value);
        Ok(())
    }

    fn copy_bundle(&mut self, from: &Path, to: &Path) -> io::Result<()> {
        if self.fail_copy {
            return Err(io::Error::other("copy failed"));
        }
        let value =
            self.bundles.get(from).cloned().ok_or_else(|| {
                io::Error::new(io::ErrorKind::NotFound, from.display().to_string())
            })?;
        self.bundles.insert(to.to_path_buf(), value);
        Ok(())
    }

    fn valid_bundle(&self, path: &Path, expected_version: &str) -> bool {
        self.invalid_path.as_deref() != Some(path)
            && self
                .bundles
                .get(path)
                .is_some_and(|value| value == expected_version)
    }

    fn remove_staged(&mut self, path: &Path) -> io::Result<()> {
        self.bundles.remove(path);
        Ok(())
    }

    fn launch_bundle(&mut self, _path: &Path) -> bool {
        self.launch_result
    }
}

fn fake_relocation(
    running: &Path,
    installed: &Path,
    running_version: &str,
    installed_version: Option<&str>,
) -> FakeRelocationExecutor {
    let mut bundles = HashMap::from([(running.to_path_buf(), running_version.to_string())]);
    if let Some(version) = installed_version {
        bundles.insert(installed.to_path_buf(), version.to_string());
    }
    FakeRelocationExecutor {
        bundles,
        fail_copy: false,
        fail_install_move: false,
        fail_rollback: false,
        invalid_path: None,
        launch_result: true,
    }
}

fn held_relocation_lock(name: &str) -> (ScratchDir, RelocationLock) {
    let root = scratch_dir(name);
    let lock = RelocationLock::try_acquire(&root)
        .expect("relocation lock acquisition should work")
        .expect("uncontended relocation lock acquisition should succeed");
    (root, lock)
}

#[test]
fn relocation_copy_failure_leaves_the_installed_bundle_untouched() {
    let (_state_root, lock) = held_relocation_lock("copy-failure-lock");
    let running = Path::new("/Downloads/Operator.app");
    let installed = Path::new("/Applications/Operator.app");
    let mut executor = fake_relocation(running, installed, "2.0.0", Some("1.0.0"));
    executor.fail_copy = true;

    assert!(execute_relocation(
        &mut executor,
        Path::new("/Users/me"),
        running,
        installed,
        "2.0.0",
        "copy-failure",
        &lock,
    )
    .is_err());
    assert_eq!(
        executor.bundles.get(installed).map(String::as_str),
        Some("1.0.0")
    );
    assert!(!executor
        .bundles
        .contains_key(&staged_bundle_path(installed, "copy-failure")));
}

#[test]
fn relocation_install_failure_rolls_the_old_bundle_back() {
    let (_state_root, lock) = held_relocation_lock("install-failure-lock");
    let running = Path::new("/Downloads/Operator.app");
    let installed = Path::new("/Applications/Operator.app");
    let mut executor = fake_relocation(running, installed, "2.0.0", Some("1.0.0"));
    executor.fail_install_move = true;

    assert!(execute_relocation(
        &mut executor,
        Path::new("/Users/me"),
        running,
        installed,
        "2.0.0",
        "install-failure",
        &lock,
    )
    .is_err());
    assert_eq!(
        executor.bundles.get(installed).map(String::as_str),
        Some("1.0.0")
    );
    assert!(!executor
        .bundles
        .contains_key(&staged_bundle_path(installed, "install-failure")));
}

#[test]
fn relocation_failed_rollback_preserves_the_staged_recovery_bundle() {
    let (_state_root, lock) = held_relocation_lock("rollback-failure-lock");
    let running = Path::new("/Downloads/Operator.app");
    let installed = Path::new("/Applications/Operator.app");
    let stage = staged_bundle_path(installed, "rollback-failure");
    let mut executor = fake_relocation(running, installed, "2.0.0", Some("1.0.0"));
    executor.invalid_path = Some(installed.to_path_buf());
    executor.fail_rollback = true;

    assert!(execute_relocation(
        &mut executor,
        Path::new("/Users/me"),
        running,
        installed,
        "2.0.0",
        "rollback-failure",
        &lock,
    )
    .is_err());
    assert_eq!(
        executor.bundles.get(&stage).map(String::as_str),
        Some("2.0.0")
    );
    assert!(executor
        .bundles
        .iter()
        .any(|(path, version)| path.to_string_lossy().contains("/.Trash/") && version == "1.0.0"));
}

#[test]
fn relocation_final_validation_failure_restores_the_old_bundle() {
    let (_state_root, lock) = held_relocation_lock("validation-failure-lock");
    let running = Path::new("/Downloads/Operator.app");
    let installed = Path::new("/Applications/Operator.app");
    let stage = staged_bundle_path(installed, "validation-failure");
    let mut executor = fake_relocation(running, installed, "2.0.0", Some("1.0.0"));
    executor.invalid_path = Some(installed.to_path_buf());

    assert!(execute_relocation(
        &mut executor,
        Path::new("/Users/me"),
        running,
        installed,
        "2.0.0",
        "validation-failure",
        &lock,
    )
    .is_err());
    assert_eq!(
        executor.bundles.get(installed).map(String::as_str),
        Some("1.0.0")
    );
    assert!(!executor.bundles.contains_key(&stage));
}

#[test]
fn relocation_relaunch_failure_keeps_the_current_process_running() {
    let (_state_root, lock) = held_relocation_lock("launch-failure-lock");
    let running = Path::new("/Downloads/Operator.app");
    let installed = Path::new("/Applications/Operator.app");
    let mut executor = fake_relocation(running, installed, "2.0.0", Some("1.0.0"));
    executor.launch_result = false;

    let relaunched = execute_relocation(
        &mut executor,
        Path::new("/Users/me"),
        running,
        installed,
        "2.0.0",
        "launch-failure",
        &lock,
    )
    .unwrap();

    assert!(!relaunched);
    assert_eq!(
        executor.bundles.get(installed).map(String::as_str),
        Some("2.0.0")
    );
}

#[test]
fn bundle_validation_requires_matching_cf_bundle_name() {
    let root = scratch_dir("bundle-name");
    let bundle = root.join("Operator.app");
    fs::create_dir_all(bundle.join("Contents/MacOS")).unwrap();
    write_executable(&bundle.join("Contents/MacOS/operator"));
    let plist_with_name = |name: &str| {
        format!(
            "<key>CFBundleExecutable</key><string>operator</string><key>CFBundleIdentifier</key><string>dev.operator.desktop</string><key>CFBundleName</key><string>{name}</string><key>CFBundleShortVersionString</key><string>1.2.3</string>"
        )
    };

    fs::write(
        bundle.join("Contents/Info.plist"),
        plist_with_name("Operator"),
    )
    .unwrap();
    assert!(macos_bundle_layout_valid(&bundle));

    fs::write(
        bundle.join("Contents/Info.plist"),
        plist_with_name("SomethingElse"),
    )
    .unwrap();
    assert!(!macos_bundle_layout_valid(&bundle));

    fs::write(
        bundle.join("Contents/Info.plist"),
        plist_with_name("Operator").replace("<key>CFBundleName</key><string>Operator</string>", ""),
    )
    .unwrap();
    assert!(!macos_bundle_layout_valid(&bundle));
}

fn cargo_manifest_version(manifest: &str) -> Option<String> {
    let mut in_package_section = false;
    for line in manifest.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') {
            in_package_section = trimmed == "[package]";
            continue;
        }
        if !in_package_section {
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("version") {
            if let Some(value) = rest.trim_start().strip_prefix('=') {
                let value = value.trim();
                if value.starts_with('"') && value.len() >= 2 && value.ends_with('"') {
                    return Some(value[1..value.len() - 1].to_string());
                }
            }
        }
    }
    None
}

fn package_json_version(json: &str) -> Option<String> {
    serde_json::from_str::<serde_json::Value>(json)
        .ok()?
        .get("version")?
        .as_str()
        .map(str::to_string)
}

#[test]
fn version_coupling_guard_detects_diverged_manifest_fixtures() {
    let cargo = "[package]\nname = \"operator\"\nversion = \"0.10.3\"\n\n[dependencies]\nsemver = \"=1.0.28\"\n";
    let matching = r#"{"name":"operator","productName":"Operator","version":"0.10.3"}"#;
    let diverged = r#"{"name":"operator","version":"0.10.4"}"#;
    let section_only = "[dependencies]\nversion = \"9.9.9\"\n";

    assert_eq!(
        cargo_manifest_version(cargo),
        package_json_version(matching)
    );
    assert_ne!(
        cargo_manifest_version(cargo),
        package_json_version(diverged)
    );
    assert_eq!(cargo_manifest_version(section_only), None);
    assert!(package_json_version("{not json").is_none());
    assert!(package_json_version(r#"{"name":"operator"}"#).is_none());
}

#[test]
fn cargo_toml_and_package_json_versions_stay_coupled() {
    let manifest_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let manifest = fs::read_to_string(manifest_root.join("Cargo.toml")).unwrap();
    let package_json = fs::read_to_string(manifest_root.join("../package.json")).unwrap();

    let cargo_version =
        cargo_manifest_version(&manifest).expect("Cargo.toml declares a [package] version");
    let package_version =
        package_json_version(&package_json).expect("package.json declares a version");

    assert_eq!(cargo_version, package_version);
}

fn write_real_bundle(bundle: &Path, version: &str) {
    fs::create_dir_all(bundle.join("Contents/MacOS")).unwrap();
    write_executable(&bundle.join("Contents/MacOS/operator"));
    fs::write(
        bundle.join("Contents/Info.plist"),
        real_bundle_plist(version),
    )
    .unwrap();
}

fn copy_bundle_tree(from: &Path, to: &Path) -> io::Result<()> {
    fs::create_dir_all(to)?;
    for entry in fs::read_dir(from)? {
        let entry = entry?;
        let target = to.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_bundle_tree(&entry.path(), &target)?;
        } else {
            fs::copy(entry.path(), &target)?;
        }
    }
    Ok(())
}

struct FsRelocationExecutor;

impl RelocationExecutor for FsRelocationExecutor {
    fn exists(&self, path: &Path) -> bool {
        path.exists()
    }

    fn move_path(&mut self, from: &Path, to: &Path) -> io::Result<()> {
        fs::rename(from, to)
    }

    fn copy_bundle(&mut self, from: &Path, to: &Path) -> io::Result<()> {
        copy_bundle_tree(from, to)
    }

    fn valid_bundle(&self, path: &Path, expected_version: &str) -> bool {
        valid_macos_bundle(path, expected_version)
    }

    fn remove_staged(&mut self, path: &Path) -> io::Result<()> {
        match fs::remove_dir_all(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
    }

    fn launch_bundle(&mut self, _path: &Path) -> bool {
        true
    }
}

fn directory_names(dir: &Path) -> Vec<String> {
    let mut names: Vec<String> = fs::read_dir(dir)
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_string_lossy().to_string())
        .collect();
    names.sort();
    names
}

#[test]
fn relocation_lock_lives_only_beneath_the_state_root() {
    let root = scratch_dir("lock-location");
    write_real_bundle(&root.join("Applications/Operator.app"), "1.0.0");

    let acquired = RelocationLock::try_acquire(&root).unwrap();
    assert!(acquired.is_some());

    assert_eq!(
        RelocationLock::lock_path(&root),
        root.join("relocation.lock")
    );
    assert_eq!(
        directory_names(&root),
        vec!["Applications", "relocation.lock"]
    );

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = fs::metadata(root.join("relocation.lock"))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
    }
}

#[test]
fn relocation_lock_is_released_when_the_guard_drops() {
    let root = scratch_dir("lock-release");
    let lock = RelocationLock::try_acquire(&root).unwrap().unwrap();

    assert!(RelocationLock::try_acquire(&root).unwrap().is_none());

    drop(lock);

    assert!(RelocationLock::try_acquire(&root).unwrap().is_some());
}

#[test]
fn contended_second_instance_declines_without_touching_either_bundle() {
    let root = scratch_dir("lock-contended");
    let running = root.join("Downloads/Operator.app");
    let installed = root.join("Applications/Operator.app");
    write_real_bundle(&running, "2.0.0");
    write_real_bundle(&installed, "1.0.0");

    let holder = RelocationLock::try_acquire(&root).unwrap();
    assert!(holder.is_some());
    assert!(RelocationLock::try_acquire(&root).unwrap().is_none());

    assert_eq!(read_bundle_version(&running).as_deref(), Some("2.0.0"));
    assert_eq!(read_bundle_version(&installed).as_deref(), Some("1.0.0"));
    assert_eq!(
        directory_names(installed.parent().unwrap()),
        vec!["Operator.app"]
    );

    drop(holder);
    assert!(RelocationLock::try_acquire(&root).unwrap().is_some());
}

#[test]
fn relocation_lock_excludes_until_the_holder_releases_it() {
    let root = scratch_dir("lock-handshake");
    let contender_root = root.to_path_buf();
    let first = RelocationLock::try_acquire(&root).unwrap();
    assert!(first.is_some());

    let (ready_tx, ready_rx) = mpsc::channel();
    let (go_tx, go_rx) = mpsc::channel();
    let (attempt_tx, attempt_rx) = mpsc::channel();
    let contender = thread::spawn(move || {
        ready_tx.send(()).unwrap();
        go_rx.recv().unwrap();
        let declined_while_held = RelocationLock::try_acquire(&contender_root)
            .unwrap()
            .is_none();
        attempt_tx.send(declined_while_held).unwrap();
    });

    ready_rx.recv().unwrap();
    go_tx.send(()).unwrap();
    let declined_while_held = attempt_rx.recv().unwrap();

    drop(first);
    let reacquired = RelocationLock::try_acquire(&root).unwrap().is_some();
    contender.join().unwrap();

    assert!(declined_while_held);
    assert!(reacquired);
}

#[test]
fn concurrent_relocations_serialize_or_decline_without_errors() {
    const RACERS: usize = 4;
    let root = scratch_dir("lock-race");
    let running = root.join("Downloads/Operator.app");
    let applications = root.join("Applications");
    let installed = applications.join("Operator.app");
    write_real_bundle(&running, "2.0.0");
    write_real_bundle(&installed, "1.0.0");
    fs::create_dir_all(root.join("home/.Trash")).unwrap();

    enum Attempt {
        Completed,
        Declined,
        Failed(String),
    }

    let barrier = Barrier::new(RACERS);
    let outcomes: Vec<Attempt> = thread::scope(|scope| {
        let handles: Vec<_> = (0..RACERS)
            .map(|index| {
                let barrier = &barrier;
                let root = &root;
                let running = running.clone();
                let installed = installed.clone();
                scope.spawn(move || {
                    barrier.wait();
                    match RelocationLock::try_acquire(root) {
                        Err(error) => Attempt::Failed(format!("acquire: {error}")),
                        Ok(None) => Attempt::Declined,
                        Ok(Some(lock)) => {
                            let mut executor = FsRelocationExecutor;
                            match execute_relocation(
                                &mut executor,
                                &root.join("home"),
                                &running,
                                &installed,
                                "2.0.0",
                                &format!("race-{index}"),
                                &lock,
                            ) {
                                Ok(_) => Attempt::Completed,
                                Err(error) => Attempt::Failed(error.to_string()),
                            }
                        }
                    }
                })
            })
            .collect();
        handles
            .into_iter()
            .map(|handle| handle.join().unwrap())
            .collect()
    });

    let mut completed = 0;
    let mut declined = 0;
    let mut failures: Vec<String> = Vec::new();
    for outcome in &outcomes {
        match outcome {
            Attempt::Completed => completed += 1,
            Attempt::Declined => declined += 1,
            Attempt::Failed(error) => failures.push(error.clone()),
        }
    }
    assert!(
        failures.is_empty(),
        "no racer may fail mid-flight: {failures:?}"
    );
    assert_eq!(completed + declined, RACERS);
    assert!(completed >= 1);

    assert!(valid_macos_bundle(&installed, "2.0.0"));
    assert_eq!(read_bundle_version(&running).as_deref(), Some("2.0.0"));
    assert_eq!(directory_names(&applications), vec!["Operator.app"]);
}

#[test]
fn killed_holder_releases_the_relocation_lock_for_future_launches() {
    const PROBE_VAR: &str = "OPERATOR_RELOCATION_LOCK_PROBE_ROOT";
    if let Some(probe_root) = env::var_os(PROBE_VAR) {
        let acquired = RelocationLock::try_acquire(Path::new(&probe_root))
            .expect("probe acquisition should work")
            .is_some();
        assert!(acquired);
        std::process::exit(0);
    }

    let probe_root = std::env::temp_dir().join(format!(
        "operator-app-state-test-lock-crash-{}",
        uuid::Uuid::new_v4().simple()
    ));
    fs::create_dir_all(&probe_root).unwrap();
    let status = Command::new(env::current_exe().unwrap())
        .args([
            "--exact",
            "app_state_tests::killed_holder_releases_the_relocation_lock_for_future_launches",
        ])
        .env(PROBE_VAR, &probe_root)
        .status()
        .unwrap();
    let reacquired = RelocationLock::try_acquire(&probe_root).unwrap().is_some();
    let _ = fs::remove_dir_all(&probe_root);

    assert_eq!(status.code(), Some(0));
    assert!(reacquired);
}
