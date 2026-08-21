pub mod discovery;
pub mod supervisor;

#[cfg(test)]
mod tests;

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DaemonStatus {
    pub state: String,
    pub port: Option<u16>,
    pub pid: Option<u32>,
    pub executable_path: Option<String>,
    pub working_directory: Option<String>,
    pub message: Option<String>,
    pub details: Option<String>,
    pub code: Option<String>,
    pub exit_code: Option<i32>,
    pub signal: Option<String>,
}

impl Default for DaemonStatus {
    fn default() -> Self {
        Self {
            state: "stopped".to_string(),
            port: None,
            pid: None,
            executable_path: None,
            working_directory: None,
            message: None,
            details: None,
            code: None,
            exit_code: None,
            signal: None,
        }
    }
}

pub use discovery::DaemonLaunchSpec;

pub fn env_map() -> HashMap<String, String> {
    std::env::vars().collect()
}

pub fn home_dir() -> PathBuf {
    #[cfg(windows)]
    {
        std::env::var_os("USERPROFILE")
            .map(PathBuf::from)
            .unwrap_or(PathBuf::from("C:\\"))
    }
    #[cfg(not(windows))]
    {
        std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or(PathBuf::from("/tmp"))
    }
}

pub fn is_packaged() -> bool {
    !cfg!(debug_assertions)
}

pub fn app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

pub fn resource_dir() -> PathBuf {
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            return parent.to_path_buf();
        }
    }
    PathBuf::from(".")
}

pub fn app_path() -> PathBuf {
    std::env::current_dir().unwrap_or(PathBuf::from("."))
}
