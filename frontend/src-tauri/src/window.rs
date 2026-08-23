#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct OverlayColors {
    pub color: (u8, u8, u8),
    pub symbol_color: (u8, u8, u8),
}

fn parse_hex_color(raw: &str) -> Option<(u8, u8, u8)> {
    let hex = raw.strip_prefix('#')?;
    if hex.len() != 6 && hex.len() != 8 {
        return None;
    }
    if !hex.chars().all(|character| character.is_ascii_hexdigit()) {
        return None;
    }
    Some((
        u8::from_str_radix(&hex[0..2], 16).ok()?,
        u8::from_str_radix(&hex[2..4], 16).ok()?,
        u8::from_str_radix(&hex[4..6], 16).ok()?,
    ))
}

pub fn overlay_colors(color: &str, symbol_color: &str) -> Option<OverlayColors> {
    if color.trim().is_empty() || symbol_color.trim().is_empty() {
        return None;
    }
    Some(OverlayColors {
        color: parse_hex_color(color.trim())?,
        symbol_color: parse_hex_color(symbol_color.trim())?,
    })
}

impl OverlayColors {
    pub fn caption_colorref(&self) -> u32 {
        rgb_to_colorref(self.color)
    }

    pub fn text_colorref(&self) -> u32 {
        rgb_to_colorref(self.symbol_color)
    }
}

pub fn rgb_to_colorref((red, green, blue): (u8, u8, u8)) -> u32 {
    u32::from(blue) << 16 | u32::from(green) << 8 | u32::from(red)
}

#[derive(Default)]
pub struct FullscreenTracker {
    active: bool,
}

impl FullscreenTracker {
    pub fn update(&mut self, current: bool) -> Option<bool> {
        if self.active == current {
            return None;
        }
        self.active = current;
        Some(current)
    }
}

pub fn fullscreen_transitions<I>(states: I) -> Vec<bool>
where
    I: IntoIterator<Item = bool>,
{
    let mut tracker = FullscreenTracker::default();
    states
        .into_iter()
        .filter_map(|state| tracker.update(state))
        .collect()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ThemePreference {
    Light,
    Dark,
    System,
}

pub const NATIVE_WINDOW_BACKGROUND_DARK: (u8, u8, u8) = (0x0f, 0x10, 0x14);
pub const NATIVE_WINDOW_BACKGROUND_LIGHT: (u8, u8, u8) = (0xfb, 0xfb, 0xfb);

pub fn theme_preference(preference: &str) -> Option<ThemePreference> {
    match preference {
        "light" => Some(ThemePreference::Light),
        "dark" => Some(ThemePreference::Dark),
        "system" => Some(ThemePreference::System),
        _ => None,
    }
}

pub fn resolved_background(
    preference: ThemePreference,
    os_theme_dark: bool,
) -> Option<(u8, u8, u8)> {
    let dark = match preference {
        ThemePreference::Light => false,
        ThemePreference::Dark => true,
        ThemePreference::System => os_theme_dark,
    };
    Some(if dark {
        NATIVE_WINDOW_BACKGROUND_DARK
    } else {
        NATIVE_WINDOW_BACKGROUND_LIGHT
    })
}

#[cfg(test)]
mod tests {
    use super::{parse_hex_color, rgb_to_colorref};

    #[test]
    fn colorref_layout_matches_win32_rgb_ordering() {
        assert_eq!(rgb_to_colorref((0x17, 0x18, 0x1c)), 0x001c1817);
        assert_eq!(parse_hex_color("#17181c"), Some((0x17, 0x18, 0x1c)));
    }
}
