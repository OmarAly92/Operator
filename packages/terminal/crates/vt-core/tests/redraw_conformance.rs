use vt_core::TerminalCore;

#[test]
fn thirty_replays_of_an_agent_redraw_stay_within_the_screen() {
    let raw = include_str!("../../../protocol/redraw-vectors/agent-cli-idle.json");
    let vector: serde_json::Value = serde_json::from_str(raw).unwrap();
    let columns = usize::try_from(vector["columns"].as_u64().unwrap()).unwrap();
    let capture_rows = usize::try_from(vector["rows"].as_u64().unwrap()).unwrap();
    let bytes: Vec<u8> = vector["bytes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|value| u8::try_from(value.as_u64().unwrap()).unwrap())
        .collect();

    let mut core = TerminalCore::new(columns, 5000).unwrap();
    core.resize(columns, capture_rows);
    for _ in 0..30 {
        core.feed(&bytes);
    }

    let rows = core.snapshot().unwrap().row_count();
    let maximum_rows = capture_rows * 6 + 4;
    assert!(
        rows <= maximum_rows,
        "30 replays produced {rows} rows; expected no more than {maximum_rows} rows for the capture geometry",
    );
}
