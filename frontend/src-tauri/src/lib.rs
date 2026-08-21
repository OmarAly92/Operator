use std::{env, error::Error, fs, path::Path, path::PathBuf};

#[derive(Clone, Copy, Eq, PartialEq)]
enum StateProfile {
    Development,
    Production,
}

fn resolve_state_root(
    operator_data_dir: Option<&Path>,
    operator_run_file: Option<&Path>,
    home_dir: Option<&Path>,
    profile: StateProfile,
) -> Result<PathBuf, &'static str> {
    if let Some(override_path) = operator_data_dir.or(operator_run_file) {
        if !override_path.is_absolute() {
            return Err("Operator overrides must resolve to an absolute path");
        }
        return override_path
            .parent()
            .filter(|parent| parent.is_absolute())
            .map(|parent| parent.join("tauri"))
            .ok_or("Operator state root could not be resolved");
    }

    let operator_root = home_dir
        .filter(|home| home.is_absolute())
        .map(|home| home.join(".operator"))
        .ok_or("Operator state root could not be resolved")?;
    if profile == StateProfile::Development {
        Ok(operator_root.join("dev").join("tauri"))
    } else {
        Ok(operator_root.join("tauri"))
    }
}

fn absolute_environment_path(name: &str) -> Result<Option<PathBuf>, Box<dyn Error>> {
    match env::var_os(name)
        .filter(|path| !path.is_empty())
        .map(PathBuf::from)
    {
        Some(path) if path.is_absolute() => Ok(Some(path)),
        Some(path) => Ok(Some(env::current_dir()?.join(path))),
        None => Ok(None),
    }
}

fn state_environment(state_root: &Path) -> Vec<(&'static str, PathBuf)> {
    #[cfg(target_os = "macos")]
    {
        vec![
            ("CFFIXED_USER_HOME", state_root.to_path_buf()),
            ("HOME", state_root.to_path_buf()),
        ]
    }
    #[cfg(target_os = "linux")]
    {
        vec![
            ("HOME", state_root.to_path_buf()),
            ("XDG_CACHE_HOME", state_root.join("cache")),
            ("XDG_CONFIG_HOME", state_root.join("config")),
            ("XDG_DATA_HOME", state_root.join("data")),
        ]
    }
    #[cfg(target_os = "windows")]
    {
        vec![("WEBVIEW2_USER_DATA_FOLDER", state_root.join("webview"))]
    }
}

fn resolved_state_root() -> Result<PathBuf, Box<dyn Error>> {
    let operator_data_dir = absolute_environment_path("OPERATOR_DATA_DIR")?;
    let operator_run_file = absolute_environment_path("OPERATOR_RUN_FILE")?;
    #[cfg(not(target_os = "windows"))]
    let home_dir = env::var_os("HOME")
        .filter(|path| !path.is_empty())
        .map(PathBuf::from);
    #[cfg(target_os = "windows")]
    let home_dir = env::var_os("USERPROFILE")
        .filter(|path| !path.is_empty())
        .map(PathBuf::from);

    resolve_state_root(
        operator_data_dir.as_deref(),
        operator_run_file.as_deref(),
        home_dir.as_deref(),
        if cfg!(debug_assertions) {
            StateProfile::Development
        } else {
            StateProfile::Production
        },
    )
    .map_err(std::io::Error::other)
    .map_err(Into::into)
}

#[tauri::command]
fn complete_state_audit(app: tauri::AppHandle) -> Result<(), String> {
    let mode = env::var("OPERATOR_TAURI_STATE_AUDIT_MODE").map_err(|error| error.to_string())?;
    let state_root = resolved_state_root().map_err(|error| error.to_string())?;
    fs::write(
        state_root.join(format!("renderer-{mode}-complete")),
        b"complete",
    )
    .map_err(|error| error.to_string())?;
    if mode == "crash" {
        panic!("Operator Tauri state audit crash");
    }
    app.exit(0);
    Ok(())
}

#[tauri::command]
fn fail_state_audit(app: tauri::AppHandle, failure: String) {
    eprintln!("{failure}");
    app.exit(70);
}

