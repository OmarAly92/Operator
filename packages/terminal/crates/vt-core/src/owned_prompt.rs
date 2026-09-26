use crate::line_editor::LineEditorState;
use crate::TerminalCore;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OwnedPrompt {
    pub first_row: usize,
    pub input_row: usize,
    pub cwd: String,
    pub git_branch: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RunningCommand {
    pub prompt_row: usize,
    pub output_row: usize,
    pub command: String,
    pub cwd: String,
    pub git_branch: String,
    pub started_at_ms: Option<u64>,
}

impl TerminalCore {
    pub fn running_command(&self) -> Option<RunningCommand> {
        let (prompt_row, output_row, meta) = self.parser.running_command()?;
        Some(RunningCommand {
            prompt_row,
            output_row,
            command: meta.command.clone(),
            cwd: meta.cwd.clone(),
            git_branch: meta.git_branch.clone(),
            started_at_ms: meta.started_at_ms,
        })
    }

    pub fn owned_prompt(&self) -> Option<OwnedPrompt> {
        if self.line_editor.state() != LineEditorState::Owned || self.alt_screen.is_active() {
            return None;
        }
        let (first_row, input_row, meta) = self.parser.open_prompt()?;
        Some(OwnedPrompt {
            first_row,
            input_row,
            cwd: meta.cwd.clone(),
            git_branch: meta.git_branch.clone(),
        })
    }

    pub fn command_end(&self) -> Option<(usize, usize)> {
        self.parser.grid().command_end()
    }
}
