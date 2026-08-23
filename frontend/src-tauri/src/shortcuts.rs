use std::collections::HashMap;

use serde::Deserialize;
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

pub const MAIN_WINDOW_LABEL: &str = "main";

const WIRE_NEW_SESSION: &str = "new-session";
const WIRE_NEW_SHELL_TERMINAL: &str = "new-shell-terminal";
const WIRE_CLOSE_SHELL_TERMINAL: &str = "close-shell-terminal";
const WIRE_KEYBOARD_SHORTCUTS: &str = "keyboard-shortcuts";
const WIRE_OPEN_SETTINGS: &str = "open-settings";
const WIRE_PREVIOUS_SESSION: &str = "previous-session";
const WIRE_NEXT_SESSION: &str = "next-session";
const WIRE_PREVIOUS_TAB: &str = "previous-tab";
const WIRE_NEXT_TAB: &str = "next-tab";
const WIRE_FOCUS_TERMINAL: &str = "focus-terminal";

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ShortcutId {
    NewSession,
    NewShellTerminal,
    CloseShellTerminal,
    KeyboardShortcuts,
    OpenSettings,
    PreviousSession,
    NextSession,
    PreviousTab,
    NextTab,
    FocusTerminal,
}

impl ShortcutId {
    pub const PRIORITY_ORDER: [ShortcutId; 10] = [
        ShortcutId::NewSession,
        ShortcutId::NewShellTerminal,
        ShortcutId::CloseShellTerminal,
        ShortcutId::KeyboardShortcuts,
        ShortcutId::OpenSettings,
        ShortcutId::PreviousSession,
        ShortcutId::NextSession,
        ShortcutId::PreviousTab,
        ShortcutId::NextTab,
        ShortcutId::FocusTerminal,
    ];

    fn wire_id(self) -> &'static str {
        match self {
            ShortcutId::NewSession => WIRE_NEW_SESSION,
            ShortcutId::NewShellTerminal => WIRE_NEW_SHELL_TERMINAL,
            ShortcutId::CloseShellTerminal => WIRE_CLOSE_SHELL_TERMINAL,
            ShortcutId::KeyboardShortcuts => WIRE_KEYBOARD_SHORTCUTS,
            ShortcutId::OpenSettings => WIRE_OPEN_SETTINGS,
            ShortcutId::PreviousSession => WIRE_PREVIOUS_SESSION,
            ShortcutId::NextSession => WIRE_NEXT_SESSION,
            ShortcutId::PreviousTab => WIRE_PREVIOUS_TAB,
            ShortcutId::NextTab => WIRE_NEXT_TAB,
            ShortcutId::FocusTerminal => WIRE_FOCUS_TERMINAL,
        }
    }

    pub fn event_name(self) -> &'static str {
        match self {
            ShortcutId::NewSession => "shortcut:new-session",
            ShortcutId::NewShellTerminal => "shortcut:new-shell-terminal",
            ShortcutId::CloseShellTerminal => "shortcut:close-shell-terminal",
            ShortcutId::KeyboardShortcuts => "shortcut:help",
            ShortcutId::OpenSettings => "shortcut:open-settings",
            ShortcutId::PreviousSession => "shortcut:previous-session",
            ShortcutId::NextSession => "shortcut:next-session",
            ShortcutId::PreviousTab => "shortcut:previous-tab",
            ShortcutId::NextTab => "shortcut:next-tab",
            ShortcutId::FocusTerminal => "shortcut:focus-terminal",
        }
    }

    fn from_wire_id(raw: &str) -> Option<Self> {
        Some(match raw {
            WIRE_NEW_SESSION => ShortcutId::NewSession,
            WIRE_NEW_SHELL_TERMINAL => ShortcutId::NewShellTerminal,
            WIRE_CLOSE_SHELL_TERMINAL => ShortcutId::CloseShellTerminal,
            WIRE_KEYBOARD_SHORTCUTS => ShortcutId::KeyboardShortcuts,
            WIRE_OPEN_SETTINGS => ShortcutId::OpenSettings,
            WIRE_PREVIOUS_SESSION => ShortcutId::PreviousSession,
            WIRE_NEXT_SESSION => ShortcutId::NextSession,
            WIRE_PREVIOUS_TAB => ShortcutId::PreviousTab,
            WIRE_NEXT_TAB => ShortcutId::NextTab,
            WIRE_FOCUS_TERMINAL => ShortcutId::FocusTerminal,
            _ => return None,
        })
    }
}

