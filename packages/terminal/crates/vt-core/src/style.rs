#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct StyleCode(u32);

impl StyleCode {
    pub const DEFAULT: Self = Self(255);

    pub const fn ansi(index: u8) -> Self {
        Self(index as u32)
    }

    pub const fn value(self) -> u32 {
        self.0
    }
}
