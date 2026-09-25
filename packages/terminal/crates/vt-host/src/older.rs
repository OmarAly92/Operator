use crate::{CORES, RENDER_ERR, RENDER_TOO_BIG};

#[no_mangle]
pub extern "C" fn vt_set_cold_ring(handle: u32, bytes: u32) {
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.set_cold_ring_bytes(bytes as usize);
        }
    });
}

#[no_mangle]
pub extern "C" fn vt_cold_stats(handle: u32, out_ptr: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) => {
            let stats = core.cold_stats();
            let mut out = [0u8; 20];
            out[0..4].copy_from_slice(&(stats.rows as u32).to_le_bytes());
            out[4..8].copy_from_slice(&(stats.bytes as u32).to_le_bytes());
            out[8..12].copy_from_slice(&(stats.cap as u32).to_le_bytes());
            out[12..20].copy_from_slice(&stats.first_stable_row.to_le_bytes());
            unsafe {
                std::ptr::copy_nonoverlapping(out.as_ptr(), out_ptr as *mut u8, out.len());
            }
            1
        }
        None => 0,
    })
}

#[no_mangle]
pub extern "C" fn vt_older_chunk(
    handle: u32,
    before: u64,
    max_rows: u32,
    out_ptr: u32,
    out_cap: u32,
    next_ptr: u32,
) -> u32 {
    CORES.with(|c| {
        let cores = c.borrow();
        let Some(core) = cores.get(&handle) else {
            return RENDER_ERR;
        };
        let Some(chunk) = core.older_chunk(before, max_rows as usize, out_cap as usize) else {
            return 0;
        };
        if chunk.bytes.len() > out_cap as usize {
            return RENDER_TOO_BIG;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(
                chunk.bytes.as_ptr(),
                out_ptr as *mut u8,
                chunk.bytes.len(),
            );
            std::ptr::copy_nonoverlapping(
                chunk.first_stable_row.to_le_bytes().as_ptr(),
                next_ptr as *mut u8,
                8,
            );
        }
        chunk.bytes.len() as u32
    })
}

#[no_mangle]
pub extern "C" fn vt_older_mark(handle: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| {
        let cores = c.borrow();
        let Some(core) = cores.get(&handle) else {
            return RENDER_ERR;
        };
        let Some(mark) = core.older_mark() else {
            return 0;
        };
        if mark.len() > out_cap as usize {
            return RENDER_TOO_BIG;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(mark.as_ptr(), out_ptr as *mut u8, mark.len());
        }
        mark.len() as u32
    })
}
