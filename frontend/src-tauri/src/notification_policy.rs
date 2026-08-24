pub const CLICK_EVENT: &str = "notifications:click";

pub const ATTENTION_TYPES: [&str; 2] = ["needs_input", "ready_to_merge"];

#[derive(Debug, PartialEq, Eq)]
pub enum SignalAction {
    Toast,
    Attention,
}

pub fn should_signal_attention(notification_type: Option<&str>) -> bool {
    notification_type.is_some_and(|kind| ATTENTION_TYPES.contains(&kind))
}

pub fn should_toast(title: Option<&str>, supported: bool) -> bool {
    title.is_some_and(|title| !title.is_empty()) && supported
}

pub fn show_plan(
    focused: bool,
    supported: bool,
    title: Option<&str>,
    notification_type: Option<&str>,
) -> Vec<SignalAction> {
    if focused {
        return Vec::new();
    }
    let mut plan = Vec::with_capacity(2);
    if should_toast(title, supported) {
        plan.push(SignalAction::Toast);
    }
    if should_signal_attention(notification_type) {
        plan.push(SignalAction::Attention);
    }
    plan
}

pub fn normalize_badge_count(count: f64) -> i64 {
    if !count.is_finite() || count <= 0.0 {
        return 0;
    }
    count.min(i64::MAX as f64) as i64
}

pub fn dev_bounce_available(is_packaged: bool) -> bool {
    !is_packaged
}

pub trait ClickHost {
    fn focus_main_window(&mut self);
    fn send_clicked(&mut self, id: &str);
}

pub fn route_click(id: &str, host: &mut impl ClickHost) {
    host.focus_main_window();
    host.send_clicked(id);
}

#[cfg(test)]
mod tests {
    use super::*;

    const ALL_TYPES: [&str; 4] = [
        "needs_input",
        "ready_to_merge",
        "pr_merged",
        "pr_closed_unmerged",
    ];

    #[test]
    fn toasts_fire_for_every_backend_type_when_supported() {
        for notification_type in ALL_TYPES {
            let expected = if should_signal_attention(Some(notification_type)) {
                vec![SignalAction::Toast, SignalAction::Attention]
            } else {
                vec![SignalAction::Toast]
            };
            assert_eq!(
                show_plan(
                    false,
                    true,
                    Some(&format!("{notification_type} title")),
                    Some(notification_type)
                ),
                expected,
                "type {notification_type}"
            );
        }
    }

    #[test]
    fn toasts_are_skipped_without_a_title_or_support() {
        assert!(show_plan(false, true, Some(""), Some("needs_input"))
            .contains(&SignalAction::Attention));
        assert!(!show_plan(false, true, Some(""), None).contains(&SignalAction::Toast));
        assert_eq!(
            show_plan(false, false, Some("titled"), None),
            Vec::<SignalAction>::new()
        );
    }

    #[test]
    fn attention_signals_only_for_the_actionable_types() {
        for actionable in ["needs_input", "ready_to_merge"] {
            assert!(should_signal_attention(Some(actionable)), "{actionable}");
        }
        for informational in ["pr_merged", "pr_closed_unmerged", "some_future_type"] {
            assert!(
                !should_signal_attention(Some(informational)),
                "{informational}"
            );
        }
        assert!(!should_signal_attention(None));
    }

    #[test]
    fn attention_fires_even_when_the_toast_is_suppressed() {
        assert_eq!(
            show_plan(false, true, Some(""), Some("needs_input")),
            vec![SignalAction::Attention]
        );
        assert_eq!(
            show_plan(false, false, Some("title"), Some("ready_to_merge")),
            vec![SignalAction::Attention]
        );
    }

    #[test]
    fn everything_is_suppressed_while_the_window_has_focus() {
        assert_eq!(
            show_plan(true, true, Some("needs input"), Some("needs_input")),
            Vec::<SignalAction>::new()
        );
        assert_eq!(
            show_plan(true, true, Some("merged"), Some("pr_merged")),
            Vec::<SignalAction>::new()
        );
    }

    #[test]
    fn badge_counts_normalize_to_nonnegative_integers() {
        assert_eq!(normalize_badge_count(0.0), 0);
        assert_eq!(normalize_badge_count(3.0), 3);
        assert_eq!(normalize_badge_count(4.7), 4);
        assert_eq!(normalize_badge_count(-2.0), 0);
        assert_eq!(normalize_badge_count(f64::NAN), 0);
        assert_eq!(normalize_badge_count(f64::INFINITY), 0);
        assert_eq!(normalize_badge_count(-f64::INFINITY), 0);
        assert_eq!(normalize_badge_count(f64::MAX), i64::MAX);
    }

    #[test]
    fn dev_bounce_is_dev_only() {
        assert!(dev_bounce_available(false));
        assert!(!dev_bounce_available(true));
    }

    #[derive(Default)]
    struct FakeClickHost {
        focused: usize,
        clicked: Vec<String>,
    }

    impl ClickHost for FakeClickHost {
        fn focus_main_window(&mut self) {
            self.focused += 1;
        }

        fn send_clicked(&mut self, id: &str) {
            self.clicked.push(id.to_string());
        }
    }

    #[test]
    fn clicks_restore_focus_and_route_the_notification_id() {
        let mut host = FakeClickHost::default();

        route_click("notif-42", &mut host);

        assert_eq!(host.focused, 1);
        assert_eq!(host.clicked, vec!["notif-42".to_string()]);
    }

    #[test]
    fn click_event_channel_matches_the_renderer_subscription() {
        assert_eq!(CLICK_EVENT, "notifications:click");
    }
}
