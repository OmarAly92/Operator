use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// Relocation outcome for a macOS launch running outside an Applications folder.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RelocationAction {
    /// Run where we are; touch nothing.
    Stay,
    /// Nothing newer to lose: move this bundle into /Applications.
    Relocate,
    /// An equal-or-newer install exists: launch it instead and quit.
    Handoff,
}

/// Inputs to the macOS relocation decision (mirrors frontend/src/main/relocation.ts).
pub struct RelocationInputs<'a> {
    /// True for /Applications AND <home>/Applications.
    pub in_applications_folder: bool,
    /// A bundle already occupies /Applications/<our bundle name>.
    pub installed_present: bool,
    /// That bundle's CFBundleShortVersionString, None when unreadable.
    pub installed_version: Option<&'a str>,
    /// The running bundle's version.
    pub running_version: &'a str,
}

const APPLICATIONS_DIR: &str = "/Applications";

/// Pure relocation decision. "Relocate" is reachable only when /Applications
/// holds nothing or a strictly older build; every unknown resolves to "stay" so
/// an unreadable version can never cost a user their install.
pub fn decide_relocation(inputs: RelocationInputs) -> RelocationAction {
    if inputs.in_applications_folder {
        return RelocationAction::Stay;
    }
    if !inputs.installed_present {
        return RelocationAction::Relocate;
    }
    let installed = semver::Version::parse(inputs.installed_version.unwrap_or_default()).ok();
    let running = semver::Version::parse(inputs.running_version).ok();
    let (Some(installed), Some(running)) = (installed, running) else {
        return RelocationAction::Stay;
    };
    if installed < running {
        RelocationAction::Relocate
    } else {
        RelocationAction::Handoff
    }
}

/// Path the running bundle would occupy under /Applications.
pub fn installed_bundle_path(running_bundle_path: &Path) -> PathBuf {
    installed_bundle_path_in(running_bundle_path, Path::new(APPLICATIONS_DIR))
}

pub fn installed_bundle_path_in(running_bundle_path: &Path, applications_dir: &Path) -> PathBuf {
    match running_bundle_path.file_name() {
        Some(name) => applications_dir.join(name),
        None => applications_dir.to_path_buf(),
    }
}

/// CFBundleShortVersionString from a bundle's XML Info.plist; None when the
/// bundle is absent or the key is unreadable. Regex-free on purpose: a parse
/// miss degrades to "unknown" rather than an error.
pub fn read_bundle_version(bundle_path: &Path) -> Option<String> {
    read_bundle_string(bundle_path, "CFBundleShortVersionString")
}

fn read_bundle_string(bundle_path: &Path, key: &str) -> Option<String> {
    const OPEN: &str = "<string>";
    const CLOSE: &str = "</string>";
    let plist = fs::read_to_string(bundle_path.join("Contents").join("Info.plist")).ok()?;
    let key_tag = format!("<key>{key}</key>");
    let key_position = plist.find(&key_tag)?;
    let rest = &plist[key_position + key_tag.len()..];
    let open_position = rest.find(OPEN)?;
    if !rest[..open_position].chars().all(char::is_whitespace) {
        return None;
    }
    let value_start = &rest[open_position + OPEN.len()..];
    let close_position = value_start.find(CLOSE)?;
    let value = value_start[..close_position].trim();
    if value.is_empty() || value.contains('<') {
        return None;
    }
    Some(value.to_string())
}

fn executable_file(path: &Path) -> bool {
    if !path.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::metadata(path)
            .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    }
    #[cfg(not(unix))]
    {
        true
    }
}

pub fn macos_bundle_layout_valid(bundle_path: &Path) -> bool {
    bundle_path
        .extension()
        .is_some_and(|extension| extension == "app")
        && bundle_path.is_dir()
        && bundle_path.join("Contents/Info.plist").is_file()
        && executable_file(&bundle_path.join("Contents/MacOS/operator"))
        && read_bundle_string(bundle_path, "CFBundleExecutable").as_deref() == Some("operator")
        && read_bundle_string(bundle_path, "CFBundleIdentifier").as_deref()
            == Some("dev.operator.desktop")
        && read_bundle_string(bundle_path, "CFBundleName").as_deref() == Some("Operator")
}

pub fn valid_macos_bundle(bundle_path: &Path, expected_version: &str) -> bool {
    macos_bundle_layout_valid(bundle_path)
        && read_bundle_version(bundle_path).as_deref() == Some(expected_version)
}

