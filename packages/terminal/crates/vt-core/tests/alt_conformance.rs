use std::fs;
use std::path::PathBuf;

use base64::Engine;
use vt_core::TerminalCore;

struct Vector {
    name: String,
    rows: usize,
    cols: usize,
    input: Vec<u8>,
    expected_rows: Vec<String>,
}

fn vectors_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("protocol")
        .join("alt-vectors")
}

fn parse_vector(raw: &str) -> Vector {
    let value: serde_json::Value = serde_json::from_str(raw).expect("vector is valid JSON");
    let obj = value.as_object().expect("vector is an object");
    let name = obj
        .get("name")
        .and_then(|v| v.as_str())
        .expect("vector.name")
        .to_string();
    let rows = obj
        .get("rows")
        .and_then(|v| v.as_u64())
        .expect("vector.rows") as usize;
    let cols = obj
        .get("cols")
        .and_then(|v| v.as_u64())
        .expect("vector.cols") as usize;
    let input_base64 = obj
        .get("inputBase64")
        .and_then(|v| v.as_str())
        .expect("vector.inputBase64");
    let input = base64::engine::general_purpose::STANDARD
        .decode(input_base64)
        .expect("vector.inputBase64 is valid base64");
    let expected_rows = obj
        .get("expectedRows")
        .and_then(|v| v.as_array())
        .expect("vector.expectedRows")
        .iter()
        .map(|v| v.as_str().expect("expected row is a string").to_string())
        .collect();
    Vector {
        name,
        rows,
        cols,
        input,
        expected_rows,
    }
}

fn load_vectors() -> Vec<Vector> {
    let dir = vectors_dir();
    let mut vectors = Vec::new();
    let entries = match fs::read_dir(&dir) {
        Ok(entries) => entries,
        Err(_) => return vectors,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let raw = fs::read_to_string(&path).expect("vector is readable");
        vectors.push(parse_vector(&raw));
    }
    vectors
}

#[test]
fn at_least_one_vector_is_recorded() {
    assert!(
        !load_vectors().is_empty(),
        "no alt-screen vectors in {:?}; run `node tools/tmux-capture.mjs`",
        vectors_dir()
    );
}

#[test]
fn our_alt_grid_matches_tmux_row_for_row() {
    for vector in load_vectors() {
        let mut core = TerminalCore::new(vector.cols, 100).expect("core");
        core.resize(vector.cols, vector.rows);
        core.feed(&vector.input);
        let alt = core
            .alt_grid()
            .unwrap_or_else(|| panic!("{}: never entered the alternate screen", vector.name));
        for (index, expected) in vector.expected_rows.iter().enumerate() {
            assert_eq!(
                alt.row_text(index).trim_end(),
                expected.trim_end(),
                "{} row {index}",
                vector.name
            );
        }
    }
}
