use crate::program::write_out;
use crate::{CORES, RENDER_ERR};

#[no_mangle]
pub extern "C" fn vt_live_output_bytes(handle: u32) -> u64 {
    CORES.with(|c| {
        c.borrow()
            .get(&handle)
            .map_or(0, |core| core.live_output_bytes())
    })
}

#[no_mangle]
pub extern "C" fn vt_agent_activity(handle: u32, quiet_ms: u64) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) => core
            .agent_activity((quiet_ms != u64::MAX).then_some(quiet_ms))
            .wire(),
        None => RENDER_ERR,
    })
}

#[no_mangle]
pub extern "C" fn vt_cursor_line(handle: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) => write_out(core.cursor_line_text().as_bytes(), out_ptr, out_cap),
        None => RENDER_ERR,
    })
}
