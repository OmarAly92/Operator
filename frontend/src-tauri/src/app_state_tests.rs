use std::fs;
use std::path::{Path, PathBuf};

use chrono::{TimeZone, Utc};
use serde_json::json;

use crate::app_state::{
    format_timestamp, parse_installed_via, read_marker, resolve_bundle_path, write_marker,
    AppStateMarker, MigrationReport, MigrationState, APP_STATE_FILE_NAME, SCHEMA_VERSION,
};
use crate::relocation::{
    decide_relocation, inspect_installed_bundle, installed_bundle_path, is_in_applications_folder,
    read_bundle_version, trashed_bundle_destination, RelocationAction, RelocationInputs,
};

fn scratch_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "operator-app-state-test-{}-{}",
        name,
        std::process::id()
    ));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn instant(seconds: i64, nanos: u32) -> chrono::DateTime<Utc> {
    Utc.timestamp_opt(seconds, nanos).single().unwrap()
}

fn marker_path(state_dir: &Path) -> PathBuf {
    state_dir.join(APP_STATE_FILE_NAME)
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
    let exec = Path::new("/Applications/Operator.app/Contents/MacOS/operator");
    assert_eq!(
        resolve_bundle_path(exec),
        PathBuf::from("/Applications/Operator.app")
    );
}

#[test]
#[cfg(not(target_os = "macos"))]
fn resolve_bundle_path_keeps_the_executable_on_win_linux() {
    let exec = Path::new("/opt/operator/bin/operator");
    assert_eq!(
        resolve_bundle_path(exec),
        PathBuf::from("/opt/operator/bin/operator")
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
fn inspect_installed_bundle_reports_an_absent_install() {
    let running = Path::new("/Users/me/Downloads/Operator-State-Audit.app");

    let (present, version) = inspect_installed_bundle(running);
    assert_eq!(present, false);
    assert_eq!(version, None);
}

#[test]
fn inspect_installed_bundle_reads_a_present_bundle() {
    let running = scratch_dir("inspect-running");
    fs::create_dir_all(running.join("Contents")).unwrap();
    fs::write(
        running.join("Contents").join("Info.plist"),
        "<key>CFBundleShortVersionString</key><string>9.9.8</string>",
    )
    .unwrap();
    let installed = installed_bundle_path(&running);
    fs::create_dir_all(&installed).unwrap();

    let (present, version) = inspect_installed_bundle(&running);
    assert_eq!(present, true);
    assert_eq!(version.as_deref(), None);

    fs::create_dir_all(installed.join("Contents")).unwrap();
    fs::write(
        installed.join("Contents").join("Info.plist"),
        "<key>CFBundleShortVersionString</key><string>9.9.9</string>",
    )
    .unwrap();
    let (present, version) = inspect_installed_bundle(&running);
    assert_eq!(present, true);
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
