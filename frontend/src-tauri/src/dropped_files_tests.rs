use std::fs;
use std::path::PathBuf;

use crate::dropped_files::{
    drop_dir, prune_stale, remove_staged, sanitize_basename, stage, RemoveError, StageError,
    MAX_INPUT_BYTES,
};

fn temp_root(tag: &str) -> PathBuf {
    let root = std::env::temp_dir().join(format!(
        "operator-dropped-files-{tag}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    fs::create_dir_all(&root).unwrap();
    root
}

const DAY_MS: u64 = 24 * 60 * 60 * 1000;
const NOW_MS: u64 = 1_758_000_000_000;

#[test]
fn sanitizes_path_traversal_and_special_characters() {
    assert_eq!(sanitize_basename("../../etc/passwd"), "passwd");
    assert_eq!(sanitize_basename("a b/c.txt"), "c.txt");
    assert_eq!(
        sanitize_basename("..\\..\\win secret file.txt"),
        "win_secret_file.txt"
    );
    assert_eq!(
        sanitize_basename("report final v2.pdf"),
        "report_final_v2.pdf"
    );
    assert_eq!(
        sanitize_basename("keeps-dots_and.dashes.txt"),
        "keeps-dots_and.dashes.txt"
    );
}

#[test]
fn collapses_invalid_runs_into_single_underscores() {
    assert_eq!(sanitize_basename("a  !!  b.txt"), "a_b.txt");
    assert_eq!(sanitize_basename("!!!leading"), "_leading");
}

#[test]
fn falls_back_when_the_name_is_empty_or_unsafe() {
    assert_eq!(sanitize_basename(""), "dropped");
    assert_eq!(sanitize_basename("///"), "dropped");
    assert_eq!(sanitize_basename("???"), "_");
}

#[test]
fn truncates_overlong_sanitized_names() {
    let long = "x".repeat(400);
    let sanitized = sanitize_basename(&long);
    assert!(sanitized.chars().count() <= 80);
    assert!(sanitized.starts_with('x'));
}

#[test]
fn stages_bytes_under_the_owned_drop_dir() {
    let root = temp_root("stage");
    let path = stage(&root, "notes today.txt", b"hello drops", "aaaa1111", NOW_MS).unwrap();

    assert_eq!(path.parent(), Some(drop_dir(&root).as_path()));
    assert_eq!(
        path.file_name().unwrap().to_str().unwrap(),
        format!("{NOW_MS}-aaaa1111-notes_today.txt")
    );
    assert_eq!(fs::read(&path).unwrap(), b"hello drops");
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn rejects_inputs_above_the_64_mib_limit() {
    let root = temp_root("limit");
    let bytes = vec![0u8; MAX_INPUT_BYTES + 1];

    match stage(&root, "big.bin", &bytes, "aaaa1111", NOW_MS) {
        Err(StageError::TooLarge { size }) => assert_eq!(size, bytes.len()),
        other => panic!("expected the 64 MiB rejection, got {other:?}"),
    }
    assert!(!drop_dir(&root).exists());
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn accepts_inputs_at_exactly_the_64_mib_limit() {
    let root = temp_root("exact-limit");
    let bytes = vec![7u8; MAX_INPUT_BYTES];
    let path = stage(&root, "exact.bin", &bytes, "aaaa1111", NOW_MS).unwrap();
    assert_eq!(fs::read(&path).unwrap().len(), MAX_INPUT_BYTES);
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn generates_collision_resistant_names_for_identical_basenames() {
    let root = temp_root("collision");
    let first = stage(&root, "same name.txt", b"first", "aaaa1111", NOW_MS).unwrap();
    let second = stage(&root, "same name.txt", b"second", "bbbb2222", NOW_MS).unwrap();

    assert_ne!(first, second);
    assert_eq!(fs::read(&first).unwrap(), b"first");
    assert_eq!(fs::read(&second).unwrap(), b"second");
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn staging_leaves_no_partial_temporaries_behind() {
    let root = temp_root("atomic");
    stage(&root, "done.bin", b"payload", "aaaa1111", NOW_MS).unwrap();

    let leftovers: Vec<_> = fs::read_dir(drop_dir(&root))
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_string_lossy().to_string())
        .filter(|name| !name.ends_with("done.bin"))
        .collect();
    assert!(
        leftovers.is_empty(),
        "unexpected temporaries: {leftovers:?}"
    );
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn prunes_files_older_than_seven_days_by_embedded_timestamp() {
    let root = temp_root("prune-old");
    let dir = drop_dir(&root);
    fs::create_dir_all(&dir).unwrap();
    let stale = dir.join(format!("{}-old-stale.txt", NOW_MS - 8 * DAY_MS));
    let fresh = dir.join(format!("{}-new-fresh.txt", NOW_MS - 6 * DAY_MS));
    fs::write(&stale, b"stale").unwrap();
    fs::write(&fresh, b"fresh").unwrap();

    let removed = prune_stale(&root, NOW_MS).unwrap();

    assert_eq!(removed, 1);
    assert!(!stale.exists());
    assert!(fresh.exists());
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn pruning_keeps_recent_files_and_fresh_unknown_names() {
    let root = temp_root("prune-mixed");
    let dir = drop_dir(&root);
    fs::create_dir_all(&dir).unwrap();
    let fresh_named = dir.join(format!("{}-id-fresh.txt", NOW_MS - DAY_MS));
    let unparseable = dir.join("not-a-staged-name.txt");
    fs::write(&fresh_named, b"a").unwrap();
    fs::write(&unparseable, b"b").unwrap();

    let removed = prune_stale(&root, NOW_MS).unwrap();

    assert_eq!(removed, 0);
    assert!(fresh_named.exists());
    assert!(unparseable.exists());
    fs::remove_dir_all(root).unwrap();
}

#[test]
fn pruning_a_missing_drop_directory_is_a_noop() {
    let root = temp_root("prune-missing");
    assert_eq!(prune_stale(&root, NOW_MS).unwrap(), 0);
}

#[test]
fn refuses_to_delete_paths_outside_the_owned_drop_dir() {
    let root = temp_root("refuse");
    fs::create_dir_all(drop_dir(&root)).unwrap();
    let outside_dir = root.join("elsewhere");
    fs::create_dir_all(&outside_dir).unwrap();
    let outside_file = outside_dir.join("keep.txt");
    fs::write(&outside_file, b"keep").unwrap();
    let sibling_state = temp_root("refuse-sibling");

    for candidate in [
        root.clone(),
        root.join("missing.txt"),
        outside_file.clone(),
        sibling_state.join("terminal-drops").join("evil.txt"),
        root.parent().unwrap().to_path_buf(),
    ] {
        match remove_staged(&root, &candidate) {
            Err(RemoveError::OutsideDropDir)
            | Err(RemoveError::Missing)
            | Err(RemoveError::NotAStagedFile) => {}
            other => panic!(
                "expected refusal for {}, got {:?}",
                candidate.display(),
                other
            ),
        }
    }

    assert!(outside_file.exists());
    fs::remove_dir_all(root).unwrap();
    fs::remove_dir_all(sibling_state).unwrap();
}

#[cfg(unix)]
#[test]
fn refuses_to_delete_symlinks_that_escape_the_drop_dir() {
    use std::os::unix::fs::symlink;

    let root = temp_root("symlink");
    fs::create_dir_all(drop_dir(&root)).unwrap();
    let outside_dir = root.join("outside");
    fs::create_dir_all(&outside_dir).unwrap();
    let outside_file = outside_dir.join("victim.txt");
    fs::write(&outside_file, b"victim").unwrap();

    let direct_escape = drop_dir(&root).join("escape.txt");
    symlink(&outside_file, &direct_escape).unwrap();

    let nested_dir = drop_dir(&root).join("nested");
    fs::create_dir_all(&nested_dir).unwrap();
    let nested_escape = nested_dir.join("escape.txt");
    symlink(&outside_file, &nested_escape).unwrap();

    for escape in [&direct_escape, &nested_escape] {
        match remove_staged(&root, escape) {
            Err(RemoveError::OutsideDropDir) => {}
            other => panic!(
                "expected a refusal for {}, got {:?}",
                escape.display(),
                other
            ),
        }
    }

    assert!(outside_file.exists());
    assert!(direct_escape.exists());
    assert!(nested_escape.exists());

    let staged = stage(&root, "still deletable.bin", b"data", "aaaa1111", NOW_MS).unwrap();
    remove_staged(&root, &staged).unwrap();
    assert!(!staged.exists());

    fs::remove_dir_all(root).unwrap();
}

#[test]
fn deletes_staged_files_inside_the_drop_dir_but_not_subdirectories() {
    let root = temp_root("delete");
    let staged = stage(&root, "gone after delete.bin", b"bye", "aaaa1111", NOW_MS).unwrap();

    remove_staged(&root, &staged).unwrap();
    assert!(!staged.exists());

    let nested = drop_dir(&root).join("nested");
    fs::create_dir_all(&nested).unwrap();
    match remove_staged(&root, &nested) {
        Err(RemoveError::NotAStagedFile) => {}
        other => panic!("expected a directory refusal, got {other:?}"),
    }
    assert!(nested.exists());
    fs::remove_dir_all(root).unwrap();
}
