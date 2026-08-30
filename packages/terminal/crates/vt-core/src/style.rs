#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct StyleCode(u32);

const TAG_INDEXED: u32 = 0x0100_0000;
const TAG_RGB: u32 = 0x0200_0000;
const COLOUR_MASK: u32 = 0x03ff_ffff;
const FLAG_BOLD: u32 = 0x0400_0000;
const FLAG_DIM: u32 = 0x0800_0000;

impl StyleCode {
    pub const DEFAULT: Self = Self(255);

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

    pub const fn is_bold(self) -> bool {
        self.0 & FLAG_BOLD != 0
    }

    pub const fn is_dim(self) -> bool {
        self.0 & FLAG_DIM != 0
    }
}
