use std::ptr::NonNull;
use std::sync::OnceLock;
use std::time::Duration;

use block2::RcBlock;
use objc2::rc::Retained;
use objc2::runtime::{Bool, ProtocolObject};
use objc2::{define_class, msg_send, AnyThread};
use objc2_foundation::{NSBundle, NSError, NSObject, NSObjectProtocol, NSString};
use objc2_user_notifications::{
    UNAuthorizationOptions, UNAuthorizationStatus, UNMutableNotificationContent, UNNotification,
    UNNotificationPresentationOptions, UNNotificationRequest, UNNotificationResponse,
    UNNotificationSettings, UNNotificationSound, UNUserNotificationCenter,
    UNUserNotificationCenterDelegate,
};
use tauri::AppHandle;
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver};

use crate::native::AppClickHost;
use crate::notification_policy::{permission_name, route_click, toast_failure, PermissionStatus};

const CALLBACK_TIMEOUT: Duration = Duration::from_secs(2);

static APP: OnceLock<AppHandle> = OnceLock::new();

define_class!(
    #[unsafe(super(NSObject))]
    #[name = "OperatorNotificationDelegate"]
    struct NotificationDelegate;

    unsafe impl NSObjectProtocol for NotificationDelegate {}

    unsafe impl UNUserNotificationCenterDelegate for NotificationDelegate {
        #[unsafe(method(userNotificationCenter:willPresentNotification:withCompletionHandler:))]
        fn will_present(
            &self,
            _center: &UNUserNotificationCenter,
            _notification: &UNNotification,
            completion_handler: &block2::DynBlock<dyn Fn(UNNotificationPresentationOptions)>,
        ) {
            completion_handler.call((UNNotificationPresentationOptions::Banner
                | UNNotificationPresentationOptions::List
                | UNNotificationPresentationOptions::Sound,));
        }

        #[unsafe(method(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:))]
        fn did_receive(
            &self,
            _center: &UNUserNotificationCenter,
            response: &UNNotificationResponse,
            completion_handler: &block2::DynBlock<dyn Fn()>,
        ) {
            let id = response.notification().request().identifier().to_string();
            if let Some(app) = APP.get() {
                route_click(&id, &mut AppClickHost(app));
            }
            completion_handler.call(());
        }
    }
);

impl NotificationDelegate {
    fn new() -> Retained<Self> {
        let this = Self::alloc().set_ivars(());
        unsafe { msg_send![super(this), init] }
    }
}

pub fn has_main_bundle_identifier() -> bool {
    NSBundle::mainBundle().bundleIdentifier().is_some()
}

pub fn install(app: &AppHandle) {
    let _ = APP.set(app.clone());
    let center = UNUserNotificationCenter::currentNotificationCenter();
    let delegate = NotificationDelegate::new();
    center.setDelegate(Some(ProtocolObject::from_ref(&*delegate)));
    std::mem::forget(delegate);
}

fn describe_error(error: *mut NSError) -> Option<String> {
    NonNull::new(error).map(|error| unsafe { error.as_ref() }.localizedDescription().to_string())
}

fn submit(id: &str, title: &str, body: Option<&str>) -> UnboundedReceiver<Option<String>> {
    let content = UNMutableNotificationContent::new();
    content.setTitle(&NSString::from_str(title));
    if let Some(body) = body {
        content.setBody(&NSString::from_str(body));
    }
    content.setSound(Some(&UNNotificationSound::defaultSound()));
    let request = UNNotificationRequest::requestWithIdentifier_content_trigger(
        &NSString::from_str(id),
        &content,
        None,
    );
    let (tx, rx) = unbounded_channel();
    let done = RcBlock::new(move |error: *mut NSError| {
        let _ = tx.send(describe_error(error));
    });
    UNUserNotificationCenter::currentNotificationCenter()
        .addNotificationRequest_withCompletionHandler(&request, Some(&done));
    rx
}

fn request_authorization() -> UnboundedReceiver<()> {
    let (tx, rx) = unbounded_channel();
    let done = RcBlock::new(move |granted: Bool, error: *mut NSError| {
        if !granted.as_bool() {
            eprintln!(
                "notification authorization was not granted: {}",
                describe_error(error).unwrap_or_default()
            );
        }
        let _ = tx.send(());
    });
    UNUserNotificationCenter::currentNotificationCenter()
        .requestAuthorizationWithOptions_completionHandler(
            UNAuthorizationOptions::Alert
                | UNAuthorizationOptions::Sound
                | UNAuthorizationOptions::Badge,
            &done,
        );
    rx
}

pub async fn ensure_authorization() -> &'static str {
    let status = authorization().await;
    if status != permission_name(Some(PermissionStatus::NotDetermined)) {
        return status;
    }
    let mut rx = request_authorization();
    let _ = rx.recv().await;
    authorization().await
}

pub async fn post(id: &str, title: &str, body: Option<&str>) -> Result<(), String> {
    ensure_authorization().await;
    let mut rx = submit(id, title, body);
    let detail = match tokio::time::timeout(CALLBACK_TIMEOUT, rx.recv()).await {
        Ok(Some(None)) => return Ok(()),
        Ok(Some(Some(detail))) => detail,
        Ok(None) => "the notification center dropped the request".to_string(),
        Err(_) => "the notification center did not answer".to_string(),
    };
    Err(toast_failure(authorization().await, &detail))
}

fn query_settings() -> UnboundedReceiver<UNAuthorizationStatus> {
    let (tx, rx) = unbounded_channel();
    let block = RcBlock::new(move |settings: NonNull<UNNotificationSettings>| {
        let status = unsafe { settings.as_ref() }.authorizationStatus();
        let _ = tx.send(status);
    });
    UNUserNotificationCenter::currentNotificationCenter()
        .getNotificationSettingsWithCompletionHandler(&block);
    rx
}

pub async fn authorization() -> &'static str {
    let mut rx = query_settings();
    let status = match tokio::time::timeout(CALLBACK_TIMEOUT, rx.recv()).await {
        Ok(Some(UNAuthorizationStatus::NotDetermined)) => Some(PermissionStatus::NotDetermined),
        Ok(Some(UNAuthorizationStatus::Denied)) => Some(PermissionStatus::Denied),
        Ok(Some(_)) => Some(PermissionStatus::Authorized),
        Ok(None) | Err(_) => None,
    };
    permission_name(status)
}

pub fn settings_url(bundle_id: &str) -> String {
    format!("x-apple.systempreferences:com.apple.Notifications-Settings.extension?id={bundle_id}")
}
