use std::fs;
use std::path::Path;

use serde::Deserialize;

#[derive(Clone, Debug, PartialEq)]
pub struct TestVector {
    pub name: String,
    pub input: Vec<u8>,
    pub events: Vec<RawEvent>,
}

#[derive(Clone, Debug, Deserialize, PartialEq)]
pub struct RawEvent {
    pub kind: String,
    pub tier: u8,
    #[serde(default, rename = "exitCode")]
    pub exit_code: Option<i32>,
    #[serde(default)]
    pub path: Option<String>,
}

pub fn load_vector(path: &Path) -> TestVector {
    let text =
        fs::read_to_string(path).unwrap_or_else(|e| panic!("read vector {}: {e}", path.display()));
    let parsed: VectorFile = serde_json::from_str(&text)
        .unwrap_or_else(|e| panic!("parse vector {}: {e}", path.display()));
    TestVector {
        name: parsed.name,
        input: parsed.input.into_bytes(),
        events: parsed.events,
    }
}

#[derive(Deserialize)]
struct VectorFile {
    name: String,
    input: String,
    events: Vec<RawEvent>,
}
