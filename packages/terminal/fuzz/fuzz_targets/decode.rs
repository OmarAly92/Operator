#![no_main]

use libfuzzer_sys::fuzz_target;
use terminal_marks::MarkDecoder;

fuzz_target!(|data: &[u8]| {
    let mut decoder = MarkDecoder::new();
    for chunk in data.chunks(7) {
        let _ = decoder.feed(chunk);
    }
});
