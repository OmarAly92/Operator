use regex_automata::meta::Regex;

const NFA_SIZE_LIMIT: usize = 1 << 20;

pub struct MarkRegex {
    regex: Regex,
}

impl MarkRegex {
    pub fn new(pattern: &str) -> Option<MarkRegex> {
        if pattern.is_empty() {
            return None;
        }
        Regex::builder()
            .configure(Regex::config().nfa_size_limit(Some(NFA_SIZE_LIMIT)))
            .build(pattern)
            .ok()
            .map(|regex| MarkRegex { regex })
    }

    pub fn utf16_ranges(&self, text: &str) -> Vec<u32> {
        let mut out = Vec::new();
        let mut cursor = Utf16Cursor::new(text);
        for found in self.regex.find_iter(text) {
            if found.start() == found.end() {
                continue;
            }
            out.push(cursor.advance_to(found.start()));
            out.push(cursor.advance_to(found.end()));
        }
        out
    }
}

struct Utf16Cursor<'a> {
    text: &'a str,
    byte: usize,
    units: u32,
}

impl<'a> Utf16Cursor<'a> {
    fn new(text: &'a str) -> Self {
        Utf16Cursor {
            text,
            byte: 0,
            units: 0,
        }
    }

    fn advance_to(&mut self, byte: usize) -> u32 {
        for ch in self.text[self.byte..byte].chars() {
            self.units += ch.len_utf16() as u32;
        }
        self.byte = byte;
        self.units
    }
}
