use std::collections::HashMap;

// warp/crates/warp_terminal/src/model/grid/hyperlink_registry.rs (caps, no reclamation)
pub const MAX_DISTINCT_ENTRIES: usize = 4096;
// warp/crates/warp_terminal/src/model/ansi/control_sequence_parameters.rs:714,718
pub const MAX_URI_BYTES: usize = 2083;
pub const MAX_ID_BYTES: usize = 256;

pub type LinkId = u16;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct Hyperlink {
    pub id: Option<String>,
    pub uri: String,
}

#[derive(Debug, Default)]
pub struct HyperlinkRegistry {
    by_link: HashMap<Hyperlink, LinkId>,
    by_id: Vec<Hyperlink>,
}

impl HyperlinkRegistry {
    pub fn intern(&mut self, link: Hyperlink) -> Option<LinkId> {
        if link.uri.len() > MAX_URI_BYTES {
            return None;
        }
        if let Some(&id) = self.by_link.get(&link) {
            return Some(id);
        }
        if self.by_id.len() >= MAX_DISTINCT_ENTRIES {
            return None;
        }
        let id = LinkId::try_from(self.by_id.len() + 1).ok()?;
        self.by_id.push(link.clone());
        self.by_link.insert(link, id);
        Some(id)
    }

    pub fn uri(&self, id: LinkId) -> Option<&str> {
        let index = usize::from(id).checked_sub(1)?;
        self.by_id.get(index).map(|link| link.uri.as_str())
    }

    pub fn len(&self) -> usize {
        self.by_id.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by_id.is_empty()
    }
}

pub fn parse_osc8(params: &[&[u8]]) -> Option<Hyperlink> {
    let (params_field, uri_parts) = params.split_first()?;
    let uri_len =
        uri_parts.iter().map(|part| part.len()).sum::<usize>() + uri_parts.len().saturating_sub(1);
    if uri_len == 0 || uri_len > MAX_URI_BYTES {
        return None;
    }
    let mut uri_bytes = Vec::with_capacity(uri_len);
    for (index, part) in uri_parts.iter().enumerate() {
        if index > 0 {
            uri_bytes.push(b';');
        }
        uri_bytes.extend_from_slice(part);
    }
    let uri = String::from_utf8(uri_bytes).ok()?;
    let mut id = None;
    for pair in params_field.split(|byte| *byte == b':') {
        let Some(equals) = pair.iter().position(|byte| *byte == b'=') else {
            continue;
        };
        let (key, value) = (&pair[..equals], &pair[equals + 1..]);
        if key == b"id" && !value.is_empty() && value.len() <= MAX_ID_BYTES {
            if let Ok(value) = std::str::from_utf8(value) {
                id = Some(value.to_owned());
            }
        }
    }
    Some(Hyperlink { id, uri })
}
