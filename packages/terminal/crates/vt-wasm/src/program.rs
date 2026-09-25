use vt_core::program::ProgramNotification;
use wasm_bindgen::prelude::*;

use crate::WasmTerminalCore;

pub fn flatten_notifications(notifications: Vec<ProgramNotification>) -> Vec<String> {
    notifications
        .into_iter()
        .flat_map(|notification| [notification.title, notification.body])
        .collect()
}

#[wasm_bindgen]
impl WasmTerminalCore {
    pub fn program_generation(&self) -> u32 {
        self.core.program_generation() as u32
    }

    pub fn title(&self) -> String {
        self.core.title().to_string()
    }

    pub fn pointer_shape(&self) -> String {
        self.core.pointer_shape().to_string()
    }

    pub fn take_notifications(&mut self) -> Vec<String> {
        flatten_notifications(self.core.take_notifications())
    }
}
