use vt_core::{LineEditorState, OwnedPrompt, TerminalCore};

use crate::block_marks::percent_encode_into;

const PROMPT_START: &str = "\x1b]133;A\x1b\\";
const INPUT_READY: &str = "\x1b]7000;v=1;input-ready=1\x1b\\";
const INPUT_RELEASED: &str = "\x1b]7000;v=1;input-released=1\x1b\\";

pub(crate) fn write_line_editor_marks(
    text: &mut String,
    core: &TerminalCore,
    first: usize,
    cursor_row: usize,
) {
    match core.line_editor_state() {
        LineEditorState::Owned => {
            if let Some(prompt) = core.owned_prompt() {
                write_owned_prompt(text, &prompt, first, cursor_row, core.rows());
            }
        }
        LineEditorState::Released => text.push_str(INPUT_RELEASED),
        LineEditorState::Unknown => {}
    }
}

fn write_owned_prompt(
    text: &mut String,
    prompt: &OwnedPrompt,
    first: usize,
    cursor_row: usize,
    screen_rows: usize,
) {
    let placed = prompt.first_row >= first
        && prompt.first_row <= prompt.input_row
        && prompt.input_row <= cursor_row
        && cursor_row - prompt.first_row < screen_rows;
    if !placed {
        text.push_str(INPUT_READY);
        return;
    }
    move_rows(text, cursor_row - prompt.first_row, 'A');
    if !prompt.cwd.is_empty() || !prompt.git_branch.is_empty() {
        text.push_str("\x1b]7000;v=1;cwd=");
        percent_encode_into(text, &prompt.cwd);
        text.push_str(";branch=");
        percent_encode_into(text, &prompt.git_branch);
        text.push_str("\x1b\\");
    }
    text.push_str(PROMPT_START);
    move_rows(text, prompt.input_row - prompt.first_row, 'B');
    text.push_str(INPUT_READY);
    move_rows(text, cursor_row - prompt.input_row, 'B');
}

fn move_rows(text: &mut String, rows: usize, direction: char) {
    if rows > 0 {
        text.push_str(&format!("\x1b[{rows}{direction}"));
    }
}
