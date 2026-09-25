use crate::{CORES, RENDER_ERR, RENDER_TOO_BIG};

const KNOWN_COLOR: u32 = 0x0100_0000;

fn write_out(bytes: &[u8], out_ptr: u32, out_cap: u32) -> u32 {
    if bytes.len() > out_cap as usize {
        return RENDER_TOO_BIG;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out_ptr as *mut u8, bytes.len());
    }
    bytes.len() as u32
}

fn color(word: u32) -> Option<u32> {
    (word & KNOWN_COLOR != 0).then_some(word & 0x00ff_ffff)
}

#[no_mangle]
pub extern "C" fn vt_program_generation(handle: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) => core.program_generation() as u32,
        None => 0,
    })
}

#[no_mangle]
pub extern "C" fn vt_title(handle: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| match c.borrow().get(&handle) {
        Some(core) => write_out(core.title().as_bytes(), out_ptr, out_cap),
        None => RENDER_ERR,
    })
}

#[no_mangle]
pub extern "C" fn vt_take_notifications(handle: u32, out_ptr: u32, out_cap: u32) -> u32 {
    CORES.with(|c| {
        let mut cores = c.borrow_mut();
        let Some(core) = cores.get_mut(&handle) else {
            return RENDER_ERR;
        };
        let mut encoded = Vec::new();
        for notification in core.take_notifications() {
            let mut record = Vec::new();
            for part in [notification.title.as_bytes(), notification.body.as_bytes()] {
                record.extend_from_slice(&(part.len() as u32).to_le_bytes());
                record.extend_from_slice(part);
            }
            if encoded.len() + record.len() > out_cap as usize {
                break;
            }
            encoded.extend_from_slice(&record);
        }
        write_out(&encoded, out_ptr, out_cap)
    })
}

#[no_mangle]
pub extern "C" fn vt_set_cell_pixels(handle: u32, width: u32, height: u32) {
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.set_cell_pixels(width, height);
        }
    });
}

#[no_mangle]
pub extern "C" fn vt_set_default_colors(handle: u32, foreground: u32, background: u32) {
    CORES.with(|c| {
        if let Some(core) = c.borrow_mut().get_mut(&handle) {
            core.set_default_colors(color(foreground), color(background));
        }
    });
}
