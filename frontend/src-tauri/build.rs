fn main() {
    let manifest = tauri_build::AppManifest::new().commands(&[
        "daemon_status",
        "daemon_start",
        "daemon_stop",
        "daemon_restart",
        "complete_state_audit",
        "fail_state_audit",
        "terminal_benchmark_runtime_identity",
        "window_set_overlay",
        "window_is_fullscreen",
        "theme_set",
        "menu_action",
        "shell_focus",
        "keybindings_apply",
        "keybindings_recording",
        "set_close_shell_terminal_shortcut_enabled",
    ]);
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(manifest)).unwrap();
}
