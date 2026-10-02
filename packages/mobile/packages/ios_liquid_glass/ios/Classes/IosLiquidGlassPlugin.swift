import Flutter
import UIKit

public class IosLiquidGlassPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var sink: FlutterEventSink?

    private static let notifications: [Notification.Name] = [
        UIAccessibility.reduceTransparencyStatusDidChangeNotification,
        UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
        UIAccessibility.reduceMotionStatusDidChangeNotification,
    ]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterEventChannel(name: "ios_liquid_glass/accessibility", binaryMessenger: registrar.messenger())
        channel.setStreamHandler(IosLiquidGlassPlugin())
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        for name in Self.notifications {
            NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: name, object: nil)
        }
        send()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NotificationCenter.default.removeObserver(self)
        sink = nil
        return nil
    }

    @objc private func settingsChanged() {
        send()
    }

    private func send() {
        sink?([
            "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled,
            "increaseContrast": UIAccessibility.isDarkerSystemColorsEnabled,
            "reduceMotion": UIAccessibility.isReduceMotionEnabled,
        ])
    }
}
