use vt_core::agent::AgentEvent;
use vt_core::program::ProgramNotification;
use wasm_bindgen::prelude::*;

use crate::WasmTerminalCore;

pub fn flatten_notifications(notifications: Vec<ProgramNotification>) -> Vec<String> {
    notifications
        .into_iter()
        .flat_map(|notification| [notification.title, notification.body])
        .collect()
}

pub fn flatten_agent_events(events: Vec<AgentEvent>) -> Vec<String> {
    events
        .into_iter()
        .flat_map(|event| [event.state.as_str().to_string(), event.detail])
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

    pub fn take_agent_events(&mut self) -> Vec<String> {
        flatten_agent_events(self.core.take_agent_events())
    }

    pub fn live_output_bytes(&self) -> f64 {
        self.core.live_output_bytes() as f64
    }

    pub fn unknown_sequences(&self) -> Vec<String> {
        self.core
            .unknown_sequences()
            .into_iter()
            .map(|entry| format!("{} {}", entry.count, entry.text))
            .collect()
    }
}
