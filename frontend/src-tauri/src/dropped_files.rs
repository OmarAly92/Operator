use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

pub const DROP_DIR_NAME: &str = "terminal-drops";
pub const MAX_INPUT_BYTES: usize = 64 * 1024 * 1024;
pub const PRUNE_AFTER_MS: u64 = 7 * 24 * 60 * 60 * 1000;

#[derive(Debug)]
pub enum StageError {
    TooLarge { size: usize },
    Io(io::Error),
}

impl std::fmt::Display for StageError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StageError::TooLarge { size } => write!(
                f,
                "dropped file is {size} bytes; the maximum accepted input is {MAX_INPUT_BYTES} bytes"
            ),
            StageError::Io(error) => write!(f, "dropped file could not be staged: {error}"),
        }
    }
}

impl From<io::Error> for StageError {
    fn from(error: io::Error) -> Self {
        StageError::Io(error)
    }
}

#[derive(Debug)]
pub enum RemoveError {
    Missing,
    OutsideDropDir,
    NotAStagedFile,
    Io(io::Error),
}

impl std::fmt::Display for RemoveError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RemoveError::Missing => write!(f, "staged dropped file does not exist"),
            RemoveError::OutsideDropDir => {
                write!(
                    f,
                    "refusing to delete a path outside the owned drop directory"
                )
            }
            RemoveError::NotAStagedFile => write!(f, "path is not a staged dropped file"),
            RemoveError::Io(error) => {
                write!(f, "staged dropped file could not be deleted: {error}")
            }
        }
    }
}

impl From<io::Error> for RemoveError {
    fn from(error: io::Error) -> Self {
        RemoveError::Io(error)
    }
}

pub fn drop_dir(state_root: &Path) -> PathBuf {
    state_root.join(DROP_DIR_NAME)
}

pub fn unix_millis_now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as u64)
        .unwrap_or_default()
}

const MAX_BASENAME_CHARS: usize = 80;

pub fn sanitize_basename(raw: &str) -> String {
    let base = raw.rsplit(['/', '\\']).next().unwrap_or("");
    let mut sanitized = String::new();
    let mut in_invalid_run = false;
    for character in base.chars() {
        if character.is_ascii_alphanumeric() || matches!(character, '_' | '.' | '-') {
            sanitized.push(character);
            in_invalid_run = false;
        } else if !in_invalid_run {
            sanitized.push('_');
            in_invalid_run = true;
        }
    }
    if sanitized.is_empty() {
        return "dropped".to_string();
    }
    if sanitized.chars().count() > MAX_BASENAME_CHARS {
        sanitized.chars().take(MAX_BASENAME_CHARS).collect()
    } else {
        sanitized
    }
}

fn staged_file_name(now_ms: u64, id: &str, base: &str) -> String {
    format!("{now_ms}-{id}-{base}")
}

fn staged_temp_name(now_ms: u64, id: &str, base: &str) -> String {
    format!("{now_ms}-{id}-partial-{base}")
}

pub fn stage(
    state_root: &Path,
    name: &str,
    bytes: &[u8],
    id: &str,
    now_ms: u64,
) -> Result<PathBuf, StageError> {
    if bytes.len() > MAX_INPUT_BYTES {
        return Err(StageError::TooLarge { size: bytes.len() });
    }
    let dir = drop_dir(state_root);
    fs::create_dir_all(&dir)?;
    let base = sanitize_basename(name);
    let temp = dir.join(staged_temp_name(now_ms, id, &base));
    let target = dir.join(staged_file_name(now_ms, id, &base));
    {
        let mut file = fs::File::create(&temp)?;
        file.write_all(bytes)?;
    }
    fs::rename(&temp, &target)?;
    Ok(target)
}

fn entry_is_older_than(path: &Path, cutoff_ms: u64) -> bool {
    let Some(file_name) = path.file_name().and_then(|name| name.to_str()) else {
        return false;
    };
    let stamp = file_name
        .split('-')
        .next()
        .and_then(|prefix| prefix.parse::<u64>().ok());
    match stamp {
        Some(stamp) => stamp < cutoff_ms,
        None => fs::metadata(path)
            .and_then(|meta| meta.modified())
            .map(|modified| modified < unix_millis_to_system_time(cutoff_ms))
            .unwrap_or(false),
    }
}

fn unix_millis_to_system_time(millis: u64) -> std::time::SystemTime {
    std::time::SystemTime::UNIX_EPOCH + std::time::Duration::from_millis(millis)
}

pub fn prune_stale(state_root: &Path, now_ms: u64) -> io::Result<usize> {
    let dir = drop_dir(state_root);
    let entries = match fs::read_dir(&dir) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(0),
        Err(error) => return Err(error),
    };
    let cutoff_ms = now_ms.saturating_sub(PRUNE_AFTER_MS);
    let mut removed = 0;
    for entry in entries {
        let Ok(entry) = entry else {
            continue;
        };
        let path = entry.path();
        if !entry_is_older_than(&path, cutoff_ms) {
            continue;
        }
        let is_directory = entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false);
        let deleted = if is_directory {
            fs::remove_dir_all(&path)
        } else {
            fs::remove_file(&path)
        };
        if deleted.is_ok() {
            removed += 1;
        }
    }
    Ok(removed)
}

pub fn remove_staged(state_root: &Path, candidate: &Path) -> Result<(), RemoveError> {
    let candidate_canonical = candidate.canonicalize().map_err(|error| {
        if error.kind() == io::ErrorKind::NotFound {
            RemoveError::Missing
        } else {
            RemoveError::Io(error)
        }
    })?;
    let dir_canonical = match drop_dir(state_root).canonicalize() {
        Ok(dir) => dir,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Err(RemoveError::OutsideDropDir)
        }
        Err(error) => return Err(RemoveError::Io(error)),
    };
    if candidate_canonical == dir_canonical {
        return Err(RemoveError::NotAStagedFile);
    }
    if candidate_canonical.parent() != Some(dir_canonical.as_path()) {
        return Err(RemoveError::OutsideDropDir);
    }
    if !candidate_canonical.is_file() {
        return Err(RemoveError::NotAStagedFile);
    }
    fs::remove_file(&candidate_canonical).map_err(From::from)
}
