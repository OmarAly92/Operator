use std::fs;
use std::path::Path;

use serde::Deserialize;
use vt_core::{clusters, WidthMode};

#[derive(Deserialize)]
struct Case {
    data: Vec<String>,
    comment: String,
}

#[test]
fn every_case_in_the_unicode_grapheme_break_corpus_splits_as_the_standard_says() {
    let path = Path::new(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/grapheme/GraphemeBreakTest.json"
    ));
    let cases: Vec<Case> =
        serde_json::from_str(&fs::read_to_string(path).expect("corpus")).expect("corpus json");
    assert!(cases.len() > 700, "corpus has {} cases", cases.len());
    let mut failures = Vec::new();
    for case in &cases {
        let text: String = case.data.concat();
        let got: Vec<&str> = clusters(&text, WidthMode::Grapheme)
            .iter()
            .map(|cluster| &text[cluster.start..cluster.end])
            .collect();
        let want: Vec<&str> = case.data.iter().map(String::as_str).collect();
        if got != want {
            failures.push(format!("{}\n  want {want:?}\n  got  {got:?}", case.comment));
        }
    }
    assert!(
        failures.is_empty(),
        "{} of {} cases differ:\n{}",
        failures.len(),
        cases.len(),
        failures.join("\n")
    );
}

#[test]
fn scalar_mode_folds_zero_width_scalars_into_the_previous_cluster() {
    let text = "e\u{301}x";
    let got: Vec<(usize, usize, usize)> = clusters(text, WidthMode::Scalar)
        .iter()
        .map(|c| (c.start, c.end, c.width))
        .collect();
    assert_eq!(got, vec![(0, 3, 1), (3, 4, 1)]);
    let family = "\u{1f468}\u{200d}\u{1f469}\u{200d}\u{1f467}";
    assert_eq!(clusters(family, WidthMode::Scalar).len(), 3);
    assert_eq!(clusters(family, WidthMode::Grapheme).len(), 1);
    assert_eq!(clusters(family, WidthMode::Grapheme)[0].width, 2);
}
