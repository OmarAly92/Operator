use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

pub const UPDATER_DIR_NAME: &str = "updater";
const STAGED_DIR_NAME: &str = "staged";
const TMP_DIR_NAME: &str = "tmp";
const ARTIFACT_FILE: &str = "update.bin";
const META_FILE: &str = "meta.json";
const PARTIAL_FILE: &str = "partial.json";
pub const PARTIAL_MAX_AGE_MS: i64 = 7 * 24 * 60 * 60 * 1000;

#[derive(Debug)]
pub enum StorageError {
    OutsideUpdaterDir,
    InvalidVersionName,
    Io(io::Error),
}

impl std::fmt::Display for StorageError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StorageError::OutsideUpdaterDir => {
                write!(
                    f,
                    "refusing to touch a path outside the updater state directory"
                )
            }
            StorageError::InvalidVersionName => {
                write!(
                    f,
                    "refusing an updater artifact name that is not a plain version directory"
                )
            }
            StorageError::Io(error) => write!(f, "updater storage operation failed: {error}"),
        }
    }
}

impl From<io::Error> for StorageError {
    fn from(error: io::Error) -> Self {
        StorageError::Io(error)
    }
}

impl From<serde_json::Error> for StorageError {
    fn from(error: serde_json::Error) -> Self {
        StorageError::Io(error.into())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StagedMeta {
    pub version: String,
    pub url: String,
    pub size: u64,
    pub staged_at_ms: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StagedArtifact {
    pub meta: StagedMeta,
    pub path: PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DownloadIntent {
    pub version: String,
    pub url: String,
    pub started_at_ms: i64,
}

/// A download that began but never completed: the interrupted-download record
/// the next launch uses to restart cleanly.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PendingDownload {
    pub intent: DownloadIntent,
}

/// Owns every updater byte on disk beneath `<state-root>/updater`. All writes
/// are temp-file-plus-rename inside that directory; nothing outside it is ever
/// read or written by this module.
pub struct UpdaterStorage {
    root: PathBuf,
}

impl UpdaterStorage {
    /// Creates (or reopens) `<state-root>/updater` with its staged and tmp
    /// subdirectories.
    pub fn open(state_root: &Path) -> io::Result<Self> {
        let root = state_root.join(UPDATER_DIR_NAME);
        fs::create_dir_all(root.join(STAGED_DIR_NAME))?;
        fs::create_dir_all(root.join(TMP_DIR_NAME))?;
        let root = fs::canonicalize(&root)?;
        Ok(Self { root })
    }

    /// The canonical `<state-root>/updater` directory.
    pub fn root(&self) -> &Path {
        &self.root
    }

    /// The scratch directory every temporary updater byte must land in.
    pub fn tmp_dir(&self) -> PathBuf {
        self.root.join(TMP_DIR_NAME)
    }

    /// Records a download intent before any artifact bytes are written so a
    /// mid-download crash leaves a discoverable, restartable record.
    pub fn begin_download(
        &self,
        version: &str,
        url: &str,
        started_at_ms: i64,
    ) -> Result<(), StorageError> {
        let dir = self.version_dir(version)?;
        fs::create_dir_all(&dir)?;
        let intent = DownloadIntent {
            version: version.to_string(),
            url: url.to_string(),
            started_at_ms,
        };
        write_atomic(
            &dir.join(PARTIAL_FILE),
            serde_json::to_vec(&intent)?.as_slice(),
        )?;
        Ok(())
    }

    /// Persists verified artifact bytes atomically and clears the download
    /// intent, leaving `staged/<version>/update.bin` plus its metadata.
    pub fn complete_download(
        &self,
        version: &str,
        url: &str,
        bytes: &[u8],
        staged_at_ms: i64,
    ) -> Result<StagedArtifact, StorageError> {
        let dir = self.version_dir(version)?;
        fs::create_dir_all(&dir)?;
        write_atomic(&dir.join(ARTIFACT_FILE), bytes)?;
        let meta = StagedMeta {
            version: version.to_string(),
            url: url.to_string(),
            size: bytes.len() as u64,
            staged_at_ms,
        };
        write_atomic(&dir.join(META_FILE), serde_json::to_vec(&meta)?.as_slice())?;
        match fs::remove_file(dir.join(PARTIAL_FILE)) {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
        Ok(StagedArtifact {
            meta,
            path: dir.join(ARTIFACT_FILE),
        })
    }

    /// Loads a previously completed staged artifact for `version`.
    pub fn staged(&self, version: &str) -> Option<StagedArtifact> {
        let dir = self.version_dir(version).ok()?;
        let raw = fs::read(dir.join(META_FILE)).ok()?;
        let meta: StagedMeta = serde_json::from_slice(&raw).ok()?;
        Some(StagedArtifact {
            meta,
            path: dir.join(ARTIFACT_FILE),
        })
    }

    /// Lists unfinished downloads (intent recorded, artifact never completed).
    pub fn pending_downloads(&self) -> Vec<PendingDownload> {
        let mut pending = Vec::new();
        let Ok(entries) = fs::read_dir(self.root.join(STAGED_DIR_NAME)) else {
            return pending;
        };
        for entry in entries.flatten() {
            let path = entry.path().join(PARTIAL_FILE);
            let Ok(raw) = fs::read(&path) else {
                continue;
            };
            if let Ok(intent) = serde_json::from_slice::<DownloadIntent>(&raw) {
                pending.push(PendingDownload { intent });
            }
        }
        pending.sort_by_key(|record| record.intent.started_at_ms);
        pending
    }

    /// Removes stale unfinished-download records older than `max_age_ms`.
    pub fn prune_partials(&self, now_ms: i64, max_age_ms: i64) -> usize {
        let mut pruned = 0;
        for record in self.pending_downloads() {
            if now_ms - record.intent.started_at_ms < max_age_ms {
                continue;
            }
            let dir = match self.version_dir(&record.intent.version) {
                Ok(dir) => dir,
                Err(_) => continue,
            };
            if fs::remove_file(dir.join(PARTIAL_FILE)).is_ok() {
                pruned += 1;
            }
        }
        pruned
    }

    /// Deletes one staged version directory.
    pub fn remove_staged(&self, version: &str) -> Result<(), StorageError> {
        let dir = self.version_dir(version)?;
        match fs::remove_dir_all(&dir) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error.into()),
        }
    }

    /// Refuses any path that does not resolve inside the updater directory.
    /// Symlinks are resolved before comparison so escapes cannot hide behind
    /// an inside-looking prefix.
    pub fn ensure_inside(&self, path: &Path) -> Result<(), StorageError> {
        let resolved = fs::canonicalize(path).map_err(|error| {
            if error.kind() == io::ErrorKind::NotFound {
                StorageError::OutsideUpdaterDir
            } else {
                StorageError::Io(error)
            }
        })?;
        let inside = resolved.starts_with(&self.root);
        if !inside {
            return Err(StorageError::OutsideUpdaterDir);
        }
        Ok(())
    }

    fn version_dir(&self, version: &str) -> Result<PathBuf, StorageError> {
        if !is_version_name(version) {
            return Err(StorageError::InvalidVersionName);
        }
        Ok(self.root.join(STAGED_DIR_NAME).join(version))
    }
}

fn write_atomic(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let unique = uuid::Uuid::new_v4().simple().to_string();
    let temp = path.with_extension(format!("{}.tmp", unique));
    fs::write(&temp, bytes)?;
    match fs::rename(&temp, path) {
        Ok(()) => Ok(()),
        Err(error) => {
            let _ = fs::remove_file(&temp);
            Err(error)
        }
    }
}

fn is_version_name(name: &str) -> bool {
    !name.is_empty()
        && !name.starts_with('.')
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_' | '+'))
}
