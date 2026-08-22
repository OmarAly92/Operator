use std::fs;
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
    let installed = parse_release_version(inputs.installed_version.unwrap_or_default());
    let running = parse_release_version(inputs.running_version);
    let (Some(installed), Some(running)) = (installed, running) else {
        return RelocationAction::Stay;
    };
    if installed < running {
        RelocationAction::Relocate
    } else {
        RelocationAction::Handoff
    }
}

/// Strict major.minor.patch parser; anything else is unreadable and must
/// resolve to "stay".
fn parse_release_version(version: &str) -> Option<(u64, u64, u64)> {
    let mut parts = version.split('.');
    let major = parts.next()?.parse().ok()?;
    let minor = parts.next()?.parse().ok()?;
    let patch = parts.next()?.parse().ok()?;
    if parts.next().is_some() {
        return None;
    }
    Some((major, minor, patch))
}

/// Path the running bundle would occupy under /Applications.
pub fn installed_bundle_path(running_bundle_path: &Path) -> PathBuf {
    match running_bundle_path.file_name() {
        Some(name) => Path::new(APPLICATIONS_DIR).join(name),
        None => PathBuf::from(APPLICATIONS_DIR),
    }
}

/// CFBundleShortVersionString from a bundle's XML Info.plist; None when the
/// bundle is absent or the key is unreadable. Regex-free on purpose: a parse
/// miss degrades to "unknown" rather than an error.
pub fn read_bundle_version(bundle_path: &Path) -> Option<String> {
    const KEY: &str = "<key>CFBundleShortVersionString</key>";
    const OPEN: &str = "<string>";
    const CLOSE: &str = "</string>";
    let plist = fs::read_to_string(bundle_path.join("Contents").join("Info.plist")).ok()?;
    let key_position = plist.find(KEY)?;
    let rest = &plist[key_position + KEY.len()..];
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

/// Read the /Applications copy's state for the relocation decision: presence
/// plus version, with an unreadable copy reported as present-but-unknown.
pub fn inspect_installed_bundle(running_bundle_path: &Path) -> (bool, Option<String>) {
    let installed = installed_bundle_path(running_bundle_path);
    if !installed.exists() {
        return (false, None);
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
