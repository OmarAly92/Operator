use std::path::PathBuf;
use std::time::Instant;

use vt_core::{Limits, TerminalCore};

const RUNS: usize = 7;
const CHUNK: usize = 64 << 10;
const ASCII_BYTES: usize = 16 << 20;

fn ascii_stream(total: usize) -> Vec<u8> {
    let styles: [&[u8]; 4] = [b"\x1b[1;32m", b"\x1b[0m", b"\x1b[38;5;208m", b"\x1b[39m"];
    let mut state = 0x9e37_79b9_7f4a_7c15u64;
    let mut next = move || {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        state
    };
    let mut out = Vec::with_capacity(total + 256);
    while out.len() < total {
        let len = (next() % 160) as usize;
        for _ in 0..len {
            if next() % 40 == 0 {
                out.extend_from_slice(styles[(next() % 4) as usize]);
            } else {
                out.push(b' ' + (next() % 95) as u8);
            }
        }
        out.extend_from_slice(b"\r\n");
    }
    out
}

fn edit_stream(total: usize) -> Vec<u8> {
    let styles: [&[u8]; 3] = [b"\x1b[1;36m", b"\x1b[0m", b"\x1b[2m"];
    let edits: [&[u8]; 6] = [
        b"\x1b[5P", b"\x1b[3@", b"\x1b[4X", b"\x1b[1K", b"\x1b[K", b"\x1b[2K",
    ];
    let mut state = 0x0bad_cafe_f00d_d00du64;
    let mut next = move || {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        state
    };
    let mut out = Vec::with_capacity(total + 4096);
    while out.len() < total {
        out.extend_from_slice(b"\x1b[20A");
        for _ in 0..20 {
            out.extend_from_slice(b"\r\x1b[2K");
            out.extend_from_slice(styles[(next() % 3) as usize]);
            for _ in 0..(next() % 110) {
                out.push(b'a' + (next() % 26) as u8);
            }
            out.extend_from_slice(b"\x1b[0m\x1b[30G");
            out.extend_from_slice(edits[(next() % 6) as usize]);
            out.extend_from_slice(b"\x1b[B");
        }
        out.extend_from_slice(b"\r\n\r\n");
    }
    out
}

fn mb_per_second(bytes: &[u8], graphemes: bool) -> f64 {
    let mut core = TerminalCore::with_limits(120, Limits::DEFAULT).expect("core");
    core.resize(120, 40);
    core.set_grapheme_clusters(graphemes);
    let start = Instant::now();
    for chunk in bytes.chunks(CHUNK) {
        core.feed(chunk);
    }
    let seconds = start.elapsed().as_secs_f64();
    bytes.len() as f64 / (1024.0 * 1024.0) / seconds
}

fn median(mut values: Vec<f64>) -> f64 {
    values.sort_by(|a, b| a.partial_cmp(b).expect("finite"));
    values[values.len() / 2]
}

fn main() {
    let label = std::env::args().nth(1).unwrap_or_else(|| "run".to_string());
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../bench/agent-session/fixtures/claude-long-50k/recording");
    let claude = std::fs::read(&fixture).expect("claude-long-50k recording");
    let ascii = ascii_stream(ASCII_BYTES);
    let edits = edit_stream(ASCII_BYTES);
    for (name, bytes) in [
        ("claude-long-50k", &claude),
        ("ascii-heavy", &ascii),
        ("edit-heavy", &edits),
    ] {
        for (mode, graphemes) in [("grapheme", true), ("scalar", false)] {
            let samples: Vec<f64> = (0..RUNS).map(|_| mb_per_second(bytes, graphemes)).collect();
            println!("{label} {name} {mode} {:.2} MB/s", median(samples));
        }
    }
}
