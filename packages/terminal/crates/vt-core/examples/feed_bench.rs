use std::time::Instant;
use vt_core::TerminalCore;

fn main() {
    let mut payload = vec![0u8; 16 << 20];
    for (i, b) in payload.iter_mut().enumerate() {
        *b = b'a' + (i % 26) as u8;
        if i % 80 == 79 {
            *b = b'\n';
        }
    }

    let mut core = TerminalCore::new(120, 1000).unwrap();
    core.resize(120, 40);
    let start = Instant::now();
    for slice in payload.chunks(64 << 10) {
        core.feed(slice);
    }
    let secs = start.elapsed().as_secs_f64();
    println!(
        "native vt-core: {:.2} MB/s ({:.2}s for 16MB)",
        16.0 / secs,
        secs
    );
}
