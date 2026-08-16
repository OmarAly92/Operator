import Flutter
import UIKit

enum HapticsPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "operator/haptics", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "notify", let kind = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let type: UINotificationFeedbackGenerator.FeedbackType
      switch kind {
      case "success": type = .success
      case "warning": type = .warning
      case "error": type = .error
      default:
        result(FlutterError(code: "bad_arg", message: "unknown kind \(kind)", details: nil))
        return
      }
      let generator = UINotificationFeedbackGenerator()
      generator.prepare()
      generator.notificationOccurred(type)
      result(nil)
    }
  }
}
