#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct StyleCode(u32);

const TAG_INDEXED: u32 = 0x0100_0000;
const TAG_RGB: u32 = 0x0200_0000;
const COLOUR_MASK: u32 = 0x03ff_ffff;
const FLAG_BOLD: u32 = 0x0400_0000;
const FLAG_DIM: u32 = 0x0800_0000;
const FLAG_REVERSE: u32 = 0x1000_0000;

impl StyleCode {
    pub const DEFAULT: Self = Self(255);

    pub const DEFAULT_BACKGROUND: Self = Self(254);

    pub const fn ansi(index: u8) -> Self {
        Self(index as u32)
    }

    pub const fn indexed(index: u8) -> Self {
        if index < 16 {
            Self::ansi(index)
        } else {
            Self(TAG_INDEXED | index as u32)
        }
    }

    pub const fn rgb(red: u8, green: u8, blue: u8) -> Self {
        Self(TAG_RGB | ((red as u32) << 16) | ((green as u32) << 8) | blue as u32)
    }

    pub const fn value(self) -> u32 {
        self.0
    }

    pub const fn colour(self) -> Self {
        Self(self.0 & COLOUR_MASK)
    }

    pub const fn with_colour(self, colour: Self) -> Self {
        Self((self.0 & !COLOUR_MASK) | (colour.0 & COLOUR_MASK))
    }

    pub const fn with_bold(self, on: bool) -> Self {
        if on {
            Self(self.0 | FLAG_BOLD)
        } else {
            Self(self.0 & !FLAG_BOLD)
        }
    }

    pub const fn with_dim(self, on: bool) -> Self {
        if on {
            Self(self.0 | FLAG_DIM)
        } else {
            Self(self.0 & !FLAG_DIM)
        }
    }

    pub const fn with_reverse(self, on: bool) -> Self {
        if on {
            Self(self.0 | FLAG_REVERSE)
        } else {
            Self(self.0 & !FLAG_REVERSE)
        }
    }

    pub const fn is_bold(self) -> bool {
        self.0 & FLAG_BOLD != 0
    }

    pub const fn is_dim(self) -> bool {
        self.0 & FLAG_DIM != 0
    }

    pub const fn is_reverse(self) -> bool {
        self.0 & FLAG_REVERSE != 0
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct Attrs(u16);

impl Attrs {
    pub const NONE: Self = Self(0);
    pub const ITALIC: u16 = 1 << 0;
    pub const UNDERLINE: u16 = 1 << 1;
    pub const DOUBLE_UNDERLINE: u16 = 1 << 2;
    pub const CURLY_UNDERLINE: u16 = 1 << 3;
    pub const DOTTED_UNDERLINE: u16 = 1 << 4;
    pub const DASHED_UNDERLINE: u16 = 1 << 5;
    pub const STRIKE: u16 = 1 << 6;
    pub const BLINK: u16 = 1 << 7;
    pub const HIDDEN: u16 = 1 << 8;
    pub const OVERLINE: u16 = 1 << 9;
    pub const ALL_UNDERLINES: u16 = Self::UNDERLINE
        | Self::DOUBLE_UNDERLINE
        | Self::CURLY_UNDERLINE
        | Self::DOTTED_UNDERLINE
        | Self::DASHED_UNDERLINE;

    pub const fn from_bits(bits: u16) -> Self {
        Self(bits)
    }

    pub const fn bits(self) -> u16 {
        self.0
    }

    pub const fn is_empty(self) -> bool {
        self.0 == 0
    }

    pub const fn contains(self, flag: u16) -> bool {
        self.0 & flag == flag
    }

    pub const fn with(self, flag: u16, on: bool) -> Self {
        if on {
            Self(self.0 | flag)
        } else {
            Self(self.0 & !flag)
        }
    }

    pub const fn without(self, mask: u16) -> Self {
        Self(self.0 & !mask)
    }

    pub const fn with_underline(self, kind: u16) -> Self {
        Self((self.0 & !Self::ALL_UNDERLINES) | kind)
    }
}

use crate::hyperlink::LinkId;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CellStyle {
    pub fg: StyleCode,
    pub bg: StyleCode,
    pub attrs: Attrs,
    pub underline: StyleCode,
    pub link: LinkId,
}

impl CellStyle {
    pub const DEFAULT: Self = Self {
        fg: StyleCode::DEFAULT,
        bg: StyleCode::DEFAULT_BACKGROUND,
        attrs: Attrs::NONE,
        underline: StyleCode::DEFAULT,
        link: 0,
    };

    pub const fn new(fg: StyleCode, bg: StyleCode) -> Self {
        Self {
            fg,
            bg,
            attrs: Attrs::NONE,
            underline: StyleCode::DEFAULT,
            link: 0,
        }
    }

    pub const fn from_fg(fg: StyleCode) -> Self {
        Self::new(fg, StyleCode::DEFAULT_BACKGROUND)
    }

    pub const fn resolved(self) -> Self {
        if !self.fg.is_reverse() {
            return self;
        }
        Self {
            fg: self.fg.with_reverse(false).with_colour(self.bg.colour()),
            bg: self.fg.colour(),
            attrs: self.attrs,
            underline: self.underline,
            link: self.link,
        }
    }

    pub const fn is_default_paint(self) -> bool {
        self.fg.value() == StyleCode::DEFAULT.value()
            && self.bg.value() == StyleCode::DEFAULT_BACKGROUND.value()
    }
}
