use super::channel::Channel;
use super::BoxFuture;

pub const H48_MS: i64 = 48 * 60 * 60 * 1000;

/// Read-only release-feed probes backing the nightly escalation rules. Every
/// failure degrades to "no information" rather than an error state.
pub trait EscalationFeeds: Send + Sync {
    /// Latest stable version via the release feed; None on any failure.
    fn latest_stable_version<'a>(&'a self) -> BoxFuture<'a, Option<String>>;
    /// Whether the staged nightly's feed marks it important; false on any
    /// failure.
    fn nightly_important<'a>(&'a self, version: &str) -> BoxFuture<'a, bool>;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EscalationInput<'a> {
    pub channel: Channel,
    pub staged_at_ms: i64,
    pub now_ms: i64,
    pub important: bool,
    pub running_version: &'a str,
    pub latest_stable_version: Option<&'a str>,
}

/// Pure escalation decision: nudge harder when a staged build should be
/// installed. latest escalates after 48 hours staged; nightly escalates when
/// the feed marks the build important or the running version is behind the
/// latest stable release.
pub fn evaluate_escalation(input: EscalationInput) -> bool {
    if input.channel == Channel::Latest {
        return input.now_ms - input.staged_at_ms >= H48_MS;
    }
    if input.important {
        return true;
    }
    let Some(latest_stable) = input.latest_stable_version else {
        return false;
    };
    let (Ok(running), Ok(stable)) = (
        semver::Version::parse(input.running_version),
        semver::Version::parse(latest_stable),
    ) else {
        return false;
    };
    running < stable
}
