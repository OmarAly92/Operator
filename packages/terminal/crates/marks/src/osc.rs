use crate::event::{MarkEvent, MarkTier};

/// Decode a Tier-1 OSC payload. The payload is the bytes between `ESC ]` and
/// the terminator (BEL or `ESC \`), so `OSC 133 ; A` arrives here as `b"133;A"`.
/// Returns `Some(event)` for recognised marks, `None` otherwise (unknown
/// subcommand, empty payload, or recognised Tier-2 prefix — the extension
/// module handles that).
pub fn decode(payload: &[u8]) -> Option<MarkEvent> {
    if payload.is_empty() {
        return None;
    }
    let split = payload.iter().position(|&b| b == b';');
    let (command, rest) = match split {
        Some(idx) => (&payload[..idx], &payload[idx + 1..]),
        None => (payload, &[][..]),
    };

    match command {
        b"133" => decode_osc133(rest),
        b"7" => decode_osc7(rest),
        // Any other OSC (including `7000` for Tier 2) returns `None` here so
        // the scanner falls through to the extension decoder.
        _ => None,
    }
}

fn decode_osc133(rest: &[u8]) -> Option<MarkEvent> {
    // The subcommand is the first byte of `rest`. We accept only single-byte
    // subcommands in Phase 1a: A, B, C, and D. Anything else is ignored
    // (recovery row 7).
    let (&sub, tail) = rest.split_first()?;
    let tier = MarkTier::Osc133;
    match sub {
        b'A' => Some(MarkEvent::PromptStart { tier }),
        b'B' => Some(MarkEvent::CommandStart { tier }),
        b'C' => Some(MarkEvent::OutputStart { tier }),
        b'D' => {
            // `D;<exit>` is the form with an exit code; bare `D` is the
            // "missing exit" form (spec §6).
            let exit = if let Some(stripped) = tail.strip_prefix(b";") {
                match std::str::from_utf8(stripped) {
                    Ok(text) => text.parse::<i32>().ok(),
                    Err(_) => None,
                }
            } else {
                None
            };
            Some(MarkEvent::CommandEnd {
                tier,
                exit_code: exit,
            })
        }
        _ => None,
    }
}

fn decode_osc7(rest: &[u8]) -> Option<MarkEvent> {
    // `OSC 7 ; file://host/path` — the path is the part after the third `/`
    // in the URL, matching the conventional `file://host/path` form.
    let url = std::str::from_utf8(rest).ok()?;
    let path = path_from_file_url(url)?;
    Some(MarkEvent::CwdChanged { path })
}

fn path_from_file_url(url: &str) -> Option<String> {
    let prefix = "file://";
    let after = url.strip_prefix(prefix)?;
    // Drop the host segment, if any (`file://host/path` -> `/path`).
    let path = if let Some(slash) = after.find('/') {
        &after[slash..]
    } else {
        after
    };
    Some(path.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::MarkTier;

    #[test]
    fn d_with_exit_parses_int() {
        assert_eq!(
            decode(b"133;D;0"),
            Some(MarkEvent::CommandEnd {
                tier: MarkTier::Osc133,
                exit_code: Some(0)
            })
        );
    }

    #[test]
    fn d_without_exit_is_none() {
        assert_eq!(
            decode(b"133;D"),
            Some(MarkEvent::CommandEnd {
                tier: MarkTier::Osc133,
                exit_code: None
            })
        );
    }

    #[test]
    fn d_with_unparseable_exit_is_none() {
        assert_eq!(
            decode(b"133;D;not-a-number"),
            Some(MarkEvent::CommandEnd {
                tier: MarkTier::Osc133,
                exit_code: None
            })
        );
    }

    #[test]
    fn unknown_133_subcommand_is_ignored() {
        assert_eq!(decode(b"133;Z"), None);
    }

    #[test]
    fn osc7_extracts_path() {
        assert_eq!(
            decode(b"7;file://host/Users/example/project"),
            Some(MarkEvent::CwdChanged {
                path: "/Users/example/project".to_string()
            })
        );
    }
}
