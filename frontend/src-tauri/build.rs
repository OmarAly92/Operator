fn main() {
    let manifest = tauri_build::AppManifest::new().commands(&[
        "daemon_status",
        "daemon_start",
        "daemon_stop",
        "daemon_restart",
        "complete_state_audit",
        "fail_state_audit",
        "terminal_benchmark_runtime_identity",
    ]);
    tauri_build::try_build(tauri_build::Attributes::new().app_manifest(manifest)).unwrap();
}
