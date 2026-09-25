use super::Size;

pub struct Rng(u64);

impl Rng {
    pub fn new(seed: u64) -> Self {
        Self(seed | 1)
    }

    pub fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }

    pub fn below(&mut self, bound: usize) -> usize {
        (self.next() % bound as u64) as usize
    }

    pub fn pick<'a>(&mut self, items: &[&'a [u8]]) -> &'a [u8] {
        items[self.below(items.len())]
    }
}

pub struct Synthetic {
    pub name: &'static str,
    pub bytes: Vec<u8>,
    pub sizes: Vec<Size>,
}

const STYLES: [&[u8]; 10] = [
    b"\x1b[0m",
    b"\x1b[1;32m",
    b"\x1b[38;5;123m",
    b"\x1b[48;2;10;20;30m",
    b"\x1b[3;4:3;58;5;9m",
    b"\x1b[7m",
    b"\x1b[2;53m",
    b"\x1b[39;49m",
    b"\x1b[22;23;24m",
    b"\x1b[m",
];

pub fn ascii_heavy(total: usize) -> Vec<u8> {
    let mut rng = Rng::new(0x9e37_79b9_7f4a_7c15);
    let mut out = Vec::with_capacity(total + 256);
    while out.len() < total {
        let len = rng.below(200);
        for _ in 0..len {
            match rng.below(40) {
                0 => out.extend_from_slice(rng.pick(&STYLES)),
                1 => out.push(b'\t'),
                2 => out.extend_from_slice(b"\x1b[K"),
                _ => out.push(b' ' + rng.below(95) as u8),
            }
        }
        out.extend_from_slice(b"\r\n");
    }
    out
}

const UNICODE: [&[u8]; 16] = [
    "é".as_bytes(),
    "中文".as_bytes(),
    "e\u{301}".as_bytes(),
    "👍🏽".as_bytes(),
    "👨‍👩‍👧".as_bytes(),
    "🇪🇬".as_bytes(),
    "\u{600}a".as_bytes(),
    "\u{200b}".as_bytes(),
    "❤\u{fe0f}".as_bytes(),
    b"\xff",
    b"\xc3",
    b"\x80\x80",
    "\u{9b}".as_bytes(),
    b"plain ascii ",
    "\u{1100}\u{1161}\u{11a8}".as_bytes(),
    "abc".as_bytes(),
];

pub fn unicode_mix(total: usize) -> Vec<u8> {
    let mut rng = Rng::new(0x1234_5678_9abc_def1);
    let mut out = Vec::with_capacity(total + 256);
    while out.len() < total {
        out.extend_from_slice(rng.pick(&UNICODE));
        match rng.below(12) {
            0 => out.extend_from_slice(b"\r\n"),
            1 => out.extend_from_slice(rng.pick(&STYLES)),
            2 => out.extend_from_slice(b"\x1b[3D"),
            _ => {}
        }
    }
    out
}

