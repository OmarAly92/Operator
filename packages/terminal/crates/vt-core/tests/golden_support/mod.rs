pub mod synthetic;

use vt_core::{Limits, TerminalCore};

pub const ROW_GROUP: usize = 500;
pub const ODD_CHUNKS: [usize; 6] = [1, 3, 7, 64, 509, 4093];
pub const EVEN_CHUNK: usize = 4096;
pub const CLOCK_STEP_MS: u64 = 7;

#[derive(Clone, Copy)]
pub struct Config {
    pub name: &'static str,
    pub graphemes: bool,
    pub agent_tui: bool,
    pub mirror: bool,
    pub odd_chunks: bool,
}

pub const CONFIGS: [Config; 4] = [
    Config {
        name: "renderer",
        graphemes: true,
        agent_tui: false,
        mirror: false,
        odd_chunks: false,
    },
    Config {
        name: "renderer-odd",
        graphemes: true,
        agent_tui: false,
        mirror: false,
        odd_chunks: true,
    },
    Config {
        name: "mirror",
        graphemes: false,
        agent_tui: false,
        mirror: true,
        odd_chunks: false,
    },
    Config {
        name: "agent-odd",
        graphemes: false,
        agent_tui: true,
        mirror: false,
        odd_chunks: true,
    },
];

#[derive(Clone, Copy)]
pub struct Size {
    pub offset: usize,
    pub cols: usize,
    pub rows: usize,
}

pub struct Fnv(u64);

impl Fnv {
    pub fn new() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }

    pub fn write(&mut self, bytes: &[u8]) {
        for byte in bytes {
            self.0 ^= u64::from(*byte);
            self.0 = self.0.wrapping_mul(0x0100_0000_01b3);
        }
    }

    pub fn write_str(&mut self, text: &str) {
        self.write(text.as_bytes());
        self.write(&[0xff]);
    }

    pub fn finish(&self) -> String {
        format!("{:016x}", self.0)
    }
}

struct Stream {
    deltas: Fnv,
    replies: Vec<u8>,
    notifications: Vec<String>,
    agent_events: Vec<String>,
    typeahead: Vec<String>,
    feeds: usize,
}

fn new_core(first: Size, config: &Config) -> TerminalCore {
    let limits = if config.mirror {
        Limits {
            rows: 20_000,
            bytes: 256 * 1024,
        }
    } else {
        Limits::DEFAULT
    };
    let mut core = TerminalCore::with_limits(first.cols, limits).expect("core");
    core.resize(first.cols, first.rows);
    core.set_grapheme_clusters(config.graphemes);
    core.set_answers_queries(true);
    core.set_terminal_identity("GoldenTerm");
    core.set_cell_pixels(9, 18);
    core.set_default_colors(Some(0x00dd_dddd), Some(0x0011_1111));
    if config.mirror {
        core.set_reflow_on_resize(false);
        core.set_cold_ring_bytes(1 << 20);
    }
    if config.agent_tui {
        core.set_agent_tui_mode(true);
    }
    core
}

fn drain(core: &mut TerminalCore, stream: &mut Stream) {
    let delta = core.take_delta();
    stream.deltas.write_str(&format!("{delta:?}"));
    stream.replies.extend(core.take_query_replies());
    for note in core.take_notifications() {
        stream.notifications.push(format!("{note:?}"));
    }
    for event in core.take_agent_events() {
        stream.agent_events.push(format!("{event:?}"));
    }
    if let Some(text) = core.take_typeahead() {
        stream.typeahead.push(text);
    }
}

fn feed_range(core: &mut TerminalCore, bytes: &[u8], config: &Config, stream: &mut Stream) {
    let mut at = 0usize;
    while at < bytes.len() {
        let step = if config.odd_chunks {
            ODD_CHUNKS[stream.feeds % ODD_CHUNKS.len()]
        } else {
            EVEN_CHUNK
        };
        let end = (at + step).min(bytes.len());
        stream.feeds += 1;
        core.feed_at(&bytes[at..end], stream.feeds as u64 * CLOCK_STEP_MS);
        drain(core, stream);
        at = end;
    }
}

