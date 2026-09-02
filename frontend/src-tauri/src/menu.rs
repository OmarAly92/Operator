use std::sync::atomic::{AtomicI32, Ordering};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MenuPlatform {
    Macos,
    Windows,
    Linux,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MenuItemKind {
    Action,
    Separator,
    NativeAbout,
    NativeQuit,
    NativePaste,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MenuTemplateItem {
    pub kind: MenuItemKind,
    pub action: Option<&'static str>,
    pub label: &'static str,
    pub accelerator: &'static str,
}

impl MenuTemplateItem {
    fn action(action: &'static str, label: &'static str, accelerator: &'static str) -> Self {
        Self {
            kind: MenuItemKind::Action,
            action: Some(action),
            label,
            accelerator,
        }
    }

    fn separator() -> Self {
        Self {
            kind: MenuItemKind::Separator,
            action: None,
            label: "",
            accelerator: "",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MenuTemplateSubmenu {
    pub label: &'static str,
    pub items: Vec<MenuTemplateItem>,
}

fn edit_submenu(is_mac: bool) -> MenuTemplateSubmenu {
    let redo_accelerator = if is_mac { "Shift+Cmd+Z" } else { "Ctrl+Y" };
    MenuTemplateSubmenu {
        label: "Edit",
        items: vec![
            MenuTemplateItem::action("edit.undo", "Undo", "CmdOrCtrl+Z"),
            MenuTemplateItem::action("edit.redo", "Redo", redo_accelerator),
            MenuTemplateItem::separator(),
            MenuTemplateItem::action("edit.cut", "Cut", "CmdOrCtrl+X"),
            MenuTemplateItem::action("edit.copy", "Copy", "CmdOrCtrl+C"),
            // The platform's own paste, not a scripted one: a webview refuses
            // `document.execCommand('paste')` from page content, so a custom
            // Cmd+V item would swallow the keystroke and paste nothing.
            MenuTemplateItem {
                kind: MenuItemKind::NativePaste,
                action: None,
                label: "Paste",
                accelerator: "",
            },
            MenuTemplateItem::action("edit.selectAll", "Select All", "CmdOrCtrl+A"),
        ],
    }
}

fn view_submenu(is_mac: bool) -> MenuTemplateSubmenu {
    let (devtools, fullscreen) = if is_mac {
        ("Alt+Cmd+I", "Ctrl+Cmd+F")
    } else {
        ("Ctrl+Shift+I", "F11")
    };
    MenuTemplateSubmenu {
        label: "View",
        items: vec![
            MenuTemplateItem::action("view.reload", "Reload", "CmdOrCtrl+R"),
            MenuTemplateItem::action("view.devtools", "Toggle DevTools", devtools),
            MenuTemplateItem::separator(),
            MenuTemplateItem::action("view.zoomReset", "Reset Zoom", "CmdOrCtrl+0"),
            MenuTemplateItem::action("view.zoomIn", "Zoom In", "CmdOrCtrl+="),
            MenuTemplateItem::action("view.zoomOut", "Zoom Out", "CmdOrCtrl+-"),
            MenuTemplateItem::separator(),
            MenuTemplateItem::action("view.fullscreen", "Toggle Full Screen", fullscreen),
        ],
    }
}

fn window_submenu() -> MenuTemplateSubmenu {
    MenuTemplateSubmenu {
        label: "Window",
        items: vec![
            MenuTemplateItem::action("window.minimize", "Minimize", "CmdOrCtrl+M"),
            MenuTemplateItem::action("window.close", "Close", "CmdOrCtrl+W"),
        ],
    }
}

pub fn app_menu_template(platform: MenuPlatform) -> Vec<MenuTemplateSubmenu> {
    let is_mac = platform == MenuPlatform::Macos;
    let mut submenus = Vec::with_capacity(4);
    if is_mac {
        submenus.push(MenuTemplateSubmenu {
            label: "Operator",
            items: vec![
                MenuTemplateItem {
                    kind: MenuItemKind::NativeAbout,
                    action: None,
                    label: "",
                    accelerator: "",
                },
                MenuTemplateItem::separator(),
                MenuTemplateItem {
                    kind: MenuItemKind::NativeQuit,
                    action: None,
                    label: "",
                    accelerator: "",
                },
            ],
        });
    }
    submenus.push(edit_submenu(is_mac));
    submenus.push(view_submenu(is_mac));
    submenus.push(window_submenu());
    submenus
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EditCommand {
    Undo,
    Redo,
    Cut,
    Copy,
    SelectAll,
}

impl EditCommand {
    pub fn exec_script(self) -> &'static str {
        match self {
            EditCommand::Undo => "document.execCommand('undo')",
            EditCommand::Redo => "document.execCommand('redo')",
            EditCommand::Cut => "document.execCommand('cut')",
            EditCommand::Copy => "document.execCommand('copy')",
            EditCommand::SelectAll => "document.execCommand('selectAll')",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MenuAction {
    Edit(EditCommand),
    Reload,
    DevTools,
    ZoomIn,
    ZoomOut,
    ZoomReset,
    ToggleFullscreen,
    Minimize,
    ToggleMaximize,
    Close,
    Quit,
    ShortcutsHelp,
    About,
}

pub fn resolve_menu_action(action: &str) -> Option<MenuAction> {
    Some(match action {
        "edit.undo" => MenuAction::Edit(EditCommand::Undo),
        "edit.redo" => MenuAction::Edit(EditCommand::Redo),
        "edit.cut" => MenuAction::Edit(EditCommand::Cut),
        "edit.copy" => MenuAction::Edit(EditCommand::Copy),
        "edit.selectAll" => MenuAction::Edit(EditCommand::SelectAll),
        "view.reload" => MenuAction::Reload,
        "view.devtools" => MenuAction::DevTools,
        "view.zoomIn" => MenuAction::ZoomIn,
        "view.zoomOut" => MenuAction::ZoomOut,
        "view.zoomReset" => MenuAction::ZoomReset,
        "view.fullscreen" => MenuAction::ToggleFullscreen,
        "window.minimize" => MenuAction::Minimize,
        "window.maximize" => MenuAction::ToggleMaximize,
        "window.close" => MenuAction::Close,
        "app.quit" => MenuAction::Quit,
        "help.shortcuts" => MenuAction::ShortcutsHelp,
        "help.about" => MenuAction::About,
        _ => return None,
    })
}

pub struct ZoomState {
    tenths: AtomicI32,
}

impl Default for ZoomState {
    fn default() -> Self {
        Self {
            tenths: AtomicI32::new(0),
        }
    }
}

fn chromium_zoom_scale(level_tenths: i32) -> f64 {
    1.2f64.powf(f64::from(level_tenths) / 10.0)
}

impl ZoomState {
    pub fn scale_after_step(&self, step: Option<f64>) -> f64 {
        let delta_tenths = match step {
            None => -self.tenths.load(Ordering::SeqCst),
            Some(step) => (step * 10.0).round() as i32,
        };
        let next = self.tenths.fetch_add(delta_tenths, Ordering::SeqCst) + delta_tenths;
        chromium_zoom_scale(next)
    }
}

pub trait MenuHost {
    fn edit(&mut self, command: EditCommand);
    fn reload(&mut self);
    fn toggle_devtools(&mut self);
    fn zoom(&mut self, scale: f64);
    fn toggle_fullscreen(&mut self);
    fn minimize(&mut self);
    fn toggle_maximize(&mut self);
    fn close(&mut self);
    fn quit(&mut self);
    fn show_shortcuts_help(&mut self);
    fn about(&mut self);
}

pub fn dispatch_menu_action<H: MenuHost>(action: &str, zoom: &ZoomState, host: &mut H) -> bool {
    let Some(resolved) = resolve_menu_action(action) else {
        return false;
    };
    match resolved {
        MenuAction::Edit(command) => host.edit(command),
        MenuAction::Reload => host.reload(),
        MenuAction::DevTools => host.toggle_devtools(),
        MenuAction::ZoomIn => {
            let scale = zoom.scale_after_step(Some(0.5));
            host.zoom(scale);
        }
        MenuAction::ZoomOut => {
            let scale = zoom.scale_after_step(Some(-0.5));
            host.zoom(scale);
        }
        MenuAction::ZoomReset => {
            let scale = zoom.scale_after_step(None);
            host.zoom(scale);
        }
        MenuAction::ToggleFullscreen => host.toggle_fullscreen(),
        MenuAction::Minimize => host.minimize(),
        MenuAction::ToggleMaximize => host.toggle_maximize(),
        MenuAction::Close => host.close(),
        MenuAction::Quit => host.quit(),
        MenuAction::ShortcutsHelp => host.show_shortcuts_help(),
        MenuAction::About => host.about(),
    }
    true
}

#[cfg(test)]
mod tests {
    use super::EditCommand;

    #[test]
    fn edit_scripts_target_the_focused_webview_document() {
        assert_eq!(
            EditCommand::SelectAll.exec_script(),
            "document.execCommand('selectAll')"
        );
    }
}