pub fn malformed() -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(b"start\r\n");
    out.extend_from_slice(b"\x1b]0;");
    out.extend(std::iter::repeat_n(b't', 3000));
    out.extend_from_slice(b"\x07after title\r\n");
    out.extend_from_slice(b"\x1b]8;;https://example.com/");
    out.extend(std::iter::repeat_n(b'u', 3000));
    out.extend_from_slice(b"\x1b\\long link\x1b]8;;\x1b\\\r\n");
    out.extend_from_slice(b"\x1b]8;id=a;https://a.example\x1b\\linked\x1b]8;\x1b\\ tail\r\n");
    out.extend_from_slice(b"\x1b[");
    for index in 1..=40 {
        out.extend_from_slice(format!("{index};").as_bytes());
    }
    out.extend_from_slice(b"mforty params\r\n");
    out.extend_from_slice(b"\x1b[?$>p three intermediates\r\n");
    out.extend_from_slice(b"\x1b[>4;2mnot sgr\x1b[?4mnot sgr either\r\n");
    out.extend_from_slice(b"\x1b]0;unterminated\x1b[31mred after unterminated osc\x1b[0m\r\n");
    out.extend_from_slice(
        b"\x1bP1$qm\x1b\\dcs\x1b_apc payload\x1b\\\x1bXsos\x1b\\\x1b^pm\x1b\\\r\n",
    );
    out.extend_from_slice(b"\x1b[3\x18Xcan\x1b[4\x1aYsub\r\n");
    out.extend_from_slice(b"\x1b[99999999999A\x1b[0;0H\x1b[65535;65535H\x1b[H");
    out.extend_from_slice(b"\x1b]777;agent-state;v=1;state=working;detail=x\x07");
    out.extend_from_slice(b"\x1b]777;notify;Title;Body\x07\x1b]9;nine\x07\x1b]99;;kitty\x1b\\");
    out.extend_from_slice(
        b"\x1b]10;?\x07\x1b]11;?\x1b\\\x1b[16t\x1b[14t\x1b[18t\x1b[22;0t\x1b[22;1t\x1b[23;0t",
    );
    out.extend_from_slice(
        b"\x1b[>0q\x1b[c\x1b[0c\x1b[>c\x1b[?2026;1;25;9999$p\x1b[?2048h\x1b[?2048l",
    );
    out.extend_from_slice(b"\x1bZ\x1b#8\x1b(0lqk\x1b(Bf\x1b[3b\r\n");
    out.extend_from_slice(b"\x1b]22;pointer\x07\x1b]22;text\x07\x1b]1;icon\x07\x1b]2;two\x07");
    out.extend_from_slice(b"\x1b[?1;1000;1002;1006;1004;2004h\x1b[?25;1l\x1b[?25h");
    out.extend_from_slice(
        b"\x1b]133;A\x07$ \x1b]133;B\x07ls\r\n\x1b]133;C\x07out\r\n\x1b]133;D;0\x07",
    );
    out.extend_from_slice(b"\x1b[?2026hsync body\r\n\x1b[?2026l");
    out.extend_from_slice(b"\x1b[?2026hunterminated sync");
    out
}

const EDITS: [&[u8]; 22] = [
    b"\x1b[3@",
    b"\x1b[2P",
    b"\x1b[5X",
    b"\x1b[K",
    b"\x1b[1K",
    b"\x1b[2K",
    b"\x1b[J",
    b"\x1b[1J",
    b"\x1b[2L",
    b"\x1b[M",
    b"\x1b[S",
    b"\x1b[2T",
    b"\x1b[3;9r",
    b"\x1b[r",
    b"\x1b[5;7H",
    b"\x1b[A",
    b"\x1b[2B",
    b"\x1b[10G",
    b"\x1bM",
    b"\x1b7\x1b[H\x1b8",
    b"\r\n",
    b"\x1b[2J",
];

const TEXT: [&[u8]; 8] = [
    b"plain words here",
    "wide 中文字".as_bytes(),
    "combining e\u{301}\u{302}".as_bytes(),
    "emoji 👍🏽 ok".as_bytes(),
    b"\x1b]8;;https://x.example\x1b\\link\x1b]8;;\x1b\\",
    b"0123456789abcdefghijklmnopqrstuvwxyz",
    b"\ttabbed",
    b"x",
];

pub fn edits_styled(steps: usize) -> Vec<u8> {
    let mut rng = Rng::new(0x0bad_cafe_f00d_d00d);
    let mut out = Vec::new();
    for _ in 0..steps {
        match rng.below(3) {
            0 => out.extend_from_slice(rng.pick(&STYLES)),
            1 => out.extend_from_slice(rng.pick(&TEXT)),
            _ => out.extend_from_slice(rng.pick(&EDITS)),
        }
    }
    out
}

pub fn all() -> Vec<Synthetic> {
    let single = |cols, rows| {
        vec![Size {
            offset: 0,
            cols,
            rows,
        }]
    };
    let ascii = ascii_heavy(256 * 1024);
    let ascii_len = ascii.len();
    vec![
        Synthetic {
            name: "synthetic-ascii-heavy",
            bytes: ascii,
            sizes: vec![
                Size {
                    offset: 0,
                    cols: 80,
                    rows: 24,
                },
                Size {
                    offset: ascii_len / 2,
                    cols: 61,
                    rows: 30,
                },
            ],
        },
        Synthetic {
            name: "synthetic-unicode-mix",
            bytes: unicode_mix(64 * 1024),
            sizes: single(20, 10),
        },
        Synthetic {
            name: "synthetic-malformed",
            bytes: malformed(),
            sizes: single(40, 12),
        },
        Synthetic {
            name: "synthetic-edits-styled",
            bytes: edits_styled(20_000),
            sizes: single(40, 12),
        },
    ]
}
