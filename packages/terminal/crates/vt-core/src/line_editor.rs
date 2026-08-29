#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum LineEditorState {
    #[default]
    Unknown,
    Owned,
    Released,
}

impl LineEditorState {
    pub fn wire(self) -> u32 {
        match self {
            LineEditorState::Unknown => 0,
            LineEditorState::Owned => 1,
            LineEditorState::Released => 2,
        }
    }
}

#[derive(Default)]
pub struct LineEditorTracker {
    state: LineEditorState,
}

impl LineEditorTracker {
    pub fn state(&self) -> LineEditorState {
        self.state
    }

    pub fn on_input_ready(&mut self) {
        self.state = LineEditorState::Owned;
    }

    pub fn on_input_released(&mut self) {
        self.state = LineEditorState::Released;
    }

    pub fn on_alt_screen_enter(&mut self) {
        self.state = LineEditorState::Released;
    }
}
