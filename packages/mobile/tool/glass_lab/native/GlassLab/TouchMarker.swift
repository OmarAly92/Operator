import ObjectiveC
import SwiftUI
import UIKit

extension Notification.Name {
    static let labTouch = Notification.Name("lab.touch")
}

enum TouchRelay {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        guard
            let original = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.sendEvent(_:))),
            let replacement = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.labSendEvent(_:)))
        else { return }
        method_exchangeImplementations(original, replacement)
    }

    static func relay(_ event: UIEvent) {
        guard event.type == .touches, let touch = event.allTouches?.first else { return }
        NotificationCenter.default.post(name: .labTouch, object: touch.phase.rawValue)
    }
}

extension UIWindow {
    @objc func labSendEvent(_ event: UIEvent) {
        labSendEvent(event)
        TouchRelay.relay(event)
    }
}

struct TouchMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> TouchMarkerView {
        TouchRelay.install()
        return TouchMarkerView()
    }

    func updateUIView(_ uiView: TouchMarkerView, context: Context) {}
}

final class TouchMarkerView: UIView {
    static let restDelay: TimeInterval = 0.25
    private var observer: NSObjectProtocol?
    private var generation = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isUserInteractionEnabled = false
        observer = NotificationCenter.default.addObserver(forName: .labTouch, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.object as? Int, let phase = UITouch.Phase(rawValue: raw) else { return }
            self?.show(phase)
        }
    }

    required init?(coder: NSCoder) { nil }

    private func show(_ phase: UITouch.Phase) {
        generation += 1
        switch phase {
        case .began, .stationary:
            backgroundColor = .red
        case .moved:
            backgroundColor = .green
        case .ended, .cancelled:
            backgroundColor = .blue
            let current = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.restDelay) { [weak self] in
                guard let self, self.generation == current else { return }
                self.backgroundColor = .black
            }
        default:
            break
        }
    }
}
