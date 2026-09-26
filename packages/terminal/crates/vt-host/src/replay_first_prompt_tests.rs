use vt_core::{BlockSource, Limits, LineEditorState, TerminalCore};

use crate::replay::replay_frame;

const REAL_BASH_FIRST_PROMPT: &str = "\x1b]7000;v=1;exit=0\x07\x1b]7000;v=1;id=t-1;cwd=%2Ftmp;branch=\x1b\\\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07\x1b[?1034h\r\x1b[K";
const REAL_BASH_FIRST_COMMAND: &str = "\r\x1b[Kecho hello\r\n\x1b]7000;v=1;id=t-1;cmd=echo%20hello\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07hello\r\n\x1b]7000;v=1;id=t-1;exit=0\x1b\\\x1b]133;D;0\x07\x1b]7000;v=1;id=t-2;cwd=%2Ftmp;branch=\x1b\\\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07\r\x1b[K";

type BlockSummary = (String, String, BlockSource, Vec<String>);

fn mirror(cols: usize, rows: usize) -> TerminalCore {
    let limits = Limits {
        rows: 1000,
        bytes: u32::MAX as usize,
    };
    let mut core = TerminalCore::with_limits(cols, limits).unwrap();
    core.set_reflow_on_resize(false);
    core.set_answers_queries(true);
    core.resize(cols, rows);
    core
}

fn renderer(cols: usize, rows: usize) -> TerminalCore {
    let mut core = TerminalCore::new(cols, 1000).unwrap();
    core.resize(cols, rows);
    core
}

fn zsh_prompt(id: &str) -> String {
    format!(
        "\x1b]7000;v=1;id={id};cwd=%2Ftmp;branch=\x1b\\\x1b[1m\x1b[7m%\x1b[27m\x1b[1m\x1b[0m{}\r \r\x1b]133;A\x07\x1b]133;B\x07\x1b]7000;v=1;input-ready=1\x07",
        " ".repeat(79)
    )
}

fn block_summary(core: &TerminalCore) -> Vec<BlockSummary> {
    let snapshot = core.snapshot().unwrap();
    (0..snapshot.blocks.len())
        .map(|index| {
            let block = snapshot.blocks[index];
            let first = block.first_row as usize;
            (
                snapshot.block_command(index).to_string(),
                snapshot.block_cwd(index).to_string(),
                block.source,
                (first..first + block.row_count as usize)
                    .map(|row| snapshot.row_text(row).trim_end().to_string())
                    .collect(),
            )
        })
        .collect()
}

fn attached_after_the_first_prompt(first_prompt: &str, rest: &str) -> (TerminalCore, TerminalCore) {
    let mut host = mirror(80, 24);
    host.feed(first_prompt.as_bytes());
    let frame = String::from_utf8(replay_frame(&host, 1000).unwrap()).unwrap();
    let mut live = renderer(80, 24);
    live.feed(format!("{first_prompt}{rest}").as_bytes());
    let mut page = renderer(80, 24);
    page.feed(frame.as_bytes());
    assert_eq!(
        page.line_editor_state(),
        LineEditorState::Owned,
        "{frame:?}"
    );
    page.feed(rest.as_bytes());
    (live, page)
}

fn assert_first_command_has_its_block(live: &TerminalCore, page: &TerminalCore) {
    let blocks = block_summary(page);
    assert_eq!(blocks, block_summary(live));
    assert_eq!(blocks[0].0, "echo hello");
    assert_eq!(blocks[0].1, "/tmp");
    assert!(
        blocks.iter().all(|block| block.2 != BlockSource::Synthetic),
        "{blocks:?}"
    );
}

#[test]
fn a_page_that_attaches_after_bashs_first_suppressed_prompt_gives_the_first_command_its_block() {
    let (live, page) =
        attached_after_the_first_prompt(REAL_BASH_FIRST_PROMPT, REAL_BASH_FIRST_COMMAND);
    assert_first_command_has_its_block(&live, &page);
}

#[test]
fn a_page_that_attaches_after_zshs_first_suppressed_prompt_gives_the_first_command_its_block() {
    let rest = format!(
        "echo hello\r\n\x1b]7000;v=1;id=t-1;cmd=echo%20hello\x1b\\\x1b]7000;v=1;input-released=1\x07\x1b]133;C\x07hello\r\n\x1b]7000;v=1;id=t-1;exit=0\x1b\\\x1b]133;D;0\x07{}",
        zsh_prompt("t-2")
    );
    let (live, page) = attached_after_the_first_prompt(&zsh_prompt("t-1"), &rest);
    assert_first_command_has_its_block(&live, &page);
}
