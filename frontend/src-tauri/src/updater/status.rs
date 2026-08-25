use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum UpdateState {
    Idle,
    Checking,
    Available,
    NotAvailable,
    Downloading,
    Downloaded,
    Error,
    Unsupported,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateStatus {
    pub state: UpdateState,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub percent: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub request_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub staged_at: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub escalated: Option<bool>,
}

impl UpdateStatus {
    pub fn idle() -> Self {
        Self {
            state: UpdateState::Idle,
            version: None,
            percent: None,
            message: None,
            request_id: None,
            staged_at: None,
            escalated: None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum UpdatePhase {
    Check,
    Download,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum UpdateTrigger {
    Automatic,
    Manual,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum UpdateFailureCategory {
    Network,
    Signature,
    Permission,
    DiskSpace,
    NotFound,
    NotSupported,
    Unknown,
}

pub const EVENT_UPDATE_FAILED: &str = "opr.renderer.update_failed";
pub const EVENT_UPDATE_DOWNLOADED: &str = "opr.renderer.update_downloaded";
pub const EVENT_UPDATE_UNSUPPORTED: &str = "opr.renderer.update_unsupported";

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateOutcome {
    pub event: &'static str,
    pub phase: UpdatePhase,
    pub trigger: UpdateTrigger,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_category: Option<UpdateFailureCategory>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub to_version: Option<String>,
}

/// Buckets an updater error into a safe category. Anything unrecognized stays
/// "unknown" rather than leaking the original text.
pub fn update_failure_category(message: Option<&str>) -> UpdateFailureCategory {
    let text = message.unwrap_or("").to_lowercase();
    if text.is_empty() {
        return UpdateFailureCategory::Unknown;
    }
    if text.contains("enotfound")
        || text.contains("econnreset")
        || text.contains("econnrefused")
        || text.contains("etimedout")
        || text.contains("net::")
        || text.contains("socket")
        || text.contains("dns")
        || text.contains("network")
        || text.contains("502")
        || text.contains("503")
        || text.contains("504")
    {
        return UpdateFailureCategory::Network;
    }
    if text.contains("signature")
        || text.contains("code sign")
        || text.contains("notariz")
        || text.contains("checksum")
        || text.contains("sha512")
        || text.contains("integrity")
        || text.contains("not trusted")
    {
        return UpdateFailureCategory::Signature;
    }
    if text.contains("eacces")
        || text.contains("eperm")
        || text.contains("permission")
        || text.contains("denied")
        || text.contains("read-only")
        || text.contains("readonly")
    {
        return UpdateFailureCategory::Permission;
    }
    if text.contains("enospc") || text.contains("no space") || text.contains("disk full") {
        return UpdateFailureCategory::DiskSpace;
    }
    if text.contains("404") || text.contains("not found") {
        return UpdateFailureCategory::NotFound;
    }
    if text.contains("unsupported")
        || text.contains("not supported")
        || text.contains("cannot update")
    {
        return UpdateFailureCategory::NotSupported;
    }
    UpdateFailureCategory::Unknown
}

/// Builds the failure outcome for an updater error.
pub fn update_failure_outcome(
    message: Option<&str>,
    phase: UpdatePhase,
    trigger: UpdateTrigger,
    to_version: Option<String>,
) -> UpdateOutcome {
    UpdateOutcome {
        event: EVENT_UPDATE_FAILED,
        phase,
        trigger,
        error_category: Some(update_failure_category(message)),
        to_version,
    }
}

/// Builds the unsupported outcome for a shell surface that cannot update.
pub fn update_unsupported_outcome(phase: UpdatePhase, trigger: UpdateTrigger) -> UpdateOutcome {
    UpdateOutcome {
        event: EVENT_UPDATE_UNSUPPORTED,
        phase,
        trigger,
        error_category: Some(UpdateFailureCategory::NotSupported),
        to_version: None,
    }
}

/// Builds the downloaded outcome for a completed update download.
pub fn update_downloaded_outcome(
    trigger: UpdateTrigger,
    to_version: Option<String>,
) -> UpdateOutcome {
    UpdateOutcome {
        event: EVENT_UPDATE_DOWNLOADED,
        phase: UpdatePhase::Download,
        trigger,
        error_category: None,
        to_version,
    }
}
