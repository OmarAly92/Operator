impl crate::TerminalCore {
    pub fn application_cursor_keys(&self) -> bool {
        self.parser.app_cursor()
    }

    pub fn sgr_mouse(&self) -> bool {
        self.parser.sgr_mouse()
    }

    pub fn bracketed_paste(&self) -> bool {
        self.parser.bracketed_paste()
    }

    pub fn focus_reporting(&self) -> bool {
        self.parser.focus_reporting()
    }

    pub fn mouse_tracking(&self) -> bool {
        self.parser.mouse_tracking()
    }

    pub fn mouse_tracking_level(&self) -> u8 {
        self.parser.mouse_tracking_level()
    }
}
