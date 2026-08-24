use crate::menu::MenuPlatform;

pub const MAX_MENU_SESSIONS: usize = 8;
pub const TRAY_ICON_PNG: &[u8] = include_bytes!("../../assets/trayIconTemplate.png");
pub const TRAY_OPEN_SESSION_EVENT: &str = "tray:open-session";

pub const APP_LOCALES: [&str; 8] = ["en", "zh-CN", "ja", "ko", "es", "fr", "de", "pt-BR"];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Zone {
    Merge,
    Action,
}

impl Zone {
    pub fn rank(self) -> u8 {
        match self {
            Zone::Merge => 0,
            Zone::Action => 1,
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "merge" => Some(Zone::Merge),
            "action" => Some(Zone::Action),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SessionEntry {
    pub project_id: String,
    pub project_name: String,
    pub session_id: String,
    pub title: String,
    pub zone: Zone,
}

impl SessionEntry {
    pub fn new(
        project_id: &str,
        project_name: &str,
        session_id: &str,
        title: &str,
        zone: Zone,
    ) -> Self {
        Self {
            project_id: project_id.to_string(),
            project_name: project_name.to_string(),
            session_id: session_id.to_string(),
            title: title.to_string(),
            zone,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenSessionTarget {
    pub project_id: String,
    pub session_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ItemSpec {
    DisabledLabel(String),
    Separator,
    Session { id: String, label: String },
    Submenu { label: String, items: Vec<ItemSpec> },
    Action { id: String, label: String },
    NativeQuit,
}

#[derive(Debug, PartialEq, Eq)]
pub struct TrayPlan {
    pub title: Option<String>,
    pub tooltip: String,
    pub items: Vec<ItemSpec>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TrayStrings {
    pub empty: String,
    pub more: String,
    pub quit: String,
    pub show: String,
    pub untitled: String,
    pub tooltip_one: String,
    pub tooltip_other: String,
    pub zone_merge: String,
    pub zone_action: String,
}

pub fn is_tray_enabled(platform: MenuPlatform, is_packaged: bool, version: &str) -> bool {
    platform == MenuPlatform::Macos && (!is_packaged || version.contains("-nightly."))
}

const EN_CATALOG: &[u8] = include_bytes!("../../src/renderer/i18n/en.json");
const ZH_CN_CATALOG: &[u8] = include_bytes!("../../src/renderer/i18n/zh-CN.json");
const JA_CATALOG: &[u8] = include_bytes!("../../src/renderer/i18n/ja.json");
const KO_CATALOG: &[u8] = include_bytes!("../../src/renderer/i18n/ko.json");
const ES_CATALOG: &[u8] = include_bytes!("../../src/renderer/i18n/es.json");
const FR_CATALOG: &[u8] = include_bytes!("../../src/renderer/i18n/fr.json");
const DE_CATALOG: &[u8] = include_bytes!("../../src/renderer/i18n/de.json");
const PT_BR_CATALOG: &[u8] = include_bytes!("../../src/renderer/i18n/pt-BR.json");

fn catalog_bytes(locale: &str) -> &'static [u8] {
    match locale {
        "zh-CN" => ZH_CN_CATALOG,
        "ja" => JA_CATALOG,
        "ko" => KO_CATALOG,
        "es" => ES_CATALOG,
        "fr" => FR_CATALOG,
        "de" => DE_CATALOG,
        "pt-BR" => PT_BR_CATALOG,
        _ => EN_CATALOG,
    }
}

fn catalog_value(locale: &str, key: &str) -> Option<String> {
    let catalog: serde_json::Value = serde_json::from_slice(catalog_bytes(locale)).ok()?;
    catalog.get(key)?.as_str().map(str::to_string)
}

pub fn load_strings(locale: &str) -> TrayStrings {
    let pick = |key: &str| {
        catalog_value(locale, key)
            .or_else(|| catalog_value("en", key))
            .unwrap_or_default()
    };
    TrayStrings {
        empty: pick("tray.empty"),
        more: pick("tray.more"),
        quit: pick("tray.quit"),
        show: pick("tray.show"),
        untitled: pick("tray.untitledSession"),
        tooltip_one: pick("tray.attentionTooltip_one"),
        tooltip_other: pick("tray.attentionTooltip_other"),
        zone_merge: pick("zone.merge"),
        zone_action: pick("zone.action"),
    }
}

fn format_template(template: &str, count: usize) -> String {
    template.replace("{{count}}", &count.to_string())
}

fn session_label(entry: &SessionEntry, strings: &TrayStrings) -> String {
    let title = if entry.title.is_empty() {
        strings.untitled.clone()
    } else {
        entry.title.clone()
    };
    if entry.project_name.is_empty() {
        title
    } else {
        format!("{title}  \u{b7}  {}", entry.project_name)
    }
}

pub fn session_item_id(entry: &SessionEntry) -> String {
    format!("session/{}/{}", entry.project_id, entry.session_id)
}

pub fn parse_session_item_id(id: &str) -> Option<OpenSessionTarget> {
    let rest = id.strip_prefix("session/")?;
    let mut parts = rest.splitn(2, '/');
    let project_id = parts.next()?.to_string();
    let session_id = parts.next()?.to_string();
    if session_id.is_empty() || session_id.contains('/') {
        return None;
    }
    if project_id.is_empty() {
        return None;
    }
    Some(OpenSessionTarget {
        project_id,
        session_id,
    })
}

pub fn render(sessions: &[SessionEntry], strings: &TrayStrings) -> TrayPlan {
    let count = sessions.len();
    let tooltip = if count == 0 {
        "Operator".to_string()
    } else if count == 1 {
        format_template(&strings.tooltip_one, count)
    } else {
        format_template(&strings.tooltip_other, count)
    };

    let mut items: Vec<ItemSpec> = Vec::new();
    if count == 0 {
        items.push(ItemSpec::DisabledLabel(strings.empty.clone()));
    } else {
        let mut ordered: Vec<&SessionEntry> = sessions.iter().collect();
        ordered.sort_by(|left, right| {
            left.zone
                .rank()
                .cmp(&right.zone.rank())
                .then_with(|| left.title.cmp(&right.title))
        });
        let visible = &ordered[..ordered.len().min(MAX_MENU_SESSIONS)];
        let overflow = ordered.len().saturating_sub(MAX_MENU_SESSIONS);

        let mut last_zone: Option<Zone> = None;
        for entry in visible {
            if last_zone != Some(entry.zone) {
                if last_zone.is_some() {
                    items.push(ItemSpec::Separator);
                }
                let header = match entry.zone {
                    Zone::Merge => &strings.zone_merge,
                    Zone::Action => &strings.zone_action,
                };
                items.push(ItemSpec::DisabledLabel(header.clone()));
                last_zone = Some(entry.zone);
            }
            items.push(ItemSpec::Session {
                id: session_item_id(entry),
                label: session_label(entry, strings),
            });
        }
        if overflow > 0 {
            let submenu_items: Vec<ItemSpec> = ordered[MAX_MENU_SESSIONS..]
                .iter()
                .map(|entry| ItemSpec::Session {
                    id: session_item_id(entry),
                    label: session_label(entry, strings),
                })
                .collect();
            items.push(ItemSpec::Separator);
            items.push(ItemSpec::Submenu {
                label: format!("{} ({overflow})", strings.more),
                items: submenu_items,
            });
        }
    }
    items.push(ItemSpec::Separator);
    items.push(ItemSpec::Action {
        id: "show".to_string(),
        label: strings.show.clone(),
    });
    items.push(ItemSpec::NativeQuit);

    TrayPlan {
        title: (count > 0).then(|| count.to_string()),
        tooltip,
        items,
    }
}

#[derive(Default)]
pub struct PendingTarget {
    ready: bool,
    pending: Option<OpenSessionTarget>,
}
impl PendingTarget {
    pub fn open_session(&mut self, target: OpenSessionTarget) -> Option<OpenSessionTarget> {
        if self.ready {
            Some(target)
        } else {
            self.pending = Some(target);
            None
        }
    }

    pub fn renderer_ready(&mut self) -> Option<OpenSessionTarget> {
        self.ready = true;
        self.pending.take()
    }

    pub fn reset(&mut self) {
        self.ready = false;
        self.pending = None;
    }

    pub fn ready(&self) -> bool {
        self.ready
    }
}

pub struct TrayHandle {
    icon: tauri::tray::TrayIcon<tauri::Wry>,
}

use tauri::Manager;

impl TrayHandle {
    pub fn apply(&self, app: &tauri::AppHandle, plan: &TrayPlan) -> Result<(), String> {
        let menu = build_menu(app, plan)?;
        self.icon
            .set_menu(Some(menu))
            .map_err(|error| error.to_string())?;
        self.icon
            .set_tooltip(Some(plan.tooltip.clone()))
            .map_err(|error| error.to_string())?;
        #[cfg(target_os = "macos")]
        self.icon
            .set_title(plan.title.clone())
            .map_err(|error| error.to_string())?;
        Ok(())
    }
}

type MenuResult<T> = Result<T, String>;

fn build_menu(
    app: &tauri::AppHandle,
    plan: &TrayPlan,
) -> MenuResult<tauri::menu::Menu<tauri::Wry>> {
    let mut entries: Vec<std::sync::Arc<dyn tauri::menu::IsMenuItem<tauri::Wry>>> =
        Vec::with_capacity(plan.items.len());
    for (index, spec) in plan.items.iter().enumerate() {
        match spec {
            ItemSpec::DisabledLabel(label) => {
                let item = tauri::menu::MenuItem::with_id(
                    app,
                    format!("disabled-{index}"),
                    label.as_str(),
                    false,
                    None::<&str>,
                )
                .map_err(|error| error.to_string())?;
                entries.push(std::sync::Arc::new(item));
            }
            ItemSpec::Separator => {
                let separator = tauri::menu::PredefinedMenuItem::separator(app)
                    .map_err(|error| error.to_string())?;
                entries.push(std::sync::Arc::new(separator));
            }
            ItemSpec::Session { id, label } => {
                let item = tauri::menu::MenuItem::with_id(
                    app,
                    id.as_str(),
                    label.as_str(),
                    true,
                    None::<&str>,
                )
                .map_err(|error| error.to_string())?;
                entries.push(std::sync::Arc::new(item));
            }
            ItemSpec::Action { id, label } => {
                let item = tauri::menu::MenuItem::with_id(
                    app,
                    id.as_str(),
                    label.as_str(),
                    true,
                    None::<&str>,
                )
                .map_err(|error| error.to_string())?;
                entries.push(std::sync::Arc::new(item));
            }
            ItemSpec::Submenu { label, items } => {
                let submenu = build_submenu(app, label, items)?;
                entries.push(std::sync::Arc::new(submenu));
            }
            ItemSpec::NativeQuit => {
                let quit = tauri::menu::PredefinedMenuItem::quit(app, None)
                    .map_err(|error| error.to_string())?;
                entries.push(std::sync::Arc::new(quit));
            }
        }
    }
    let refs: Vec<&dyn tauri::menu::IsMenuItem<tauri::Wry>> =
        entries.iter().map(|entry| entry.as_ref()).collect();
    tauri::menu::MenuBuilder::new(app)
        .items(&refs)
        .build()
        .map_err(|error| error.to_string())
}

fn build_submenu(
    app: &tauri::AppHandle,
    label: &str,
    items: &[ItemSpec],
) -> MenuResult<tauri::menu::Submenu<tauri::Wry>> {
    let mut submenu = tauri::menu::SubmenuBuilder::new(app, label);
    for (index, spec) in items.iter().enumerate() {
        match spec {
            ItemSpec::Session { id, label } | ItemSpec::Action { id, label } => {
                submenu = submenu.item(
                    &tauri::menu::MenuItem::with_id(
                        app,
                        id.as_str(),
                        label.as_str(),
                        true,
                        None::<&str>,
                    )
                    .map_err(|error| error.to_string())?,
                );
            }
            ItemSpec::DisabledLabel(text) => {
                submenu = submenu.item(
                    &tauri::menu::MenuItem::with_id(
                        app,
                        format!("submenu-disabled-{index}"),
                        text.as_str(),
                        false,
                        None::<&str>,
                    )
                    .map_err(|error| error.to_string())?,
                );
            }
            ItemSpec::Separator => submenu = submenu.separator(),
            ItemSpec::Submenu { .. } | ItemSpec::NativeQuit => {}
        }
    }
    submenu.build().map_err(|error| error.to_string())
}

pub fn create_tray(app: &tauri::AppHandle, locale: &str) -> MenuResult<Option<TrayHandle>> {
    if !cfg!(target_os = "macos") {
        return Ok(None);
    }
    let image =
        tauri::image::Image::from_bytes(TRAY_ICON_PNG).map_err(|error| error.to_string())?;
    let strings = load_strings(locale);
    let plan = render(&[], &strings);
    let menu = build_menu(app, &plan)?;
    let mut builder = tauri::tray::TrayIconBuilder::with_id("operator-tray")
        .icon(image)
        .tooltip(plan.tooltip.clone())
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app_handle, event| {
            crate::native::handle_tray_menu_event(app_handle, &event);
        });
    builder = builder.icon_as_template(true);
    let icon = builder.build(app).map_err(|error| error.to_string())?;
    icon.set_title(plan.title)
        .map_err(|error| error.to_string())?;
    Ok(Some(TrayHandle { icon }))
}

pub fn apply_state(app: &tauri::AppHandle, sessions: &[SessionEntry]) -> Result<(), String> {
    let Some(shell) = app.try_state::<crate::native::ShellState>() else {
        return Ok(());
    };
    let tray_guard = shell
        .tray
        .lock()
        .map_err(|_| "tray state poisoned".to_string())?;
    let Some(handle) = tray_guard.as_ref() else {
        return Ok(());
    };
    let locale = shell
        .locale
        .lock()
        .map(|current| current.clone())
        .unwrap_or_else(|_| "en".to_string());
    let strings = load_strings(&locale);
    let plan = render(sessions, &strings);
    handle.apply(app, &plan)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tray_is_darwin_only_and_nightly_gated_when_packaged() {
        let darwin = MenuPlatform::Macos;
        assert!(is_tray_enabled(darwin, false, "0.10.3"));
        assert!(!is_tray_enabled(darwin, true, "0.10.3"));
        assert!(is_tray_enabled(darwin, true, "0.11.0-nightly.20260822"));
        for platform in [MenuPlatform::Windows, MenuPlatform::Linux] {
            assert!(!is_tray_enabled(platform, false, "0.11.0-nightly.20260822"));
        }
    }

    #[test]
    fn every_locale_resolves_the_full_tray_string_set_from_the_shared_catalogs() {
        for locale in APP_LOCALES {
            let strings = load_strings(locale);
            for (label, value) in [
                ("empty", &strings.empty),
                ("more", &strings.more),
                ("quit", &strings.quit),
                ("show", &strings.show),
                ("untitled", &strings.untitled),
                ("tooltip_one", &strings.tooltip_one),
                ("tooltip_other", &strings.tooltip_other),
                ("zone_merge", &strings.zone_merge),
                ("zone_action", &strings.zone_action),
            ] {
                assert!(
                    !value.trim().is_empty(),
                    "{locale}.{label} must not be blank"
                );
            }
        }
    }

    #[test]
    fn catalogs_match_the_canonical_english_and_german_files() {
        let en = load_strings("en");
        assert_eq!(en.show, "Show Operator");
        assert_eq!(en.empty, "No sessions need attention");
        assert_eq!(en.tooltip_one, "{{count}} session needs attention");
        assert_eq!(en.tooltip_other, "{{count}} sessions need attention");

        let de = load_strings("de");
        assert_eq!(de.show, "Operator anzeigen");
        assert_eq!(de.more, "Mehr");
        assert_eq!(load_strings("unknown-locale"), en);
    }

    #[test]
    fn empty_states_render_a_disabled_label_without_sessions() {
        let plan = render(&[], &load_strings("en"));

        assert_eq!(plan.title, None);
        assert_eq!(plan.tooltip, "Operator");
        assert_eq!(
            plan.items,
            vec![
                ItemSpec::DisabledLabel("No sessions need attention".to_string()),
                ItemSpec::Separator,
                ItemSpec::Action {
                    id: "show".to_string(),
                    label: "Show Operator".to_string()
                },
                ItemSpec::NativeQuit,
            ]
        );
    }

    #[test]
    fn sessions_sort_by_zone_then_title_with_headers_and_separators() {
        let sessions = [
            SessionEntry::new("p2", "Beta", "s3", "Zulu task", Zone::Action),
            SessionEntry::new("p1", "Alpha", "s2", "beta merge", Zone::Merge),
            SessionEntry::new("p1", "Alpha", "s1", "alpha merge", Zone::Merge),
        ];
        let plan = render(&sessions, &load_strings("en"));

        assert_eq!(plan.title, Some("3".to_string()));
        assert_eq!(plan.tooltip, "3 sessions need attention");
        assert_eq!(
            plan.items[..5],
            [
                ItemSpec::DisabledLabel("Ready to merge".to_string()),
                ItemSpec::Session {
                    id: "session/p1/s1".to_string(),
                    label: "alpha merge  \u{b7}  Alpha".to_string()
                },
                ItemSpec::Session {
                    id: "session/p1/s2".to_string(),
                    label: "beta merge  \u{b7}  Alpha".to_string()
                },
                ItemSpec::Separator,
                ItemSpec::DisabledLabel("Needs you".to_string()),
            ]
        );
        assert!(matches!(&plan.items[5], ItemSpec::Session { id, .. } if id == "session/p2/s3"));
    }

    #[test]
    fn untitled_sessions_fall_back_to_the_localized_label() {
        let sessions = [SessionEntry::new("p1", "", "s1", "", Zone::Action)];
        let plan = render(&sessions, &load_strings("de"));

        assert_eq!(
            plan.items[1],
            ItemSpec::Session {
                id: "session/p1/s1".to_string(),
                label: "Unbenannte Sitzung".to_string()
            }
        );
    }

    #[test]
    fn singular_attention_tooltips_cover_one_session() {
        let sessions = [SessionEntry::new("p1", "Alpha", "s1", "t", Zone::Merge)];
        let plan = render(&sessions, &load_strings("en"));

        assert_eq!(plan.title, Some("1".to_string()));
        assert_eq!(plan.tooltip, "1 session needs attention");
    }

    #[test]
    fn menus_cap_at_eight_visible_sessions_with_an_overflow_submenu() {
        let mut sessions = Vec::new();
        for index in 0..12 {
            sessions.push(SessionEntry::new(
                "p1",
                "Alpha",
                &format!("s{index:02}"),
                &format!("task {index:02}"),
                Zone::Action,
            ));
        }
        let plan = render(&sessions, &load_strings("en"));

        let visible = plan
            .items
            .iter()
            .filter(|item| matches!(item, ItemSpec::Session { .. }))
            .count();
        assert_eq!(visible, 8);
        let overflow = plan.items.iter().find_map(|item| match item {
            ItemSpec::Submenu { label, items } => Some((label.clone(), items.len())),
            _ => None,
        });
        assert_eq!(overflow, Some(("More (4)".to_string(), 4)));
    }

    #[test]
    fn session_item_ids_round_trip_through_the_open_session_parser() {
        let entry = SessionEntry::new("proj-uuid", "Alpha", "sess-uuid", "t", Zone::Merge);
        let id = session_item_id(&entry);
        assert_eq!(
            parse_session_item_id(&id),
            Some(OpenSessionTarget {
                project_id: "proj-uuid".to_string(),
                session_id: "sess-uuid".to_string()
            })
        );
        for malformed in [
            "show",
            "session",
            "session/only-project",
            "session/p/s/extra",
            "",
        ] {
            assert_eq!(parse_session_item_id(malformed), None, "{malformed}");
        }
    }

    #[test]
    fn pending_targets_hold_until_the_renderer_reports_ready() {
        let mut pending = PendingTarget::default();
        let first = OpenSessionTarget {
            project_id: "p".into(),
            session_id: "s1".into(),
        };
        let second = OpenSessionTarget {
            project_id: "p".into(),
            session_id: "s2".into(),
        };

        assert_eq!(pending.open_session(first.clone()), None);
        assert_eq!(pending.open_session(second.clone()), None);

        assert_eq!(pending.renderer_ready(), Some(second));

        let third = OpenSessionTarget {
            project_id: "p".into(),
            session_id: "s3".into(),
        };
        assert_eq!(pending.open_session(third.clone()), Some(third));
    }

    #[test]
    fn renderer_reloads_clear_pending_targets_and_disarm_until_reregistration() {
        let mut pending = PendingTarget::default();
        assert_eq!(
            pending.open_session(OpenSessionTarget {
                project_id: "p".into(),
                session_id: "s1".into()
            }),
            None
        );

        pending.reset();

        assert!(!pending.ready());
        let reloaded = OpenSessionTarget {
            project_id: "p".into(),
            session_id: "s2".into(),
        };
        assert_eq!(pending.open_session(reloaded.clone()), None);
        assert_eq!(pending.renderer_ready(), Some(reloaded));
    }
}