/// Read the /Applications copy's state for the relocation decision: presence
/// plus version, with an unreadable copy reported as present-but-unknown.
pub fn inspect_installed_bundle(running_bundle_path: &Path) -> (bool, Option<String>) {
    inspect_installed_bundle_in(running_bundle_path, Path::new(APPLICATIONS_DIR))
}

pub fn inspect_installed_bundle_in(
    running_bundle_path: &Path,
    applications_dir: &Path,
) -> (bool, Option<String>) {
    let installed = installed_bundle_path_in(running_bundle_path, applications_dir);
    if !installed.exists() {
        return (false, None);
    }
    if !macos_bundle_layout_valid(&installed) {
        return (true, None);
    }
    (true, read_bundle_version(&installed))
}

/// True when the bundle runs from /Applications or <home>/Applications,
/// mirroring Electron's app.isInApplicationsFolder().
pub fn is_in_applications_folder(bundle_path: &Path, home_dir: &Path) -> bool {
    bundle_path.starts_with(Path::new(APPLICATIONS_DIR))
        || bundle_path.starts_with(home_dir.join("Applications"))
}

/// Upper bound on uniquified Trash candidates before the move is declined.
const TRASH_CANDIDATE_LIMIT: u32 = 100;

/// Destination in <home>/.Trash for a bundle being set aside, mirroring
/// Electron's default moveToApplicationsFolder conflict handling: the OLD
/// install goes to the user's Trash under a Finder-uniquified name
/// ("Operator.app", then "Operator 2.app", ...). None when every candidate name
/// is already taken or the name has no usable form.
pub fn trashed_bundle_destination(
    home_dir: &Path,
    bundle_name: &str,
    mut exists: impl FnMut(&Path) -> bool,
) -> Option<PathBuf> {
    if bundle_name.is_empty() {
        return None;
    }
    let trash = home_dir.join(".Trash");
    let bundle = Path::new(bundle_name);
    let stem = bundle.file_stem()?.to_str()?;
    let extension = bundle.extension().and_then(|ext| ext.to_str());
    let mut candidate = trash.join(bundle_name);
    for taken in 1..=TRASH_CANDIDATE_LIMIT {
        if !exists(&candidate) {
            return Some(candidate);
        }
        candidate = trash.join(match extension {
            Some(ext) => format!("{stem} {next}.{ext}", next = taken + 1),
            None => format!("{stem} {}", taken + 1),
        });
    }
    None
}

pub trait RelocationExecutor {
    fn exists(&self, path: &Path) -> bool;
    fn move_path(&mut self, from: &Path, to: &Path) -> io::Result<()>;
    fn copy_bundle(&mut self, from: &Path, to: &Path) -> io::Result<()>;
    fn valid_bundle(&self, path: &Path, expected_version: &str) -> bool;
    fn remove_staged(&mut self, path: &Path) -> io::Result<()>;
    fn launch_bundle(&mut self, path: &Path) -> bool;
}

pub fn staged_bundle_path(installed: &Path, tag: &str) -> PathBuf {
    let name = installed
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("Operator");
    installed.with_file_name(format!(".{name}.operator-stage-{tag}.app"))
}

fn cleanup_error<E: RelocationExecutor>(
    executor: &mut E,
    stage: &Path,
    error: io::Error,
) -> io::Error {
    match executor.remove_staged(stage) {
        Ok(()) => error,
        Err(cleanup) => io::Error::other(format!(
            "{error}; staging cleanup at {} failed: {cleanup}",
            stage.display()
        )),
    }
}

/// Cross-process mutual exclusion for the whole relocate-or-decline window.
/// Held as an exclusive advisory lock on `<state-root>/relocation.lock` so two
/// concurrently launched app instances can never interleave the destructive
/// bundle replacement: `flock(LOCK_EX | LOCK_NB)` on POSIX, an open with no
/// sharing allowed on Windows (every opener of this path uses the same mode,
/// so the second open fails while the first handle lives). Acquisition never
/// blocks: a contended instance gets `None` and declines without touching
/// either bundle. The lock lives in the kernel per open handle, so it is
/// released by closing the guard's file — including when the holder dies
/// without running destructors — and a leftover lock file never blocks the
/// next launch. The holder stamps its pid into the file; that content is
/// diagnostics only.
#[derive(Debug)]
pub struct RelocationLock {
    file: fs::File,
}

impl RelocationLock {
    pub fn lock_path(state_root: &Path) -> PathBuf {
        state_root.join("relocation.lock")
    }

