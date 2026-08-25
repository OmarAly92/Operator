use std::collections::HashMap;

use crate::menu::{dispatch_menu_action, resolve_menu_action, EditCommand, MenuAction, ZoomState};
use crate::shortcuts::{
    accelerator_for_binding, default_bindings, event_name_for_wire_id, ApplyReport, Binding,
    ShortcutEngine, ShortcutId, ShortcutRegistrar,
};
use crate::window::{fullscreen_transitions, overlay_colors, theme_preference};

const HOST_MAC: bool = cfg!(target_os = "macos");
const ALL_EVENT_NAMES: [&str; 10] = [
    "shortcut:new-session",
    "shortcut:new-shell-terminal",
    "shortcut:close-shell-terminal",
    "shortcut:help",
    "shortcut:open-settings",
    "shortcut:previous-session",
    "shortcut:next-session",
    "shortcut:previous-tab",
    "shortcut:next-tab",
    "shortcut:focus-terminal",
];

#[derive(Default)]
struct FakeRegistrar {
    fail_on: Vec<String>,
}

impl FakeRegistrar {
    fn failing_on(accelerators: &[&str]) -> Self {
        Self {
            fail_on: accelerators.iter().map(|name| name.to_string()).collect(),
        }
    }
}

impl ShortcutRegistrar for FakeRegistrar {
    fn register(&mut self, accelerator: &str, _event_name: &str) -> Result<(), String> {
        if self.fail_on.iter().any(|failed| failed == accelerator) {
            return Err(format!("os refused {accelerator}"));
        }
        Ok(())
    }

    fn unregister_all(&mut self) {}
}

fn engine_with(registrar: FakeRegistrar) -> ShortcutEngine<FakeRegistrar> {
    ShortcutEngine::new(registrar, HOST_MAC)
}

fn armed_engine() -> ShortcutEngine<FakeRegistrar> {
    let mut engine = engine_with(FakeRegistrar::default());
    engine.set_window_focused(true);
    engine
}

fn default_accelerator(id: ShortcutId) -> String {
    accelerator_for_binding(&default_bindings(id, HOST_MAC)[0], HOST_MAC)
}

