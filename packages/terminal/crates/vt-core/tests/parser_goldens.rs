mod golden_support;

use std::fs;
use std::path::{Path, PathBuf};

use golden_support::{replay, synthetic, Size, CONFIGS};

fn manifest() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn read_sizes(path: &Path) -> Vec<Size> {
    let raw = fs::read_to_string(path).expect("size.json");
    let values: Vec<serde_json::Value> = serde_json::from_str(&raw).expect("size.json array");
    values
        .iter()
        .map(|value| Size {
            offset: value["offset"].as_u64().expect("offset") as usize,
            cols: value["cols"].as_u64().expect("cols") as usize,
            rows: value["rows"].as_u64().expect("rows") as usize,
        })
        .collect()
}

fn recordings() -> Vec<(String, Vec<u8>, Vec<Size>)> {
    let mut out = Vec::new();
    let mut dirs: Vec<(String, PathBuf)> = Vec::new();
    for base in [
        manifest().join("tests/ref"),
        manifest().join("../../bench/agent-session/fixtures"),
    ] {
        for entry in fs::read_dir(&base).expect("recording dir") {
            let path = entry.expect("entry").path();
            if path.join("recording").is_file() && path.join("size.json").is_file() {
                let name = path.file_name().unwrap().to_string_lossy().into_owned();
                dirs.push((name, path));
            }
        }
    }
    dirs.sort();
    for (name, path) in dirs {
        let bytes = fs::read(path.join("recording")).expect("recording");
        out.push((name, bytes, read_sizes(&path.join("size.json"))));
    }
    for item in synthetic::all() {
        out.push((item.name.to_string(), item.bytes, item.sizes));
    }
    out
}

fn golden_path(name: &str) -> PathBuf {
    manifest()
        .join("tests/goldens")
        .join(format!("{name}.golden"))
}

#[test]
fn every_recording_matches_the_goldens_recorded_before_the_parser_rework() {
    let update = std::env::var_os("UPDATE_GOLDENS").is_some();
    let mut failures = Vec::new();
    let sources = recordings();
    assert!(sources.len() >= 53, "found {} recordings", sources.len());
    for (name, bytes, sizes) in sources {
        let mut lines = Vec::new();
        for config in CONFIGS.iter() {
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
