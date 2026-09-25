use std::collections::VecDeque;

pub const AGENT_EXTENSION: &[u8] = b"agent-state";
pub const MAX_AGENT_OSC_BYTES: usize = 1024;
pub const MAX_AGENT_DETAIL_BYTES: usize = 256;
pub const MAX_PENDING_AGENT_EVENTS: usize = 16;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentState {
    Working,
    Waiting,
    Idle,
    Done,
}

impl AgentState {
    pub fn parse(raw: &[u8]) -> Option<Self> {
        match raw {
            b"working" => Some(Self::Working),
            b"waiting" => Some(Self::Waiting),
            b"idle" => Some(Self::Idle),
            b"done" => Some(Self::Done),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Working => "working",
            Self::Waiting => "waiting",
            Self::Idle => "idle",
            Self::Done => "done",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentEvent {
    pub state: AgentState,
    pub detail: String,
}

#[derive(Debug, Default)]
pub struct AgentChannel {
    pending: VecDeque<AgentEvent>,
    last: Option<AgentEvent>,
    replaying: bool,
}

impl AgentChannel {
    pub fn osc(&mut self, fields: &[&[u8]]) -> bool {
        if self.replaying {
            return false;
        }
        let Some(event) = parse_agent_fields(fields) else {
            return false;
        };
        if self.last.as_ref() == Some(&event) {
            return false;
        }
        self.last = Some(event.clone());
        if self.pending.len() >= MAX_PENDING_AGENT_EVENTS {
            self.pending.pop_front();
        }
        self.pending.push_back(event);
        true
    }

    pub fn take(&mut self) -> Vec<AgentEvent> {
        self.pending.drain(..).collect()
    }

    pub fn replaying(&self) -> bool {
        self.replaying
    }

    pub fn set_replaying(&mut self, on: bool) {
        self.replaying = on;
    }

    pub fn reset_for_new_process(&mut self) {
        self.last = None;
    }
}

pub fn parse_agent_fields(fields: &[&[u8]]) -> Option<AgentEvent> {
    let raw_len = b"777;".len()
        + AGENT_EXTENSION.len()
        + fields.iter().map(|field| field.len() + 1).sum::<usize>();
    if raw_len >= MAX_AGENT_OSC_BYTES {
        return None;
    }
    let mut version: Option<&[u8]> = None;
    let mut state: Option<&[u8]> = None;
    let mut detail: Option<&[u8]> = None;
    for field in fields {
        let field = field.strip_prefix(b" ").unwrap_or(field);
        if field.is_empty() {
            continue;
        }
        let equals = field.iter().position(|byte| *byte == b'=')?;
        let (key, value) = (&field[..equals], &field[equals + 1..]);
        let slot = match key {
            b"v" => &mut version,
            b"state" => &mut state,
            b"detail" => &mut detail,
            _ => continue,
        };
        if slot.is_some() {
            return None;
        }
        *slot = Some(value);
    }
    if version? != b"1" {
        return None;
    }
    let state = AgentState::parse(state?)?;
    let detail = match detail {
        Some(raw) => {
            crate::program::clean_text(&percent_decode_strict(raw)?, MAX_AGENT_DETAIL_BYTES)
        }
        None => String::new(),
    };
    Some(AgentEvent { state, detail })
}

fn percent_decode_strict(raw: &[u8]) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(raw.len());
    let mut index = 0;
    while index < raw.len() {
        if raw[index] == b'%' {
            let high = hex(*raw.get(index + 1)?)?;
            let low = hex(*raw.get(index + 2)?)?;
            out.push(high * 16 + low);
            index += 3;
        } else {
            out.push(raw[index]);
            index += 1;
        }
    }
    Some(out)
}

fn hex(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

impl crate::TerminalCore {
    pub fn take_agent_events(&mut self) -> Vec<AgentEvent> {
        self.parser.program_mut().agent_mut().take()
    }

    pub fn live_output_bytes(&self) -> u64 {
        self.live_output
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_minimal_event_parses() {
        let event = parse_agent_fields(&[b"v=1", b"state=working"]).expect("event");
        assert_eq!(event.state, AgentState::Working);
        assert_eq!(event.detail, "");
    }

    #[test]
    fn fields_parse_in_any_order_with_one_leading_space_and_unknown_keys() {
        let event = parse_agent_fields(&[b"state=done", b" x-future=1", b" v=1"]).expect("event");
        assert_eq!(event.state, AgentState::Done);
    }

    #[test]
    fn a_repeated_key_or_a_field_without_equals_rejects_the_event() {
        assert!(parse_agent_fields(&[b"v=1", b"state=idle", b"state=done"]).is_none());
        assert!(parse_agent_fields(&[b"v=1", b"state=idle", b"bare"]).is_none());
    }

    #[test]
    fn a_bad_percent_escape_rejects_the_event() {
        assert!(parse_agent_fields(&[b"v=1", b"state=idle", b"detail=50%"]).is_none());
        assert!(parse_agent_fields(&[b"v=1", b"state=idle", b"detail=%zz"]).is_none());
    }

    #[test]
    fn a_payload_that_fills_the_osc_buffer_is_treated_as_truncated() {
        let fits = format!("x={}", "a".repeat(MAX_AGENT_OSC_BYTES - 36 - 1));
        assert!(parse_agent_fields(&[b"v=1", b"state=working", fits.as_bytes()]).is_some());
        let full = format!("x={}", "a".repeat(MAX_AGENT_OSC_BYTES - 36));
        assert!(parse_agent_fields(&[b"v=1", b"state=working", full.as_bytes()]).is_none());
    }

    #[test]
    fn identical_consecutive_events_are_queued_once_and_the_queue_is_capped() {
        let mut channel = AgentChannel::default();
        assert!(channel.osc(&[b"v=1", b"state=working"]));
        assert!(!channel.osc(&[b"v=1", b"state=working"]));
        assert!(channel.osc(&[b"v=1", b"state=working", b"detail=a"]));
        assert_eq!(channel.take().len(), 2);
        for index in 0..(MAX_PENDING_AGENT_EVENTS + 4) {
            let detail = format!("detail={index}");
            channel.osc(&[b"v=1", b"state=working", detail.as_bytes()]);
        }
        let taken = channel.take();
        assert_eq!(taken.len(), MAX_PENDING_AGENT_EVENTS);
        assert_eq!(taken[0].detail, "4");
    }
}