    pub fn try_acquire(state_root: &Path) -> io::Result<Option<RelocationLock>> {
        fs::create_dir_all(state_root)?;
        let file = match open_lock_file(&Self::lock_path(state_root)) {
            Ok(file) => file,
            Err(error) if is_lock_contention(&error) => return Ok(None),
            Err(error) => return Err(error),
        };
        match try_lock_exclusive(&file) {
            Ok(()) => {
                let lock = RelocationLock { file };
                stamp_holder_pid(&lock.file);
                Ok(Some(lock))
            }
            Err(error) if is_lock_contention(&error) => Ok(None),
            Err(error) => Err(error),
        }
    }
}

fn stamp_holder_pid(file: &fs::File) {
    use std::io::Write;
    let mut file = file;
    let _ = writeln!(file, "{}", std::process::id());
}

#[cfg(unix)]
fn open_lock_file(path: &Path) -> io::Result<fs::File> {
    use std::os::unix::fs::OpenOptionsExt;
    fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(path)
}

#[cfg(windows)]
fn open_lock_file(path: &Path) -> io::Result<fs::File> {
    use std::os::windows::fs::OpenOptionsExt;
    fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .share_mode(0)
        .open(path)
}

#[cfg(unix)]
fn try_lock_exclusive(file: &fs::File) -> io::Result<()> {
    use std::os::fd::AsRawFd;
    let result = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if result == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

#[cfg(unix)]
fn is_lock_contention(error: &io::Error) -> bool {
    matches!(
        error.raw_os_error(),
        Some(code) if code == libc::EWOULDBLOCK || code == libc::EAGAIN
    )
}

#[cfg(windows)]
fn try_lock_exclusive(_file: &fs::File) -> io::Result<()> {
    Ok(())
}

#[cfg(windows)]
fn is_lock_contention(error: &io::Error) -> bool {
    const ERROR_SHARING_VIOLATION: i32 = 32;
    const ERROR_LOCK_VIOLATION: i32 = 33;
    matches!(
        error.raw_os_error(),
        Some(ERROR_SHARING_VIOLATION) | Some(ERROR_LOCK_VIOLATION)
    )
}

pub fn execute_relocation<E: RelocationExecutor>(
    executor: &mut E,
    home: &Path,
    running: &Path,
    installed: &Path,
    expected_version: &str,
    stage_tag: &str,
    _lock: &RelocationLock,
) -> io::Result<bool> {
    if running == installed {
        return Err(io::Error::other(
            "running and installed bundle paths are identical",
        ));
    }
    let stage = staged_bundle_path(installed, stage_tag);
    if executor.exists(&stage) {
        return Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            stage.display().to_string(),
        ));
    }
    if let Err(error) = executor.copy_bundle(running, &stage) {
        return Err(cleanup_error(executor, &stage, error));
    }
    if !executor.valid_bundle(&stage, expected_version) {
        return Err(cleanup_error(
            executor,
            &stage,
            io::Error::other("staged Operator bundle failed validation"),
        ));
    }

    let backup = if executor.exists(installed) {
        let Some(bundle_name) = installed.file_name().and_then(|name| name.to_str()) else {
            return Err(cleanup_error(
                executor,
                &stage,
                io::Error::other("installed bundle has no usable name"),
            ));
        };
        let Some(destination) =
            trashed_bundle_destination(home, bundle_name, |path| executor.exists(path))
        else {
            return Err(cleanup_error(
                executor,
                &stage,
                io::Error::other("no free Trash destination for installed bundle"),
            ));
        };
        if let Err(error) = executor.move_path(installed, &destination) {
            return Err(cleanup_error(executor, &stage, error));
        }
        Some(destination)
    } else {
        None
    };

    if let Err(error) = executor.move_path(&stage, installed) {
        if let Some(backup) = backup.as_ref() {
            if let Err(rollback_error) = executor.move_path(backup, installed) {
                return Err(io::Error::other(format!(
                    "{error}; rollback failed: {rollback_error}; staged recovery preserved at {}",
                    stage.display()
                )));
            }
        }
        return Err(cleanup_error(executor, &stage, error));
    }

    if !executor.valid_bundle(installed, expected_version) {
        if let Err(error) = executor.move_path(installed, &stage) {
            return Err(io::Error::other(format!(
                "installed bundle failed validation and could not be staged for rollback: {error}"
            )));
        }
        if let Some(backup) = backup.as_ref() {
            if let Err(error) = executor.move_path(backup, installed) {
                return Err(io::Error::other(format!(
                    "installed bundle failed validation and rollback failed: {error}; staged recovery preserved at {}",
                    stage.display()
                )));
            }
        }
        return Err(cleanup_error(
            executor,
            &stage,
            io::Error::other("installed Operator bundle failed validation"),
        ));
    }

    Ok(executor.launch_bundle(installed))
}