pub fn run() -> Result<(), Box<dyn Error>> {
    let state_root = resolved_state_root()?;
    fs::create_dir_all(&state_root)?;
    for (name, path) in state_environment(&state_root) {
        env::set_var(name, path);
    }

    let audit_mode = env::var("OPERATOR_TAURI_STATE_AUDIT_MODE").ok();
    if !matches!(
        audit_mode.as_deref(),
        None | Some("shutdown") | Some("crash")
    ) {
        return Err(std::io::Error::other("invalid OPERATOR_TAURI_STATE_AUDIT_MODE").into());
    }
    if audit_mode.as_deref() == Some("crash") {
        let crash_report = state_root.join("rust-panic-report");
        std::panic::set_hook(Box::new(move |_| {
            let exit_code = if fs::write(&crash_report, b"panic").is_ok() {
                101
            } else {
                70
            };
            std::process::exit(exit_code);
        }));
    }
    let audit_script = audit_mode.as_ref().map(|_| {
        r##"
void (async () => {
  localStorage.setItem("operator-state-audit", "local");
  sessionStorage.setItem("operator-state-audit", "session");
  document.cookie = "operator_state_audit=cookie; SameSite=Strict";
  history.pushState({ audit: true }, "", "#operator-state-audit");
  const cache = await caches.open("operator-state-audit");
  await cache.put("https://tauri.localhost/operator-state-audit", new Response("cache"));
  await window.__TAURI_INTERNALS__.invoke("complete_state_audit");
})().catch((error) => window.__TAURI_INTERNALS__.invoke("fail_state_audit", {
  failure: String(error),
}));
"##
        .to_owned()
    });

    let mut builder = tauri::Builder::default();
    if audit_mode.is_some() {
        builder = builder.invoke_handler(tauri::generate_handler![
            complete_state_audit,
            fail_state_audit
        ]);
    }
    builder
        .setup(move |app| {
            let mut window = tauri::WebviewWindowBuilder::new(
                app,
                "main",
                tauri::WebviewUrl::App("index.html".into()),
            )
            .title("Operator")
            .inner_size(1280.0, 800.0)
            .data_directory(state_root.join("webview"))
            .use_https_scheme(false);
            if let Some(script) = audit_script.clone() {
                window = window.initialization_script(script);
            }
            window.build()?;
            Ok(())
        })
        .run(tauri::generate_context!())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::path::{Path, PathBuf};

    use super::resolve_state_root;
    use super::state_environment;
    use super::StateProfile;

    fn test_root() -> PathBuf {
        if cfg!(target_os = "windows") {
            PathBuf::from(r"C:\operator-test")
        } else {
            PathBuf::from("/operator-test")
        }
    }

    #[test]
    fn state_root_prefers_operator_data_dir() {
        let override_root = test_root().join("override");
        let ignored_root = test_root().join("ignored");
        let home_root = test_root().join("home");
        let root = resolve_state_root(
            Some(&override_root.join("data")),
            Some(&ignored_root.join("running.json")),
            Some(&home_root),
            StateProfile::Production,
        )
        .unwrap();

        assert_eq!(root, override_root.join("tauri"));
    }

    #[test]
    fn state_root_uses_operator_run_file_without_data_override() {
        let override_root = test_root().join("override");
        let home_root = test_root().join("home");
        let root = resolve_state_root(
            None,
            Some(&override_root.join("running.json")),
            Some(&home_root),
            StateProfile::Production,
        )
        .unwrap();

        assert_eq!(root, override_root.join("tauri"));
    }

    #[test]
    fn state_root_separates_development_state() {
        let home_root = test_root().join("home");
        let root =
            resolve_state_root(None, None, Some(&home_root), StateProfile::Development).unwrap();

        assert_eq!(root, home_root.join(".operator").join("dev").join("tauri"));
    }

    #[test]
    fn state_root_fails_without_a_safe_base() {
        let error = resolve_state_root(None, None, None, StateProfile::Production).unwrap_err();

        assert_eq!(error, "Operator state root could not be resolved");
    }

    #[test]
    fn state_root_reparents_platform_state() {
        let root = Path::new("/tmp/operator/tauri");
        let environment = state_environment(root);

        #[cfg(target_os = "macos")]
        assert_eq!(
            environment,
            vec![
                ("CFFIXED_USER_HOME", root.to_path_buf()),
                ("HOME", root.to_path_buf()),
            ]
        );
        #[cfg(target_os = "linux")]
        assert_eq!(
            environment,
            vec![
                ("HOME", root.to_path_buf()),
                ("XDG_CACHE_HOME", root.join("cache")),
                ("XDG_CONFIG_HOME", root.join("config")),
                ("XDG_DATA_HOME", root.join("data")),
            ]
        );
        #[cfg(target_os = "windows")]
        assert_eq!(
            environment,
            vec![("WEBVIEW2_USER_DATA_FOLDER", root.join("webview"))]
        );
    }
}
