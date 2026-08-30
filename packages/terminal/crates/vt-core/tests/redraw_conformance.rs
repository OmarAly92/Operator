use vt_core::TerminalCore;

#[test]
fn thirty_replays_of_an_agent_redraw_stay_within_the_screen() {
    let raw = include_str!("../../../protocol/redraw-vectors/agent-cli-idle.json");
    let vector: serde_json::Value = serde_json::from_str(raw).unwrap();
    let bytes: Vec<u8> = vector["bytes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|value| value.as_u64().unwrap() as u8)
        .collect();

    let mut core = TerminalCore::new(100, 5000).unwrap();
    core.resize(100, 30);
    for _ in 0..30 {
        core.feed(&bytes);
    }

    let rows = core.snapshot().unwrap().row_count();
    assert!(
        rows < 300,
        "30 replays produced {rows} rows; before the screen grid this was 841",
    );
}
