mod common;

use vt_core::hyperlink::{
    parse_osc8, Hyperlink, HyperlinkRegistry, MAX_DISTINCT_ENTRIES, MAX_URI_BYTES,
};
use vt_core::{CellStyle, TerminalCore};

fn link_runs(core: &TerminalCore, row: usize) -> Vec<(u32, u16)> {
    let snapshot = core.snapshot().expect("snapshot");
    common::check(core);
    snapshot
        .row_style_pairs(row)
        .iter()
        .map(|(end, style)| (*end, style.link))
        .collect()
}

#[test]
fn cell_style_stays_sixteen_bytes_with_the_link_id() {
    assert_eq!(std::mem::size_of::<CellStyle>(), 16);
    assert_eq!(CellStyle::DEFAULT.link, 0);
}

#[test]
fn parse_osc8_reads_id_and_rejoins_a_uri_that_contained_semicolons() {
    let link = parse_osc8(&[b"id=abc", b"https://x.y/a", b"b=c"]).expect("open form");
    assert_eq!(
        link,
        Hyperlink {
            id: Some("abc".to_string()),
            uri: "https://x.y/a;b=c".to_string()
        }
    );
    assert_eq!(
        parse_osc8(&[b"", b"https://x.y"]),
        Some(Hyperlink {
            id: None,
            uri: "https://x.y".to_string()
        })
    );
    assert_eq!(parse_osc8(&[b"", b""]), None);
    assert_eq!(parse_osc8(&[]), None);
    let long = vec![b'x'; MAX_URI_BYTES + 1];
    assert_eq!(parse_osc8(&[b"", long.as_slice()]), None);
    let big_id = vec![b'i'; 257];
    let mut params = b"id=".to_vec();
    params.extend_from_slice(&big_id);
    assert_eq!(
        parse_osc8(&[params.as_slice(), b"https://x.y"]),
        Some(Hyperlink {
            id: None,
            uri: "https://x.y".to_string()
        })
    );
}

#[test]
fn the_registry_dedupes_caps_and_never_reclaims() {
    let mut registry = HyperlinkRegistry::default();
    let a = registry
        .intern(Hyperlink {
            id: None,
            uri: "https://a".to_string(),
        })
        .expect("a");
    let again = registry
        .intern(Hyperlink {
            id: None,
            uri: "https://a".to_string(),
        })
        .expect("a again");
    assert_eq!(a, again);
    assert_eq!(a, 1);
    let with_id = registry
        .intern(Hyperlink {
            id: Some("k".to_string()),
            uri: "https://a".to_string(),
        })
        .expect("a with id");
    assert_ne!(with_id, a);
    assert_eq!(registry.uri(a), Some("https://a"));
    assert_eq!(registry.uri(0), None);
    for n in registry.len()..MAX_DISTINCT_ENTRIES {
        assert!(registry
            .intern(Hyperlink {
                id: None,
                uri: format!("https://n/{n}")
            })
            .is_some());
    }
    assert_eq!(registry.len(), MAX_DISTINCT_ENTRIES);
    assert_eq!(
        registry.intern(Hyperlink {
            id: None,
            uri: "https://one-too-many".to_string()
        }),
        None
    );
    assert_eq!(registry.uri(a), Some("https://a"));
}

#[test]
fn printed_cells_carry_the_link_until_it_is_closed() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.feed(b"pre \x1b]8;;https://x.y\x1b\\link\x1b]8;;\x1b\\ post");
    assert_eq!(link_runs(&core, 0), vec![(4, 0), (8, 1), (13, 0)]);
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.link_uri(1), Some("https://x.y"));
    assert_eq!(core.hyperlink_uri(1), Some("https://x.y"));
    assert_eq!(core.hyperlink_count(), 1);
}

#[test]
fn sgr_reset_keeps_the_link_and_a_new_osc8_replaces_it() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.feed(
        b"\x1b]8;;https://a\x1b\\\x1b[31mred\x1b[0mplain\x1b]8;;https://b\x1b\\bee\x1b]8;;\x1b\\",
    );
    assert_eq!(link_runs(&core, 0), vec![(3, 1), (8, 1), (11, 2)]);
}

#[test]
fn a_link_survives_eviction_and_rewrap_because_offsets_do_not_move() {
    let mut core = TerminalCore::new(12, 100).expect("core");
    core.resize(12, 2);
    core.feed(b"\x1b]8;;https://x.y/long\x1b\\alpha beta gamma\x1b]8;;\x1b\\\r\nx\r\ny\r\n");
    core.resize(6, 2);
    let snapshot = core.snapshot().expect("snapshot");
    common::check(&core);
    let linked: Vec<String> = (0..snapshot.row_count())
        .filter(|row| {
            snapshot
                .row_style_pairs(*row)
                .iter()
                .any(|(_, style)| style.link == 1)
        })
        .map(|row| snapshot.row_text(row).to_string())
        .collect();
    assert_eq!(linked.concat(), "alpha beta gamma");
    assert_eq!(snapshot.link_uri(1), Some("https://x.y/long"));
}

#[test]
fn a_boundary_mark_drops_the_pen_link() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.feed(b"\x1b]8;;https://x.y\x1b\\open\x1b]7000;v=1;boundary=0\x07after");
    let snapshot = core.snapshot().expect("snapshot");
    let after = (0..snapshot.row_count())
        .find(|row| snapshot.row_text(*row) == "after")
        .expect("after row");
    assert!(snapshot
        .row_style_pairs(after)
        .iter()
        .all(|(_, style)| style.link == 0));
}

#[test]
fn a_history_chunk_carrying_osc8_interns_into_the_receiving_core() {
    let mut core = TerminalCore::new(20, 10_000).expect("core");
    core.feed(b"\x1b]7000;v=1;origin=1000\x1b\\live\r\n");
    core.feed(b"\x1b]7000;v=1;history=999,1\x1b\\");
    core.feed(b"\x1b]8;;https://old\x1b\\older\x1b]8;;\x1b\\\r\n");
    let snapshot = core.snapshot().expect("snapshot");
    common::check(&core);
    assert_eq!(snapshot.row_text(0), "older");
    let link = snapshot.row_style_pairs(0)[0].1.link;
    assert_ne!(link, 0);
    assert_eq!(snapshot.link_uri(link), Some("https://old"));
}

#[test]
fn the_alternate_screen_carries_links_through_the_same_registry() {
    let mut core = TerminalCore::new(20, 100).expect("core");
    core.resize(20, 3);
    core.feed(b"\x1b[?1049h\x1b]8;;https://alt\x1b\\alt\x1b]8;;\x1b\\");
    let snapshot = core.snapshot().expect("snapshot");
    assert_eq!(snapshot.link_uri(1), Some("https://alt"));
    let alt = snapshot.alt.expect("alt");
    assert_eq!(alt.style_pairs[0].1.link, 1);
}
