use std::collections::VecDeque;

mod pointer;

pub use pointer::pointer_shape_css;

pub const MAX_TITLE_BYTES: usize = 1024;
pub const TITLE_STACK_MAX_DEPTH: usize = 4096;
pub const MAX_PENDING_NOTIFICATIONS: usize = 16;
pub const MAX_NOTIFICATION_TITLE_BYTES: usize = 1024;
pub const MAX_NOTIFICATION_BODY_BYTES: usize = 2048;
const CONEMU_MAX_COMMAND: u8 = 12;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProgramNotification {
    pub title: String,
    pub body: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OscKind {
    Hyperlink,
    Title,
    IconName,
    Notification,
    RxvtExtension,
    KittyNotification,
    DynamicColor,
    PointerShape,
    Other,
}

impl OscKind {
    pub fn of(params: &[&[u8]]) -> Self {
        match params.first().copied() {
            Some(b"8") => Self::Hyperlink,
            Some(b"0") | Some(b"2") => Self::Title,
            Some(b"1") => Self::IconName,
            Some(b"9") => Self::Notification,
            Some(b"777") => Self::RxvtExtension,
            Some(b"99") => Self::KittyNotification,
            Some(b"10") | Some(b"11") => Self::DynamicColor,
            Some(b"22") => Self::PointerShape,
            _ => Self::Other,
        }
    }
}

#[derive(Debug, Default)]
struct KittyPending {
    id: String,
    title: String,
    body: String,
}

#[derive(Debug, Default)]
pub struct ProgramState {
    title: String,
    title_stack: VecDeque<String>,
    pointer_shape: &'static str,
    notifications: VecDeque<ProgramNotification>,
    kitty: Option<KittyPending>,
    generation: u64,
    cell_pixels: Option<(u32, u32)>,
    foreground: Option<u32>,
    background: Option<u32>,
    in_band_resize: bool,
    agent: crate::agent::AgentChannel,
}

impl ProgramState {
    pub fn title(&self) -> &str {
        &self.title
    }

    pub fn pointer_shape(&self) -> &'static str {
        self.pointer_shape
    }

    pub fn generation(&self) -> u64 {
        self.generation
    }

    pub fn title_stack_depth(&self) -> usize {
        self.title_stack.len()
    }

    pub fn in_band_resize(&self) -> bool {
        self.in_band_resize
    }

    pub fn take_notifications(&mut self) -> Vec<ProgramNotification> {
        self.notifications.drain(..).collect()
    }

    pub fn agent(&self) -> &crate::agent::AgentChannel {
        &self.agent
    }

    pub fn agent_mut(&mut self) -> &mut crate::agent::AgentChannel {
        &mut self.agent
    }

    pub fn osc(&mut self, params: &[&[u8]], bell_terminated: bool) -> Option<Vec<u8>> {
        match OscKind::of(params) {
            OscKind::Title => {
                self.set_title(joined(&params[1..]));
                None
            }
            OscKind::Notification => {
                self.osc9(&params[1..]);
                None
            }
            OscKind::RxvtExtension => {
                self.osc777(&params[1..]);
                None
            }
            OscKind::KittyNotification => {
                self.osc99(&params[1..]);
                None
            }
            OscKind::PointerShape => {
                self.osc22(&params[1..]);
                None
            }
            OscKind::DynamicColor => self.color_reply(params, bell_terminated),
            OscKind::Hyperlink | OscKind::IconName | OscKind::Other => None,
        }
    }

    pub fn set_title(&mut self, raw: Vec<u8>) {
        let title = clean_text(&raw, MAX_TITLE_BYTES);
        if title != self.title {
            self.title = title;
            self.bump();
        }
    }

    pub fn push_title(&mut self) {
        if self.title_stack.len() >= TITLE_STACK_MAX_DEPTH {
            self.title_stack.pop_front();
        }
        self.title_stack.push_back(self.title.clone());
    }

    pub fn pop_title(&mut self) {
        if let Some(title) = self.title_stack.pop_back() {
            if title != self.title {
                self.title = title;
                self.bump();
            }
        }
    }

    pub fn reset_for_new_process(&mut self) {
        let changed = !self.title.is_empty() || !self.pointer_shape.is_empty();
        self.title.clear();
        self.title_stack.clear();
        self.pointer_shape = "";
        self.kitty = None;
        self.in_band_resize = false;
        self.agent.reset_for_new_process();
        if changed {
            self.bump();
        }
    }

    pub fn set_cell_pixels(&mut self, width: u32, height: u32) -> bool {
        let next = (width > 0 && height > 0).then_some((width, height));
        let changed = next != self.cell_pixels;
        self.cell_pixels = next;
        changed
    }

    pub fn set_default_colors(&mut self, foreground: Option<u32>, background: Option<u32>) {
        self.foreground = foreground.map(|rgb| rgb & 0x00ff_ffff);
        self.background = background.map(|rgb| rgb & 0x00ff_ffff);
    }

    pub fn set_in_band_resize(&mut self, on: bool) {
        self.in_band_resize = on;
    }

    pub fn size_report(&self, kind: u16, columns: usize, rows: usize) -> Option<Vec<u8>> {
        match kind {
            14 => {
                let (width, height) = self.cell_pixels?;
                Some(
                    format!(
                        "\x1b[4;{};{}t",
                        rows as u64 * u64::from(height),
                        columns as u64 * u64::from(width)
                    )
                    .into_bytes(),
                )
            }
            16 => {
                let (width, height) = self.cell_pixels?;
                Some(format!("\x1b[6;{height};{width}t").into_bytes())
            }
            18 => Some(format!("\x1b[8;{rows};{columns}t").into_bytes()),
            _ => None,
        }
    }

    pub fn in_band_report(&self, columns: usize, rows: usize) -> Option<Vec<u8>> {
        if !self.in_band_resize {
            return None;
        }
        let (width, height) = self.cell_pixels?;
        Some(
            format!(
                "\x1b[48;{rows};{columns};{};{}t",
                rows as u64 * u64::from(height),
                columns as u64 * u64::from(width)
            )
            .into_bytes(),
        )
    }

    fn bump(&mut self) {
        self.generation = self.generation.wrapping_add(1);
    }

    fn notify(&mut self, title: String, body: String) {
        if title.is_empty() && body.is_empty() {
            return;
        }
        if self.notifications.len() >= MAX_PENDING_NOTIFICATIONS {
            self.notifications.pop_front();
        }
        self.notifications
            .push_back(ProgramNotification { title, body });
        self.bump();
    }

    fn osc9(&mut self, payload: &[&[u8]]) {
        if payload
            .first()
            .is_some_and(|first| is_conemu_command(first))
        {
            return;
        }
        let body = clean_text(&joined(payload), MAX_NOTIFICATION_BODY_BYTES);
        self.notify(String::new(), body);
    }

    fn osc777(&mut self, payload: &[&[u8]]) {
        if payload.first() == Some(&crate::agent::AGENT_EXTENSION) {
            if self.agent.osc(&payload[1..]) {
                self.bump();
            }
            return;
        }
        let [extension, title, body @ ..] = payload else {
            return;
        };
        if *extension != b"notify" {
            return;
        }
        let title = clean_text(title, MAX_NOTIFICATION_TITLE_BYTES);
        let body = clean_text(&joined(body), MAX_NOTIFICATION_BODY_BYTES);
        self.notify(title, body);
    }

    fn osc99(&mut self, payload: &[&[u8]]) {
        let Some((metadata, text)) = payload.split_first() else {
            return;
        };
        let mut id = String::new();
        let mut done = true;
        let mut into_body = false;
        for pair in metadata.split(|byte| *byte == b':') {
            let Some(equals) = pair.iter().position(|byte| *byte == b'=') else {
                continue;
            };
            let (key, value) = (&pair[..equals], &pair[equals + 1..]);
            match key {
                b"i" => id = clean_text(value, 256),
                b"d" => done = value != b"0",
                b"e" if value == b"1" => return,
                b"p" => match value {
                    b"title" => into_body = false,
                    b"body" => into_body = true,
                    _ => return,
                },
                _ => {}
            }
        }
        let pending = match self.kitty.take() {
            Some(pending) if pending.id == id => pending,
            _ => KittyPending {
                id,
                ..KittyPending::default()
            },
        };
        let mut pending = pending;
        let text = String::from_utf8_lossy(&joined(text)).into_owned();
        if into_body {
            append_capped(&mut pending.body, &text, MAX_NOTIFICATION_BODY_BYTES);
        } else {
            append_capped(&mut pending.title, &text, MAX_NOTIFICATION_TITLE_BYTES);
        }
        if done {
            let title = clean_text(pending.title.as_bytes(), MAX_NOTIFICATION_TITLE_BYTES);
            let body = clean_text(pending.body.as_bytes(), MAX_NOTIFICATION_BODY_BYTES);
            self.notify(title, body);
        } else {
            self.kitty = Some(pending);
        }
    }

    fn osc22(&mut self, payload: &[&[u8]]) {
        let name = joined(payload);
        let next = if name.is_empty() {
            ""
        } else {
            match std::str::from_utf8(&name).ok().and_then(pointer_shape_css) {
                Some(css) => css,
                None => return,
            }
        };
        if next != self.pointer_shape {
            self.pointer_shape = next;
            self.bump();
        }
    }

    fn color_reply(&self, params: &[&[u8]], bell_terminated: bool) -> Option<Vec<u8>> {
        let first: u16 = std::str::from_utf8(params.first()?).ok()?.parse().ok()?;
        let mut reply = Vec::new();
        for (index, param) in params[1..].iter().enumerate() {
            if *param != b"?" {
                continue;
            }
            let slot = first + index as u16;
            let rgb = match slot {
                10 => self.foreground,
                11 => self.background,
                _ => None,
            };
            let Some(rgb) = rgb else {
                continue;
            };
            let (r, g, b) = ((rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff);
            reply.extend_from_slice(
                format!("\x1b]{slot};rgb:{r:02x}{r:02x}/{g:02x}{g:02x}/{b:02x}{b:02x}").as_bytes(),
            );
            reply.extend_from_slice(if bell_terminated { b"\x07" } else { b"\x1b\\" });
        }
        (!reply.is_empty()).then_some(reply)
    }
}

fn is_conemu_command(first: &[u8]) -> bool {
    !first.is_empty()
        && first.len() <= 2
        && first.iter().all(u8::is_ascii_digit)
        && std::str::from_utf8(first)
            .ok()
            .and_then(|digits| digits.parse::<u8>().ok())
            .is_some_and(|command| (1..=CONEMU_MAX_COMMAND).contains(&command))
}

fn joined(parts: &[&[u8]]) -> Vec<u8> {
    let mut out = Vec::new();
    for (index, part) in parts.iter().enumerate() {
        if index > 0 {
            out.push(b';');
        }
        out.extend_from_slice(part);
    }
    out
}

pub(crate) fn clean_text(raw: &[u8], cap: usize) -> String {
    let decoded = String::from_utf8_lossy(raw);
    let mut out = String::new();
    for ch in decoded.chars().filter(|ch| !ch.is_control()) {
        if out.len() + ch.len_utf8() > cap {
            break;
        }
        out.push(ch);
    }
    out
}

fn append_capped(target: &mut String, text: &str, cap: usize) {
    for ch in text.chars() {
        if target.len() + ch.len_utf8() > cap {
            return;
        }
        target.push(ch);
    }
}

impl crate::TerminalCore {
    pub fn title(&self) -> &str {
        self.parser.program().title()
    }

    pub fn pointer_shape(&self) -> &'static str {
        self.parser.program().pointer_shape()
    }

    pub fn program_generation(&self) -> u64 {
        self.parser.program().generation()
    }

    pub fn title_stack_depth(&self) -> usize {
        self.parser.program().title_stack_depth()
    }

    pub fn take_notifications(&mut self) -> Vec<ProgramNotification> {
        self.parser.program_mut().take_notifications()
    }

    pub fn set_cell_pixels(&mut self, width: u32, height: u32) {
        if self.parser.program_mut().set_cell_pixels(width, height) {
            self.parser.send_in_band_report();
        }
    }

    pub fn set_default_colors(&mut self, foreground: Option<u32>, background: Option<u32>) {
        self.parser
            .program_mut()
            .set_default_colors(foreground, background);
    }
}
