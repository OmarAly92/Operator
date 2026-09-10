use objc2_app_kit::{NSWindow, NSWindowButton, NSWindowStyleMask};
use objc2_foundation::{NSPoint, NSRect, NSSize};

pub fn align(window: &tauri::WebviewWindow) -> Result<(), tauri::Error> {
    let target = window.clone();
    window.run_on_main_thread(move || {
        let Ok(pointer) = target.ns_window() else { return };
        let native = unsafe { &*pointer.cast::<NSWindow>() };
        if native.styleMask().contains(NSWindowStyleMask::FullScreen) {
            return;
        }
        let Some(close) = native.standardWindowButton(NSWindowButton::CloseButton) else { return };
        let Some(titlebar) = (unsafe { close.superview() }) else { return };
        let Some(container) = (unsafe { titlebar.superview() }) else { return };
        let mut frame = container.frame();
        frame.size.height = 35.0;
        frame.origin.y = native.frame().size.height - 35.0;
        container.setFrame(frame);
        let mut titlebar_frame = titlebar.frame();
        titlebar_frame.origin.y = 0.0;
        titlebar_frame.size.height = 35.0;
        titlebar.setFrame(titlebar_frame);
        for (index, kind) in [NSWindowButton::CloseButton, NSWindowButton::MiniaturizeButton, NSWindowButton::ZoomButton].into_iter().enumerate() {
            if let Some(button) = native.standardWindowButton(kind) {
                button.setFrame(NSRect::new(
                    NSPoint::new(12.0 + index as f64 * 20.0, 9.5),
                    NSSize::new(14.0, 14.0),
                ));
            }
        }
    })
}
