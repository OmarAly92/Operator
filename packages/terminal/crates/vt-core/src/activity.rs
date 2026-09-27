pub mod compact;
pub mod input_patterns;

use crate::{LineEditorState, TerminalCore};

pub const ACTIVITY_POLLING_AFTER_MS: u64 = 500;
pub const ACTIVITY_IDLE_AFTER_MS: u64 = 1_500;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AgentActivity {
    Active,
    PollingForIdle,
    Idle,
    Prompting,
}

impl AgentActivity {
    pub fn wire(self) -> u32 {
        match self {
            AgentActivity::Active => 0,
            AgentActivity::PollingForIdle => 1,
            AgentActivity::Idle => 2,
            AgentActivity::Prompting => 3,
        }
    }
}

impl TerminalCore {
    pub fn agent_activity(&self, quiet_ms: Option<u64>) -> AgentActivity {
        let quiet = quiet_ms.unwrap_or(u64::MAX);
        if quiet < ACTIVITY_POLLING_AFTER_MS {
            return AgentActivity::Active;
        }
        if self.cursor_line_prompts() {
            return AgentActivity::Prompting;
        }
        if quiet < ACTIVITY_IDLE_AFTER_MS {
            AgentActivity::PollingForIdle
        } else {
            AgentActivity::Idle
        }
    }

    pub fn cursor_line_prompts(&self) -> bool {
        !matches!(self.line_editor_state(), LineEditorState::Owned)
            && input_patterns::detects_high_confidence_input_pattern(&self.cursor_line_text())
    }

    pub fn cursor_line_text(&self) -> String {
        let screen = match self.parser.alt() {
            Some(alt) => alt,
            None => self.parser.screen(),
        };
        let (row, column) = screen.cursor();
        let columns = screen.cols();
        let last = (0..columns).rev().find(|&col| {
            screen
                .cell_ref(row, col)
                .is_some_and(|cell| !matches!(cell.ch, ' ' | '\0'))
        });
        let end = last.map_or(0, |col| col + 1).max(column).min(columns);
        let mut out = String::new();
        let mut buffer = [0u8; 4];
        for col in 0..end {
            match screen.cell_ref(row, col) {
                Some(cell) if cell.ch == '\0' => {}
                Some(cell) => out.push_str(cell.text(&mut buffer)),
                None => out.push(' '),
            }
        }
        out
    }
}