pub fn event_name_for_wire_id(raw: &str) -> Option<&'static str> {
    ShortcutId::from_wire_id(raw).map(ShortcutId::event_name)
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct Binding {
    #[serde(default)]
    pub key: String,
    #[serde(default)]
    pub code: Option<String>,
    #[serde(default)]
    pub ctrl: bool,
    #[serde(default)]
    pub meta: bool,
    #[serde(default)]
    pub shift: bool,
    #[serde(default)]
    pub alt: bool,
}

fn binding(key: &str, ctrl: bool, meta: bool, shift: bool, alt: bool) -> Binding {
    Binding {
        key: key.to_string(),
        code: None,
        ctrl,
        meta,
        shift,
        alt,
    }
}

pub fn default_bindings(id: ShortcutId, is_mac: bool) -> Vec<Binding> {
    match (id, is_mac) {
        (ShortcutId::NewSession, true) => vec![binding("n", false, true, false, false)],
        (ShortcutId::NewSession, false) => vec![binding("n", true, false, true, false)],
        (ShortcutId::NewShellTerminal, true) => vec![binding("t", false, true, false, false)],
        (ShortcutId::NewShellTerminal, false) => vec![binding("t", true, false, false, false)],
        (ShortcutId::CloseShellTerminal, true) => vec![binding("w", false, true, false, false)],
        (ShortcutId::CloseShellTerminal, false) => vec![binding("w", true, false, false, false)],
        (ShortcutId::KeyboardShortcuts, true) => vec![binding("/", false, true, false, false)],
        (ShortcutId::KeyboardShortcuts, false) => vec![binding("/", true, false, false, false)],
        (ShortcutId::OpenSettings, true) => vec![binding(",", false, true, false, false)],
        (ShortcutId::OpenSettings, false) => vec![binding(",", true, false, false, false)],
        (ShortcutId::PreviousSession, true) => vec![binding("ArrowUp", false, true, false, true)],
        (ShortcutId::PreviousSession, false) => vec![binding("PageUp", true, false, false, false)],
        (ShortcutId::NextSession, true) => vec![binding("ArrowDown", false, true, false, true)],
        (ShortcutId::NextSession, false) => vec![binding("PageDown", true, false, false, false)],
        (ShortcutId::PreviousTab, _) => vec![binding("Tab", true, false, true, false)],
        (ShortcutId::NextTab, _) => vec![binding("Tab", true, false, false, false)],
        (ShortcutId::FocusTerminal, true) => vec![binding("t", false, true, true, false)],
        (ShortcutId::FocusTerminal, false) => vec![binding("t", true, false, true, false)],
    }
}

fn raw_char_token(raw: &str) -> Option<&'static str> {
    Some(match raw {
        "`" | "~" => "BACKQUOTE",
        "\\" => "BACKSLASH",
        "[" | "{" => "BRACKETLEFT",
        "]" | "}" => "BRACKETRIGHT",
        "," | "<" => "COMMA",
        "." | ">" => "PERIOD",
        ";" | ":" => "SEMICOLON",
        "'" | "\"" => "QUOTE",
        "/" | "?" => "SLASH",
        "-" | "_" => "MINUS",
        "=" | "+" => "EQUAL",
        _ => return None,
    })
}

const NAMED_KEY_TOKENS: [&str; 38] = [
    "BACKQUOTE",
    "BACKSLASH",
    "BRACKETLEFT",
    "BRACKETRIGHT",
    "COMMA",
    "EQUAL",
    "MINUS",
    "PERIOD",
    "QUOTE",
    "SEMICOLON",
    "SLASH",
    "TAB",
    "ENTER",
    "SPACE",
    "BACKSPACE",
    "DELETE",
    "END",
    "HOME",
    "INSERT",
    "PAGEUP",
    "PAGEDOWN",
    "ARROWUP",
    "ARROWDOWN",
    "ARROWLEFT",
    "ARROWRIGHT",
    "ESCAPE",
    "PRINTSCREEN",
    "SCROLLLOCK",
    "PAUSE",
    "CAPSLOCK",
    "NUMLOCK",
    "NUMPADADD",
    "NUMPADDECIMAL",
    "NUMPADDIVIDE",
    "NUMPADENTER",
    "NUMPADEQUAL",
    "NUMPADMULTIPLY",
    "NUMPADSUBTRACT",
];

