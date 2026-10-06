#[allow(dead_code)]
mod golden_support;

use std::fs;
use std::path::PathBuf;

use golden_support::synthetic::Rng;
use golden_support::{replay, Config, Size, CONFIGS};

const PROMPT_START: &[u8] = b"\x1b]133;A\x07";
const PROMPT_READY: &[u8] = b"\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07";
const COMMAND_START: &[u8] = b"\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07";
const COMMAND_END: &[u8] = b"\x1b]133;D;0\x07";
const PROMPTS: [&[u8]; 4] = [
    b"~/project $ ",
    b"line-one-of-a-long-prompt-/home/someone/projects/a/b/c/d/e/f\r\nline-two $ ",
    "\u{65e5}\u{672c}\u{8a9e}\u{306e}\u{30d7}\u{30ed}\u{30f3}\u{30d7}\u{30c8} > ".as_bytes(),
    b"",
];
const TEXT: [&[u8]; 12] = [
    b"plain words that wrap when the pane is narrow enough to cut them ",
    "\u{4e2d}\u{6587}\u{5b57}".as_bytes(),
    b"\x1b[1;32mgreen\x1b[0m ",
    b"\x1b[48;5;236m band with a background \x1b[0m",
    b"  - a bullet that hangs its continuation under the text ",
    "e\u{301}".as_bytes(),
    "\u{1f44d}\u{1f3fd}".as_bytes(),
    b"\t",
    b"\x1b[K",
    b"x",
    b"\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\",
    b"0123456789",
];
const SIZES: [(usize, usize); 8] = [
    (80, 24),
    (40, 24),
    (100, 30),
    (30, 12),
    (120, 40),
    (61, 17),
    (7, 5),
    (80, 3),
];

#[derive(Clone, Copy, PartialEq, Eq)]
enum Family {
    NoIntegration,
    Running,
    AltScreen,
    AtPrompt,
}

fn line(rng: &mut Rng, out: &mut Vec<u8>) {
    for _ in 0..rng.below(8) {
        out.extend_from_slice(rng.pick(&TEXT));
    }
    out.extend_from_slice(b"\r\n");
}

fn resize_at(rng: &mut Rng, out: &[u8], sizes: &mut Vec<Size>) {
    let (cols, rows) = SIZES[rng.below(SIZES.len())];
    sizes.push(Size {
        offset: out.len(),
        cols,
        rows,
    });
}

fn prompt(rng: &mut Rng, out: &mut Vec<u8>) {
    out.extend_from_slice(PROMPT_START);
    out.extend_from_slice(PROMPTS[rng.below(PROMPTS.len())]);
    out.extend_from_slice(PROMPT_READY);
}

fn stream(family: Family, seed: u64) -> (Vec<u8>, Vec<Size>) {
    let mut rng = Rng::new(seed);
    let mut out = Vec::new();
    let mut sizes = vec![Size {
        offset: 0,
        cols: 80,
        rows: 24,
    }];
    for _ in 0..24 {
        match family {
            Family::NoIntegration => {
                for _ in 0..rng.below(30) {
                    line(&mut rng, &mut out);
                }
                out.extend_from_slice(b"$ ");
                resize_at(&mut rng, &out, &mut sizes);
            }
            Family::Running => {
                prompt(&mut rng, &mut out);
                out.extend_from_slice(b"echo command");
                out.extend_from_slice(COMMAND_START);
                for _ in 0..rng.below(30) {
                    line(&mut rng, &mut out);
                    if rng.below(6) == 0 {
                        resize_at(&mut rng, &out, &mut sizes);
                    }
                }
                resize_at(&mut rng, &out, &mut sizes);
                out.extend_from_slice(COMMAND_END);
            }
            Family::AltScreen => {
                prompt(&mut rng, &mut out);
                out.extend_from_slice(COMMAND_START);
                out.extend_from_slice(b"\x1b[?1049h\x1b[H\x1b[2J");
                for _ in 0..rng.below(10) {
                    line(&mut rng, &mut out);
                }
                resize_at(&mut rng, &out, &mut sizes);
                out.extend_from_slice(b"\x1b[?1049l");
                resize_at(&mut rng, &out, &mut sizes);
                out.extend_from_slice(COMMAND_END);
            }
            Family::AtPrompt => {
                for _ in 0..rng.below(30) {
                    line(&mut rng, &mut out);
                }
                prompt(&mut rng, &mut out);
                resize_at(&mut rng, &out, &mut sizes);
                out.extend_from_slice(b"\r\x1b[J~/project $ ");
                out.extend_from_slice(COMMAND_START);
                line(&mut rng, &mut out);
                out.extend_from_slice(COMMAND_END);
            }
        }
    }
    (out, sizes)
}

fn configs_for(family: Family) -> Vec<&'static Config> {
    CONFIGS
        .iter()
        .filter(|config| family != Family::AtPrompt || config.mirror || config.agent_tui)
        .collect()
}

fn streams() -> Vec<(String, Family, u64)> {
    let mut out = Vec::new();
    for (name, family) in [
        ("no-integration", Family::NoIntegration),
        ("running", Family::Running),
        ("alt-screen", Family::AltScreen),
        ("at-prompt-mirror-agent", Family::AtPrompt),
    ] {
        for seed in 1..=3u64 {
            out.push((format!("resize-{name}-{seed}"), family, seed * 0x9e37_79b9));
        }
    }
    out
}

fn golden_path(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/goldens")
        .join(format!("{name}.golden"))
}

#[test]
fn resizes_outside_an_owned_prompt_match_the_goldens_recorded_before_prompt_reflow() {
    let update = std::env::var_os("UPDATE_GOLDENS").is_some();
    let mut failures = Vec::new();
    for (name, family, seed) in streams() {
        let (bytes, sizes) = stream(family, seed);
        let mut lines = Vec::new();
        for config in configs_for(family) {
            lines.extend(replay(&bytes, &sizes, config));
        }
        let got = lines.join("\n") + "\n";
        let path = golden_path(&name);
        if update {
            fs::write(&path, &got).expect("write golden");
            continue;
        }
        let want = fs::read_to_string(&path).unwrap_or_else(|_| {
            panic!(
                "{} missing (UPDATE_GOLDENS=1 on the unmodified tree)",
                path.display()
            )
        });
        if got != want {
            let first = got
                .lines()
                .zip(want.lines())
                .find(|(g, w)| g != w)
                .map(|(g, w)| format!("got  {g}\nwant {w}"))
                .unwrap_or_else(|| "line count differs".to_string());
            failures.push(format!("{name}:\n{first}"));
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n\n"));
}
