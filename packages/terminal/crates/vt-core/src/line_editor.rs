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
    typeahead: Option<String>,
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
        self.typeahead = None;
    }

    pub fn on_alt_screen_enter(&mut self) {
        self.state = LineEditorState::Released;
        self.typeahead = None;
    }

    pub fn on_typeahead(&mut self, text: &str) {
        if self.state == LineEditorState::Owned && !text.is_empty() {
            self.typeahead = Some(text.to_string());
        }
    }

    pub fn take_typeahead(&mut self) -> Option<String> {
        self.typeahead.take()
    }
}
