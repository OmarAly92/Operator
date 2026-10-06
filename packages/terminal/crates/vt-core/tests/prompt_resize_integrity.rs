mod common;

use vt_core::{Limits, LineEditorState, TerminalCore};

struct Rng(u64);

impl Rng {
    fn below(&mut self, bound: usize) -> usize {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        (self.0 % bound as u64) as usize
    }
}

const PROMPTS: [&str; 5] = [
    "$ ",
    "~/a/very/long/working/directory/that/wraps/on/a/narrow/pane $ ",
    "first line of a prompt\r\nsecond $ ",
    "\u{65e5}\u{672c}\u{8a9e}\u{306e}\u{30d7}\u{30ed}\u{30f3}\u{30d7}\u{30c8} > ",
    "",
];

const TEXT: [&str; 10] = [
    "plain words that wrap when the pane is narrow ",
    "\u{4e2d}\u{6587}\u{5b57}",
    "\x1b[1;32mgreen\x1b[0m ",
    "\x1b[48;5;236m band \x1b[0m",
    "  - a bullet that hangs its continuation ",
    "e\u{301}",
    "\u{1f44d}\u{1f3fd}",
    "\t",
    "\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\",
    "0123456789",
];

const SIZES: [(usize, usize); 9] = [
    (80, 24),
    (40, 24),
    (100, 30),
    (30, 12),
    (7, 5),
    (1, 1),
    (2, 3),
    (61, 17),
    (120, 2),
];

fn step(rng: &mut Rng, core: &mut TerminalCore) -> bool {
    let owned = core.line_editor_state() == LineEditorState::Owned;
    match rng.below(10) {
        0 | 1 => {
            let mut line = String::new();
            for _ in 0..rng.below(6) {
                line.push_str(TEXT[rng.below(TEXT.len())]);
            }
            line.push_str("\r\n");
            core.feed(line.as_bytes());
        }
        2 => core.feed(
            format!(
                "\x1b]133;A\x07{}\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07",
                PROMPTS[rng.below(PROMPTS.len())]
            )
            .as_bytes(),
        ),
        3 => core.feed(b"\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07"),
        4 => core.feed(b"\x1b]133;D;0\x07"),
        5 => core.feed(if rng.below(2) == 0 {
            b"\x1b[?1049h\x1b[Hfull"
        } else {
            b"\x1b[?1049l"
        }),
        6 => core.feed(b"\r\r\x1b[A\x1b[J$ typed"),
        7 => core.feed(b"\x1b]7000;v=1;older=2\x07"),
        _ => {
            let (cols, rows) = SIZES[rng.below(SIZES.len())];
            core.resize(cols, rows);
            return owned;
        }
    }
    false
}

#[test]
fn every_step_of_a_seeded_prompt_resize_sequence_keeps_the_model_consistent() {
    let mut owned_resizes = 0usize;
    for seed in 1..=32u64 {
        let mut rng = Rng(seed.wrapping_mul(0x9e37_79b9_7f4a_7c15) | 1);
        let limits = if seed % 4 == 0 {
            Limits::rows_only(30)
        } else {
            Limits::DEFAULT
        };
        let mut core = TerminalCore::with_limits(80, limits).unwrap();
        core.resize(80, 24);
        core.set_grapheme_clusters(seed % 2 == 0);
        for index in 0..300 {
            owned_resizes += usize::from(step(&mut rng, &mut core));
            if let Err(error) = core.verify_integrity() {
                panic!("seed {seed} step {index}: {error:?}");
            }
            common::check(&core);
        }
    }
    assert!(
        owned_resizes >= 200,
        "only {owned_resizes} resizes at a prompt"
    );
}
