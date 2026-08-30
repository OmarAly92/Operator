use crate::event::ExtensionFields;

/// Decode a Tier-2 (OSC 7000) payload. The payload is the bytes between
/// `ESC ]` and `ESC \`, so `OSC 7000 ; v=1 ; id=block-001 ; …` arrives here
/// as `b"7000;v=1; id=block-001; …"`. Pairs are separated by `;`, with one
/// optional ASCII space after the separator ignored per SPEC §4.1.
///
/// Returns `Some(ExtensionFields)` for a parseable mark whose `v` major
/// version is the one this decoder understands (1). A higher major version
/// returns `None` per SPEC §4.2 — the mark is ignored in its entirety.
pub fn decode(payload: &[u8]) -> Option<ExtensionFields> {
    let prefix: &[u8] = b"7000;";
    let pairs_str = std::str::from_utf8(payload.strip_prefix(prefix)?).ok()?;

    let mut pairs: Vec<(String, String)> = Vec::new();
    let mut version_seen = false;
    let mut drop_whole = false;

    // Split on `;`, then trim one leading space off each non-first chunk so
    // both `7000;k=v;k=v` and `7000;k=v; k=v` parse identically. The leading
    // chunk is untrimmed because it has no separator before it.
    let mut chunks = pairs_str.split(';');
    let first = chunks.next()?;
    push_pair(&mut pairs, first, &mut version_seen, &mut drop_whole);
    for chunk in chunks {
        let trimmed = chunk.strip_prefix(' ').unwrap_or(chunk);
        push_pair(&mut pairs, trimmed, &mut version_seen, &mut drop_whole);
    }

    if drop_whole {
        return None;
    }
    Some(ExtensionFields { pairs })
}

fn push_pair(
    pairs: &mut Vec<(String, String)>,
    chunk: &str,
    version_seen: &mut bool,
    drop_whole: &mut bool,
) {
    if chunk.is_empty() || *drop_whole {
        return;
    }
    let Some((raw_key, raw_value)) = chunk.split_once('=') else {
        return;
    };
    let key = raw_key.to_string();
    let value = percent_decode(raw_value.as_bytes());

    if key == "v" && !*version_seen {
        // The version check is what gates a "higher major" mark. We read
        // this key *first* (per SPEC §4.2) so a future v=2 mark is dropped
        // before any other key is parsed. If we can't parse the version
        // at all, we still try to extract the keys we know — the spec
        // only requires whole-mark rejection for a *higher* major.
        *version_seen = true;
        if let Ok(version) = value.parse::<u32>() {
            if version > 1 {
                *drop_whole = true;
                pairs.clear();
                return;
            }
        }
    }

    pairs.push((key, value));
}

/// Minimal percent-decoder for the byte alphabet the protocol allows. Any
/// other byte is passed through verbatim — the encoder is responsible for
/// the encoding, and a malformed escape is the encoder's bug, not the
/// decoder's. This is intentionally not a full RFC 3986 implementation.
fn percent_decode(input: &[u8]) -> String {
    let mut out = Vec::with_capacity(input.len());
    let mut i = 0;
    while i < input.len() {
        if input[i] == b'%' && i + 2 < input.len() {
            if let (Some(hi), Some(lo)) = (hex_digit(input[i + 1]), hex_digit(input[i + 2])) {
                out.push(hi * 16 + lo);
                i += 3;
                continue;
            }
        }
        out.push(input[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn hex_digit(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_v1_with_known_keys() {
        let f = decode(b"7000;v=1; cmd=ls").unwrap();
        assert_eq!(
            f.pairs,
            vec![("v".into(), "1".into()), ("cmd".into(), "ls".into())]
        );
    }

    #[test]
    fn higher_major_version_returns_none() {
        assert_eq!(decode(b"7000;v=2; cmd=ls"), None);
    }

    #[test]
    fn percent_decodes_values() {
        let f = decode(b"7000;v=1; cmd=echo%20hello").unwrap();
        assert_eq!(
            f.pairs,
            vec![
                ("v".into(), "1".into()),
                ("cmd".into(), "echo hello".into())
            ]
        );
    }
}