fn is_physical_code_name(upper: &str) -> bool {
    (upper.len() == 4
        && upper.starts_with("KEY")
        && upper[3..].chars().all(|c| c.is_ascii_uppercase()))
        || (upper.len() == 6
            && upper.starts_with("DIGIT")
            && upper[5..].chars().all(|c| c.is_ascii_digit()))
        || (upper.len() == 7
            && upper.starts_with("NUMPAD")
            && upper[6..]
                .chars()
                .next()
                .is_some_and(|c| c.is_ascii_digit()))
}

fn f_key_token(upper: &str) -> Option<String> {
    let digits = upper.strip_prefix('F')?;
    if digits.is_empty() || !digits.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let number: u16 = digits.parse().ok()?;
    (1..=24).contains(&number).then(|| upper.to_string())
}

fn key_token(candidate: &str) -> Option<String> {
    let trimmed = candidate.trim();
    if trimmed.is_empty() {
        return None;
    }
    if let Some(named) = raw_char_token(trimmed) {
        return Some(named.to_string());
    }
    let upper = trimmed.to_uppercase();
    let mut chars = upper.chars();
    if let (Some(single), None) = (chars.next(), chars.next()) {
        if single.is_ascii_alphanumeric() {
            return Some(single.to_string());
        }
    }
    if matches!(upper.as_str(), "UP" | "DOWN" | "LEFT" | "RIGHT") {
        return Some(format!("ARROW{upper}"));
    }
    if NAMED_KEY_TOKENS.contains(&upper.as_str()) || is_physical_code_name(&upper) {
        return Some(upper);
    }
    f_key_token(&upper)
}

fn binding_key_token(binding: &Binding) -> Option<String> {
    binding
        .code
        .as_deref()
        .and_then(key_token)
        .or_else(|| key_token(&binding.key))
}

pub fn accelerator_for_binding(binding: &Binding, _is_mac: bool) -> String {
    let mut parts: Vec<String> = Vec::with_capacity(5);
    if binding.meta {
        parts.push("SUPER".to_string());
    }
    if binding.ctrl {
        parts.push("CONTROL".to_string());
    }
    if binding.alt {
        parts.push("ALT".to_string());
    }
    if binding.shift {
        parts.push("SHIFT".to_string());
    }
    match binding_key_token(binding) {
        Some(token) => {
            parts.push(token);
            parts.join("+")
        }
        None => String::new(),
    }
}

fn is_registration_candidate(binding: &Binding) -> bool {
    (binding.ctrl || binding.meta || binding.alt) && binding_key_token(binding).is_some()
}

