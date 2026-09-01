use std::cell::RefCell;
use std::collections::HashMap;
use vt_core::TerminalCore;

thread_local! {
    static CORES: RefCell<HashMap<u32, TerminalCore>> = RefCell::new(HashMap::new());
    static NEXT_ID: RefCell<u32> = const { RefCell::new(1) };
}

#[no_mangle]
pub extern "C" fn vt_alloc(len: u32) -> u32 {
    let mut buf = Vec::<u8>::with_capacity(len as usize);
    let ptr = buf.as_mut_ptr() as u32;
    std::mem::forget(buf);
    ptr
}

#[no_mangle]
pub extern "C" fn vt_free(ptr: u32, len: u32) {
    unsafe { drop(Vec::from_raw_parts(ptr as *mut u8, 0, len as usize)) };
}

#[no_mangle]
pub extern "C" fn vt_new(cols: u32, rows: u32, scrollback: u32) -> u32 {
    let Ok(mut core) = TerminalCore::new(cols as usize, scrollback as usize) else {
        return 0;
    };
    core.resize(cols as usize, rows as usize);
    NEXT_ID.with(|n| {
        let mut n = n.borrow_mut();
        let id = *n;
        *n += 1;
        CORES.with(|c| c.borrow_mut().insert(id, core));
        id
    })
}

#[no_mangle]
pub extern "C" fn vt_resize(handle: u32, cols: u32, rows: u32) {
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.resize(cols as usize, rows as usize);
        }
    });
}

#[no_mangle]
pub extern "C" fn vt_feed(handle: u32, ptr: u32, len: u32) {
    let bytes = unsafe { std::slice::from_raw_parts(ptr as *const u8, len as usize) };
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.feed(bytes);
        }
    });
}

#[no_mangle]
pub extern "C" fn vt_alt_active(handle: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) if core.alt_screen_active() => 1,
        _ => 0,
    })
}

pub const RENDER_ERR: u32 = u32::MAX;
pub const RENDER_TOO_BIG: u32 = u32::MAX - 1;

// Writes the last `lines` rendered rows as UTF-8 into out_ptr, returning the
// byte count written. 0 means a genuinely empty screen; RENDER_ERR means a bad
// handle or snapshot failure; RENDER_TOO_BIG means out_cap is too small. The
// three must stay distinct: the caller treats only RENDER_* as failures, never
// an empty screen. When the alternate screen is active the alt grid is rendered
// instead, matching what `tmux capture-pane` returns for a full-screen app.
#[no_mangle]
pub extern "C" fn vt_render(handle: u32, lines: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| {
        let cores = c.borrow();
        let Some(core) = cores.get(&handle) else { return RENDER_ERR };
        let Ok(snapshot) = core.snapshot() else { return RENDER_ERR };

        let mut text = String::new();
        if let Some(alt) = &snapshot.alt {
            for (start, end) in &alt.row_ranges {
                text.push_str(
                    std::str::from_utf8(&alt.content[*start as usize..*end as usize]).unwrap_or(""),
                );
                text.push('\n');
            }
        } else {
            let total = snapshot.row_count();
            let first = total.saturating_sub(lines as usize);
            for i in first..total {
                text.push_str(snapshot.row_text(i));
                text.push('\n');
            }
        }

        let bytes = text.as_bytes();
        if bytes.len() > out_cap as usize {
            return RENDER_TOO_BIG;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_ptr as *mut u8, bytes.len());
        }
        bytes.len() as u32
    })
}