type BindingSpec = (&'static str, bool, bool, bool, bool);

fn overrides_from(entries: &[(&str, &[BindingSpec])]) -> HashMap<String, Vec<Binding>> {
    entries
        .iter()
        .map(|(id, bindings)| {
            (
                id.to_string(),
                bindings
                    .iter()
                    .map(|(key, ctrl, meta, shift, alt)| Binding {
                        key: key.to_string(),
                        code: None,
                        ctrl: *ctrl,
                        meta: *meta,
                        shift: *shift,
                        alt: *alt,
                    })
                    .collect(),
            )
        })
        .collect()
}

#[test]
fn default_accelerators_match_the_electron_platform_split() {
    let mac = ShortcutId::PRIORITY_ORDER.map(|id| {
        (
            id,
            accelerator_for_binding(&default_bindings(id, true)[0], true),
        )
    });
    let other = ShortcutId::PRIORITY_ORDER.map(|id| {
        (
            id,
            accelerator_for_binding(&default_bindings(id, false)[0], false),
        )
    });

    let expected_mac = HashMap::from([
        (ShortcutId::NewSession, "SUPER+N"),
        (ShortcutId::NewShellTerminal, "SUPER+T"),
        (ShortcutId::CloseShellTerminal, "SUPER+W"),
        (ShortcutId::KeyboardShortcuts, "SUPER+SLASH"),
        (ShortcutId::OpenSettings, "SUPER+COMMA"),
        (ShortcutId::PreviousSession, "SUPER+ALT+ARROWUP"),
        (ShortcutId::NextSession, "SUPER+ALT+ARROWDOWN"),
        (ShortcutId::PreviousTab, "CONTROL+SHIFT+TAB"),
        (ShortcutId::NextTab, "CONTROL+TAB"),
        (ShortcutId::FocusTerminal, "SUPER+SHIFT+T"),
    ]);
    let expected_other = HashMap::from([
        (ShortcutId::NewSession, "CONTROL+SHIFT+N"),
        (ShortcutId::NewShellTerminal, "CONTROL+T"),
        (ShortcutId::CloseShellTerminal, "CONTROL+W"),
        (ShortcutId::KeyboardShortcuts, "CONTROL+SLASH"),
        (ShortcutId::OpenSettings, "CONTROL+COMMA"),
        (ShortcutId::PreviousSession, "CONTROL+PAGEUP"),
        (ShortcutId::NextSession, "CONTROL+PAGEDOWN"),
        (ShortcutId::PreviousTab, "CONTROL+SHIFT+TAB"),
        (ShortcutId::NextTab, "CONTROL+TAB"),
        (ShortcutId::FocusTerminal, "CONTROL+SHIFT+T"),
    ]);

    for (id, accelerator) in mac {
        assert_eq!(expected_mac[&id], accelerator, "mac mapping for {id:?}");
    }
    for (id, accelerator) in other {
        assert_eq!(
            expected_other[&id], accelerator,
            "non-mac mapping for {id:?}"
        );
    }
}

#[test]
fn every_default_accelerator_parses_with_the_pinned_plugin_parser() {
    for is_mac in [true, false] {
        for id in ShortcutId::PRIORITY_ORDER {
            let accelerator = accelerator_for_binding(&default_bindings(id, is_mac)[0], is_mac);
            let parsed: Result<tauri_plugin_global_shortcut::Shortcut, _> = accelerator.parse();
            assert!(
                parsed.is_ok(),
                "{accelerator} must parse for {id:?} (mac={is_mac})"
            );
        }
    }
}

#[test]
fn physical_code_overrides_shifted_character_keys() {
    let binding = Binding {
        key: "~".to_string(),
        code: Some("Backquote".to_string()),
        ctrl: false,
        meta: true,
        shift: false,
        alt: false,
    };
    assert_eq!(accelerator_for_binding(&binding, true), "SUPER+BACKQUOTE");
}

#[test]
fn every_ledger_shortcut_event_name_is_emitted() {
    let engine = armed_engine();

    for id in ShortcutId::PRIORITY_ORDER {
        assert!(
            ALL_EVENT_NAMES.contains(&id.event_name()),
            "{} missing from the ledger event list",
            id.event_name()
        );
    }

    for (id, event) in ShortcutId::PRIORITY_ORDER.iter().zip(ALL_EVENT_NAMES) {
        if *id == ShortcutId::CloseShellTerminal {
            continue;
        }
        assert_eq!(
            engine.event_for(default_accelerator(*id).as_str()),
            Some(event)
        );
    }
    assert_eq!(
        engine.event_for("CONTROL+SHIFT+TAB"),
        Some("shortcut:previous-tab")
    );
}

#[test]
fn close_shell_terminal_stays_unregistered_until_enabled() {
    let close_accelerator = default_accelerator(ShortcutId::CloseShellTerminal);
    let mut engine = armed_engine();
    assert!(engine.event_for(close_accelerator.as_str()).is_none());

    engine.set_close_terminal_enabled(true);
    assert_eq!(
        engine.event_for(close_accelerator.as_str()),
        Some("shortcut:close-shell-terminal")
    );

    engine.set_close_terminal_enabled(false);
    assert!(engine.event_for(close_accelerator.as_str()).is_none());
}

#[test]
fn settings_changes_reregister_only_what_changed() {
    let new_session_accelerator = default_accelerator(ShortcutId::NewSession);
    let focus_terminal_accelerator = default_accelerator(ShortcutId::FocusTerminal);
    let mut engine = armed_engine();

    engine.set_overrides(overrides_from(&[
        ("new-session", &[("j", false, true, false, false)]),
        ("focus-terminal", &[]),
    ]));

    assert_eq!(engine.event_for("SUPER+J"), Some("shortcut:new-session"));
    assert!(engine.event_for(new_session_accelerator.as_str()).is_none());
    assert!(engine
        .event_for(focus_terminal_accelerator.as_str())
        .is_none());
}

#[test]
fn empty_override_unassigns_the_chord_and_frees_the_key() {
    let new_shell_terminal_accelerator = default_accelerator(ShortcutId::NewShellTerminal);
    let mut engine = armed_engine();
    assert_eq!(
        engine.event_for(new_shell_terminal_accelerator.as_str()),
        Some("shortcut:new-shell-terminal")
    );

    engine.set_overrides(overrides_from(&[("new-shell-terminal", &[])]));
    assert!(engine
        .event_for(new_shell_terminal_accelerator.as_str())
        .is_none());

    let report = engine.set_overrides(overrides_from(&[
        ("new-shell-terminal", &[]),
        ("focus-terminal", &[("t", false, true, false, false)]),
    ]));

    assert!(report.conflicts.is_empty());
    assert_eq!(
        engine.event_for(new_shell_terminal_accelerator.as_str()),
        Some("shortcut:focus-terminal")
    );
}

#[test]
fn conflicting_bindings_keep_priority_order_and_report_the_shadowed_id() {
    let mut engine = engine_with(FakeRegistrar::default());
    engine.set_window_focused(true);

    let report = engine.set_overrides(overrides_from(&[
        (
            "new-session",
            &[
                ("k", false, true, false, false),
                ("j", false, true, false, false),
            ],
        ),
        ("new-shell-terminal", &[("k", false, true, false, false)]),
        ("keyboard-shortcuts", &[("k", false, true, false, false)]),
    ]));

    assert_eq!(report.conflicts.len(), 2);
    assert!(report
        .conflicts
        .iter()
        .all(|conflict| conflict.winner == ShortcutId::NewSession));
    assert!(report
        .conflicts
        .iter()
        .any(|conflict| conflict.shadowed == ShortcutId::NewShellTerminal));
    assert!(report
        .conflicts
        .iter()
        .any(|conflict| conflict.shadowed == ShortcutId::KeyboardShortcuts));
    assert_eq!(report.conflicts[0].accelerator, "SUPER+K");
    assert!(engine.event_for("SUPER+K").is_some());
    assert_eq!(engine.event_for("SUPER+J"), Some("shortcut:new-session"));
}

#[test]
fn registration_failures_are_reported_without_dropping_other_shortcuts() {
    let new_session_accelerator = default_accelerator(ShortcutId::NewSession);
    let mut engine = engine_with(FakeRegistrar::failing_on(&[
        new_session_accelerator.as_str()
    ]));
    engine.set_window_focused(true);

    let report = engine.apply();
    let ApplyReport {
        conflicts,
        failures,
    } = report;

    assert!(conflicts.is_empty());
    assert_eq!(failures.len(), 1);
    assert_eq!(failures[0].id, ShortcutId::NewSession);
    assert_eq!(failures[0].accelerator, new_session_accelerator);
    assert_eq!(
        failures[0].error,
        format!("os refused {}", default_accelerator(ShortcutId::NewSession))
    );
}

#[test]
fn recording_suppresses_every_shortcut_until_recording_ends() {
    let mut engine = armed_engine();
    assert!(!engine.registered().is_empty());

    engine.set_recording(true);
    assert!(engine.registered().is_empty());
    assert!(!engine.armed());

    engine.set_overrides(overrides_from(&[(
        "new-session",
        &[("p", false, true, false, false)],
    )]));
    assert!(engine.registered().is_empty());

    engine.set_recording(false);
    assert_eq!(engine.event_for("SUPER+P"), Some("shortcut:new-session"));
}

#[test]
fn losing_focus_disarms_and_regaining_focus_rearms() {
    let mut engine = armed_engine();
    assert!(!engine.registered().is_empty());

    engine.set_window_focused(false);
    assert!(engine.registered().is_empty());

    engine.set_window_focused(true);
    assert!(engine
        .registered()
        .iter()
        .any(|(accelerator, _)| accelerator == "CONTROL+SHIFT+TAB"));
}

#[test]
fn fullscreen_tracker_reports_each_transition_once() {
    let transitions = fullscreen_transitions([false, true, true, false, false]);
    assert_eq!(transitions, vec![true, false]);
}

#[test]
fn overlay_colors_require_hex_input() {
    let colors = overlay_colors("#17181c", "#c7ccd4").expect("#rrggbb colors parse");
    assert_eq!(colors.color, (0x17, 0x18, 0x1c));
    assert_eq!(colors.symbol_color, (0xc7, 0xcc, 0xd4));
    assert_eq!(
        overlay_colors("#17181cff", "#c7ccd4").map(|colors| colors.color),
        Some((0x17, 0x18, 0x1c))
    );
    assert!(overlay_colors("rgb(23, 24, 28)", "#c7ccd4").is_none());
    assert!(overlay_colors("", "#c7ccd4").is_none());
    assert!(overlay_colors("#17181c", "#cc").is_none());
}

#[test]
fn theme_preferences_accept_only_electron_values() {
    assert_eq!(
        theme_preference("light"),
        Some(crate::window::ThemePreference::Light)
    );
    assert_eq!(
        theme_preference("dark"),
        Some(crate::window::ThemePreference::Dark)
    );
    assert_eq!(
        theme_preference("system"),
        Some(crate::window::ThemePreference::System)
    );
    assert_eq!(theme_preference("purple"), None);
    assert_eq!(theme_preference(""), None);
}

#[test]
fn every_window_titlebar_menu_action_resolves() {
    let actions = [
        ("edit.undo", Some(MenuAction::Edit(EditCommand::Undo))),
        ("edit.redo", Some(MenuAction::Edit(EditCommand::Redo))),
        ("edit.cut", Some(MenuAction::Edit(EditCommand::Cut))),
        ("edit.copy", Some(MenuAction::Edit(EditCommand::Copy))),
        ("edit.paste", Some(MenuAction::Edit(EditCommand::Paste))),
        (
            "edit.selectAll",
            Some(MenuAction::Edit(EditCommand::SelectAll)),
        ),
        ("view.reload", Some(MenuAction::Reload)),
        ("view.devtools", Some(MenuAction::DevTools)),
        ("view.zoomIn", Some(MenuAction::ZoomIn)),
        ("view.zoomOut", Some(MenuAction::ZoomOut)),
        ("view.zoomReset", Some(MenuAction::ZoomReset)),
        ("view.fullscreen", Some(MenuAction::ToggleFullscreen)),
        ("window.minimize", Some(MenuAction::Minimize)),
        ("window.maximize", Some(MenuAction::ToggleMaximize)),
        ("window.close", Some(MenuAction::Close)),
        ("app.quit", Some(MenuAction::Quit)),
        ("help.shortcuts", Some(MenuAction::ShortcutsHelp)),
        ("help.about", Some(MenuAction::About)),
    ];
    for (action, expected) in actions {
        assert_eq!(resolve_menu_action(action), expected, "action {action}");
    }
    assert_eq!(resolve_menu_action("edit.paste-all"), None);
    assert_eq!(resolve_menu_action(""), None);
}

#[derive(Default)]
struct FakeMenuHost {
    edits: Vec<EditCommand>,
    reloads: usize,
    devtools_toggles: usize,
    zoom_scales: Vec<f64>,
    fullscreen_toggles: usize,
    minimize_count: usize,
    maximize_toggles: usize,
    closes: usize,
    quits: usize,
    help_events: usize,
    abouts: usize,
}

impl crate::menu::MenuHost for FakeMenuHost {
    fn edit(&mut self, command: EditCommand) {
        self.edits.push(command);
    }

    fn reload(&mut self) {
        self.reloads += 1;
    }

    fn toggle_devtools(&mut self) {
        self.devtools_toggles += 1;
    }

    fn zoom(&mut self, scale: f64) {
        self.zoom_scales.push(scale);
    }

    fn toggle_fullscreen(&mut self) {
        self.fullscreen_toggles += 1;
    }

    fn minimize(&mut self) {
        self.minimize_count += 1;
    }

    fn toggle_maximize(&mut self) {
        self.maximize_toggles += 1;
    }

    fn close(&mut self) {
        self.closes += 1;
    }

    fn quit(&mut self) {
        self.quits += 1;
    }

    fn show_shortcuts_help(&mut self) {
        self.help_events += 1;
    }

    fn about(&mut self) {
        self.abouts += 1;
    }
}

#[test]
fn menu_dispatch_routes_every_action_to_its_host_call() {
    let zoom = ZoomState::default();
    let mut host = FakeMenuHost::default();

    assert!(dispatch_menu_action("edit.undo", &zoom, &mut host));
    assert!(dispatch_menu_action("edit.paste", &zoom, &mut host));
    assert!(dispatch_menu_action("view.reload", &zoom, &mut host));
    assert!(dispatch_menu_action("view.devtools", &zoom, &mut host));
    assert!(dispatch_menu_action("view.zoomIn", &zoom, &mut host));
    assert!(dispatch_menu_action("view.zoomIn", &zoom, &mut host));
    assert!(dispatch_menu_action("view.zoomOut", &zoom, &mut host));
    assert!(dispatch_menu_action("view.zoomReset", &zoom, &mut host));
    assert!(dispatch_menu_action("view.fullscreen", &zoom, &mut host));
    assert!(dispatch_menu_action("window.minimize", &zoom, &mut host));
    assert!(dispatch_menu_action("window.maximize", &zoom, &mut host));
    assert!(dispatch_menu_action("window.close", &zoom, &mut host));
    assert!(dispatch_menu_action("app.quit", &zoom, &mut host));
    assert!(dispatch_menu_action("help.shortcuts", &zoom, &mut host));
    assert!(dispatch_menu_action("help.about", &zoom, &mut host));
    assert!(!dispatch_menu_action("edit.unknown", &zoom, &mut host));

    assert_eq!(host.edits, vec![EditCommand::Undo, EditCommand::Paste]);
    assert_eq!(host.reloads, 1);
    assert_eq!(host.devtools_toggles, 1);
    let half_step = 1.2f64.powf(0.5);
    assert_eq!(host.zoom_scales, vec![half_step, 1.2, half_step, 1.0]);
    assert_eq!(host.fullscreen_toggles, 1);
    assert_eq!(host.minimize_count, 1);
    assert_eq!(host.maximize_toggles, 1);
    assert_eq!(host.closes, 1);
    assert_eq!(host.quits, 1);
    assert_eq!(host.help_events, 1);
    assert_eq!(host.abouts, 1);
}

#[test]
fn help_shortcuts_dispatch_matches_the_keyboard_shortcuts_event_channel() {
    assert_eq!(
        event_name_for_wire_id("keyboard-shortcuts"),
        Some("shortcut:help")
    );
}

#[test]
fn windows_and_linux_install_the_same_hidden_role_menu_template() {
    let expected_windows = crate::menu::app_menu_template(crate::menu::MenuPlatform::Windows);
    let expected_linux = crate::menu::app_menu_template(crate::menu::MenuPlatform::Linux);
    assert_eq!(expected_windows, expected_linux);

    assert_eq!(expected_windows.len(), 3);
    let edit = &expected_windows[0];
    assert_eq!(edit.label, "Edit");
    let edit_actions: Vec<&str> = edit.items.iter().filter_map(|item| item.action).collect();
    assert_eq!(
        edit_actions,
        [
            "edit.undo",
            "edit.redo",
            "edit.cut",
            "edit.copy",
            "edit.paste",
            "edit.selectAll"
        ]
    );
    assert_eq!(edit.items[2].kind, crate::menu::MenuItemKind::Separator);

    let view = &expected_windows[1];
    assert_eq!(view.label, "View");
    let view_entries: Vec<(&str, &str)> = view
        .items
        .iter()
        .filter_map(|item| item.action.map(|action| (action, item.accelerator)))
        .collect();
    assert_eq!(
        view_entries,
        [
            ("view.reload", "CmdOrCtrl+R"),
            ("view.devtools", "Ctrl+Shift+I"),
            ("view.zoomReset", "CmdOrCtrl+0"),
            ("view.zoomIn", "CmdOrCtrl+="),
            ("view.zoomOut", "CmdOrCtrl+-"),
            ("view.fullscreen", "F11"),
        ]
    );

    let window_menu = &expected_windows[2];
    assert_eq!(window_menu.label, "Window");
    let window_entries: Vec<(&str, &str)> = window_menu
        .items
        .iter()
        .filter_map(|item| item.action.map(|action| (action, item.accelerator)))
        .collect();
    assert_eq!(
        window_entries,
        [
            ("window.minimize", "CmdOrCtrl+M"),
            ("window.close", "CmdOrCtrl+W")
        ]
    );
}

#[test]
fn macos_menu_covers_app_edit_view_window_roles_with_mac_accelerators() {
    let template = crate::menu::app_menu_template(crate::menu::MenuPlatform::Macos);

    assert_eq!(template.len(), 4);
    let app = &template[0];
    assert_eq!(app.label, "Operator");
    assert!(app
        .items
        .iter()
        .any(|item| item.kind == crate::menu::MenuItemKind::NativeAbout));
    assert!(app
        .items
        .iter()
        .any(|item| item.kind == crate::menu::MenuItemKind::NativeQuit));

    let accelerators: HashMap<&str, &str> = template
        .iter()
        .flat_map(|submenu| &submenu.items)
        .filter_map(|item| item.action.map(|action| (action, item.accelerator)))
        .collect();
    assert_eq!(accelerators["edit.undo"], "CmdOrCtrl+Z");
    assert_eq!(accelerators["edit.redo"], "Shift+Cmd+Z");
    assert_eq!(accelerators["edit.selectAll"], "CmdOrCtrl+A");
    assert_eq!(accelerators["view.reload"], "CmdOrCtrl+R");
    assert_eq!(accelerators["view.devtools"], "Alt+Cmd+I");
    assert_eq!(accelerators["view.zoomReset"], "CmdOrCtrl+0");
    assert_eq!(accelerators["view.zoomIn"], "CmdOrCtrl+=");
    assert_eq!(accelerators["view.zoomOut"], "CmdOrCtrl+-");
    assert_eq!(accelerators["view.fullscreen"], "Ctrl+Cmd+F");
    assert_eq!(accelerators["window.minimize"], "CmdOrCtrl+M");
    assert_eq!(accelerators["window.close"], "CmdOrCtrl+W");
}

#[test]
fn every_native_menu_action_routes_through_the_shared_dispatch() {
    let zoom = ZoomState::default();
    for platform in [
        crate::menu::MenuPlatform::Macos,
        crate::menu::MenuPlatform::Windows,
        crate::menu::MenuPlatform::Linux,
    ] {
        for submenu in crate::menu::app_menu_template(platform) {
            for item in submenu.items {
                let Some(action) = item.action else {
                    continue;
                };
                let mut host = FakeMenuHost::default();
                assert!(
                    dispatch_menu_action(action, &zoom, &mut host),
                    "native menu action {action} must dispatch"
                );
            }
        }
    }
}

#[test]
fn system_theme_follows_the_os_scheme_change() {
    use crate::window::{
        resolved_background, ThemePreference, NATIVE_WINDOW_BACKGROUND_DARK,
        NATIVE_WINDOW_BACKGROUND_LIGHT,
    };

    assert_eq!(
        resolved_background(ThemePreference::System, true),
        Some(NATIVE_WINDOW_BACKGROUND_DARK)
    );
    assert_eq!(
        resolved_background(ThemePreference::System, false),
        Some(NATIVE_WINDOW_BACKGROUND_LIGHT)
    );
    assert_eq!(
        resolved_background(ThemePreference::Light, true),
        Some(NATIVE_WINDOW_BACKGROUND_LIGHT)
    );
    assert_eq!(
        resolved_background(ThemePreference::Dark, false),
        Some(NATIVE_WINDOW_BACKGROUND_DARK)
    );
}
