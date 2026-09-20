use vt_core::TerminalCore;

pub fn check(core: &TerminalCore) {
    if let Err(error) = core.verify_integrity() {
        panic!("integrity violated: {error:?}");
    }
    core.snapshot().expect("snapshot builds");
}