pub fn coerce_overrides(raw: HashMap<String, Vec<Binding>>) -> HashMap<String, Vec<Binding>> {
    let mut coerced = HashMap::new();
    for (id, bindings) in raw {
        if ShortcutId::from_wire_id(&id).is_none() {
            continue;
        }
        let mut valid: Vec<Binding> = bindings
            .iter()
            .take(2)
            .filter(|candidate| is_registration_candidate(candidate))
            .cloned()
            .collect();
        if valid.len() > 1 {
            let mut seen: Vec<String> = Vec::new();
            valid.retain(|candidate| {
                let accelerator = accelerator_for_binding(candidate, true);
                if seen.contains(&accelerator) {
                    return false;
                }
                seen.push(accelerator);
                true
            });
        }
        if bindings.is_empty() || !valid.is_empty() {
            coerced.insert(id, valid);
        }
    }
    coerced
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Conflict {
    pub winner: ShortcutId,
    pub shadowed: ShortcutId,
    pub accelerator: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RegistrationFailure {
    pub id: ShortcutId,
    pub accelerator: String,
    pub error: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ApplyReport {
    pub conflicts: Vec<Conflict>,
    pub failures: Vec<RegistrationFailure>,
}

pub trait ShortcutRegistrar {
    fn register(&mut self, accelerator: &str, event_name: &str) -> Result<(), String>;
    fn unregister_all(&mut self);
}

pub struct GlobalShortcutRegistrar {
    pub app: tauri::AppHandle,
}

impl ShortcutRegistrar for GlobalShortcutRegistrar {
    fn register(&mut self, accelerator: &str, event_name: &str) -> Result<(), String> {
        let event_name = event_name.to_string();
        self.app
            .global_shortcut()
            .on_shortcut(accelerator, move |app, _shortcut, event| {
                if event.state == ShortcutState::Pressed {
                    let _ =
                        tauri::Emitter::emit_to(app, MAIN_WINDOW_LABEL, event_name.as_str(), ());
                }
            })
            .map_err(|error| error.to_string())
    }

    fn unregister_all(&mut self) {
        if let Err(error) = self.app.global_shortcut().unregister_all() {
            eprintln!("failed to unregister global shortcuts: {error}");
        }
    }
}

pub fn probe_global_shortcuts() -> bool {
    match global_hotkey::GlobalHotKeyManager::new() {
        Ok(manager) => {
            drop(manager);
            true
        }
        Err(error) => {
            eprintln!("global shortcuts are unavailable on this platform: {error}");
            false
        }
    }
}

pub struct ShortcutEngine<R: ShortcutRegistrar> {
    registrar: R,
    is_mac: bool,
    overrides: HashMap<String, Vec<Binding>>,
    close_terminal_enabled: bool,
    recording_active: bool,
    window_focused: bool,
    armed: bool,
    registered: Vec<(String, String)>,
}

impl<R: ShortcutRegistrar> ShortcutEngine<R> {
    pub fn new(registrar: R, is_mac: bool) -> Self {
        Self {
            registrar,
            is_mac,
            overrides: HashMap::new(),
            close_terminal_enabled: false,
            recording_active: false,
            window_focused: true,
            armed: false,
            registered: Vec::new(),
        }
    }

    pub fn armed(&self) -> bool {
        self.armed
    }

    pub fn registered(&self) -> &[(String, String)] {
        &self.registered
    }

    pub fn event_for(&self, accelerator: &str) -> Option<&str> {
        self.registered
            .iter()
            .find(|(existing, _)| existing == accelerator)
            .map(|(_, event)| event.as_str())
    }

    pub fn set_window_focused(&mut self, focused: bool) -> ApplyReport {
        self.window_focused = focused;
        self.apply()
    }

    pub fn set_recording(&mut self, active: bool) -> ApplyReport {
        self.recording_active = active;
        self.apply()
    }

    pub fn set_close_terminal_enabled(&mut self, enabled: bool) -> ApplyReport {
        self.close_terminal_enabled = enabled;
        self.apply()
    }

    pub fn set_overrides(&mut self, overrides: HashMap<String, Vec<Binding>>) -> ApplyReport {
        self.overrides = coerce_overrides(overrides);
        self.apply()
    }

    fn desired(&self) -> (Vec<(String, String, ShortcutId)>, Vec<Conflict>) {
        let mut claimed: Vec<(String, ShortcutId)> = Vec::new();
        let mut desired = Vec::new();
        let mut conflicts = Vec::new();
        for id in ShortcutId::PRIORITY_ORDER {
            if id == ShortcutId::CloseShellTerminal && !self.close_terminal_enabled {
                continue;
            }
            let bindings = match self.overrides.get(id.wire_id()) {
                Some(bindings) => bindings.clone(),
                None => default_bindings(id, self.is_mac),
            };
            let mut seen_in_id: Vec<String> = Vec::new();
            for binding in bindings {
                if !is_registration_candidate(&binding) {
                    continue;
                }
                let accelerator = accelerator_for_binding(&binding, self.is_mac);
                if accelerator.is_empty() || seen_in_id.contains(&accelerator) {
                    continue;
                }
                seen_in_id.push(accelerator.clone());
                if let Some((_, winner)) = claimed
                    .iter()
                    .find(|(existing, _)| *existing == accelerator)
                {
                    conflicts.push(Conflict {
                        winner: *winner,
                        shadowed: id,
                        accelerator,
                    });
                    continue;
                }
                claimed.push((accelerator.clone(), id));
                desired.push((accelerator, id.event_name().to_string(), id));
            }
        }
        (desired, conflicts)
    }

    pub fn apply(&mut self) -> ApplyReport {
        let should_arm = self.window_focused && !self.recording_active;
        if !should_arm {
            if self.armed {
                self.registrar.unregister_all();
                self.registered.clear();
                self.armed = false;
            }
            return ApplyReport::default();
        }
        let (desired, conflicts) = self.desired();
        self.registrar.unregister_all();
        self.registered.clear();
        let mut failures = Vec::new();
        for (accelerator, event_name, id) in desired {
            match self.registrar.register(&accelerator, &event_name) {
                Ok(()) => self.registered.push((accelerator, event_name)),
                Err(error) => failures.push(RegistrationFailure {
                    id,
                    accelerator,
                    error,
                }),
            }
        }
        self.armed = true;
        ApplyReport {
            conflicts,
            failures,
        }
    }
}
