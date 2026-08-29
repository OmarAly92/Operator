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
    #[serde(default)]
    pub tier: Option<RawTier>,
    #[serde(default, alias = "exitCode")]
    pub exit_code: Option<i32>,
    #[serde(default)]
    pub path: Option<String>,
}

#[derive(Clone, Debug, Deserialize, PartialEq)]
#[serde(untagged)]
pub enum RawTier {
    Number(u8),
    Name(String),
}

impl RawTier {
    pub fn is_osc133(&self) -> bool {
        match self {
            Self::Number(1) => true,
            Self::Name(name) => name == "osc133",
            _ => false,
        }
    }
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