pub fn replay(recording: &[u8], sizes: &[Size], config: &Config) -> Vec<String> {
    let first = sizes[0];
    let mut core = new_core(first, config);
    let mut stream = Stream {
        deltas: Fnv::new(),
        replies: Vec::new(),
        notifications: Vec::new(),
        agent_events: Vec::new(),
        typeahead: Vec::new(),
        feeds: 0,
    };
    let mut fed = 0usize;
    for size in sizes.iter().skip(1) {
        let upto = size.offset.min(recording.len());
        if upto > fed {
            feed_range(&mut core, &recording[fed..upto], config, &mut stream);
            fed = upto;
        }
        core.resize(size.cols, size.rows);
        drain(&mut core, &mut stream);
    }
    if fed < recording.len() {
        feed_range(&mut core, &recording[fed..], config, &mut stream);
    }
    let tick_at = (stream.feeds as u64 + 1) * CLOCK_STEP_MS + 1_000;
    core.tick(tick_at);
    drain(&mut core, &mut stream);
    core.verify_integrity().expect("integrity");
    digest(&core, &stream, config)
}

fn digest(core: &TerminalCore, stream: &Stream, config: &Config) -> Vec<String> {
    let name = config.name;
    let snapshot = core.snapshot().expect("snapshot");
    let mut lines = Vec::new();
    let rows = snapshot.row_count();
    lines.push(format!("{name} rows {rows}"));
    let mut group = 0usize;
    while group * ROW_GROUP < rows {
        let mut text = Fnv::new();
        let mut styles = Fnv::new();
        let mut spans = Fnv::new();
        for row in group * ROW_GROUP..((group + 1) * ROW_GROUP).min(rows) {
            text.write_str(&format!(
                "{}|{}|{}",
                snapshot.row_indent(row),
                snapshot.row_wrapped(row),
                snapshot.row_text(row)
            ));
            styles.write_str(&format!("{:?}", snapshot.row_style_pairs(row)));
            spans.write_str(&format!("{:?}", snapshot.row_cell_spans(row)));
        }
        lines.push(format!(
            "{name} rows[{}..] text {} styles {} spans {}",
            group * ROW_GROUP,
            text.finish(),
            styles.finish(),
            spans.finish()
        ));
        group += 1;
    }
    let mut blocks = Fnv::new();
    blocks.write_str(&format!("{:?}", snapshot.blocks));
    blocks.write(&snapshot.block_text);
    lines.push(format!(
        "{name} blocks {} {}",
        snapshot.blocks.len(),
        blocks.finish()
    ));
    let mut links = Fnv::new();
    links.write_str(&format!("{:?}", snapshot.link_ranges));
    links.write(&snapshot.link_text);
    lines.push(format!("{name} links {}", links.finish()));
    lines.push(format!(
        "{name} cursor {} {} {} history {} first_stable {} editor {}",
        snapshot.cursor_row,
        snapshot.cursor_col,
        snapshot.cursor_visible,
        snapshot.history_rows,
        snapshot.first_stable_row,
        snapshot.line_editor_state
    ));
    let alt = match core.alt_snapshot() {
        None => "none".to_string(),
        Some(alt) => {
            let mut hash = Fnv::new();
            hash.write(&alt.content);
            hash.write_str(&format!(
                "{:?}{:?}{:?}{:?}{:?}{} {} {}",
                alt.row_ranges,
                alt.run_ranges,
                alt.style_pairs,
                alt.span_ranges,
                alt.cell_spans,
                alt.cursor_row,
                alt.cursor_col,
                alt.cursor_visible
            ));
            format!("{}x{} {}", alt.cols, alt.rows, hash.finish())
        }
    };
    lines.push(format!("{name} alt {alt}"));
    lines.push(format!(
        "{name} modes app_cursor={} sgr_mouse={} paste={} focus={} mouse={} sync={} pending_sync={}",
        core.application_cursor_keys(),
        core.sgr_mouse(),
        core.bracketed_paste(),
        core.focus_reporting(),
        core.mouse_tracking_level(),
        core.synchronized_output(),
        core.pending_sync_bytes().len()
    ));
    lines.push(format!(
        "{name} program title={:?} pointer={:?} stack={} live_output={} older={:?}",
        core.title(),
        core.pointer_shape(),
        core.title_stack_depth(),
        core.live_output_bytes(),
        core.older_state()
    ));
    lines.push(format!(
        "{name} replies {:?}",
        String::from_utf8_lossy(&stream.replies)
    ));
    let mut notes = Fnv::new();
    for note in &stream.notifications {
        notes.write_str(note);
    }
    lines.push(format!(
        "{name} notifications {} {}",
        stream.notifications.len(),
        notes.finish()
    ));
    let mut events = Fnv::new();
    for event in &stream.agent_events {
        events.write_str(event);
    }
    lines.push(format!(
        "{name} agent_events {} {}",
        stream.agent_events.len(),
        events.finish()
    ));
    lines.push(format!("{name} typeahead {:?}", stream.typeahead));
    lines.push(format!(
        "{name} deltas {} {}",
        stream.feeds,
        stream.deltas.finish()
    ));
    lines
}
