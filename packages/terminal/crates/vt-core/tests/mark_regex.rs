use std::time::{Duration, Instant};

use vt_core::mark_regex::MarkRegex;

fn ranges(pattern: &str, text: &str) -> Vec<u32> {
    MarkRegex::new(pattern)
        .expect("pattern compiles")
        .utf16_ranges(text)
}

#[test]
fn finds_every_match_as_utf16_start_end_pairs() {
    assert_eq!(ranges("err(or)?", "err, error, ERROR"), vec![0, 3, 5, 10]);
}

#[test]
fn counts_offsets_in_utf16_units_past_non_ascii_text() {
    assert_eq!(ranges("x", "é日😀x"), vec![4, 5]);
    assert_eq!(ranges("日", "é日"), vec![1, 2]);
}

#[test]
fn skips_empty_matches() {
    assert_eq!(ranges("x*", "ab"), Vec::<u32>::new());
    assert_eq!(ranges("^", "ab"), Vec::<u32>::new());
}

#[test]
fn rejects_an_empty_or_invalid_pattern() {
    assert!(MarkRegex::new("").is_none());
    assert!(MarkRegex::new("(oops").is_none());
    assert!(MarkRegex::new("(?=x)").is_none());
    assert!(MarkRegex::new(r"(a)\1").is_none());
}

#[test]
fn rejects_a_pattern_that_compiles_too_large() {
    assert!(MarkRegex::new(r"\w{1000}{1000}").is_none());
}

#[test]
fn a_backtracking_bomb_finishes_in_linear_time() {
    let text = format!("{}!", "a".repeat(20_000));
    let started = Instant::now();
    let found = ranges("(a+)+$", &text);
    assert!(found.is_empty());
    assert!(started.elapsed() < Duration::from_secs(2));
}
