import Foundation
import XCTest

enum Target {
    case point(CGFloat, CGFloat)
    case element(String, dx: CGFloat, dy: CGFloat)

    init(json: Any) throws {
        if let pair = json as? [Double], pair.count == 2 {
            self = .point(CGFloat(pair[0]), CGFloat(pair[1]))
        } else if let name = json as? String {
            self = .element(name, dx: 0, dy: 0)
        } else if let object = json as? [String: Any], let name = object["element"] as? String {
            self = .element(name, dx: CGFloat(object["dx"] as? Double ?? 0), dy: CGFloat(object["dy"] as? Double ?? 0))
        } else {
            throw StepError.malformed("target \(json)")
        }
    }
}

enum Step {
    case wait(Double)
    case tap(Target)
    case doubleTap(Target)
    case press(Target, duration: Double)
    case pressDrag(from: Target, to: Target, pressDuration: Double, velocity: Double?, hold: Double)

    static func decode(_ text: String) throws -> [Step] {
        let raw = try JSONSerialization.jsonObject(with: Data(text.utf8))
        guard let list = raw as? [[String: Any]] else { throw StepError.malformed("steps must be a list of objects") }
        return try list.map(Step.init(json:))
    }

    init(json: [String: Any]) throws {
        guard json.count == 1, let (kind, value) = json.first else { throw StepError.malformed("step \(json)") }
        switch kind {
        case "wait":
            guard let seconds = value as? Double else { throw StepError.malformed("wait \(value)") }
            self = .wait(seconds)
        case "tap":
            self = .tap(try Target(json: value))
        case "doubleTap":
            self = .doubleTap(try Target(json: value))
        case "press":
            guard let object = value as? [String: Any], let at = object["at"], let duration = object["duration"] as? Double else {
                throw StepError.malformed("press \(value)")
            }
            self = .press(try Target(json: at), duration: duration)
        case "pressDrag":
            guard let object = value as? [String: Any], let from = object["from"], let to = object["to"] else {
                throw StepError.malformed("pressDrag \(value)")
            }
            self = .pressDrag(
                from: try Target(json: from),
                to: try Target(json: to),
                pressDuration: object["pressDuration"] as? Double ?? 0.05,
                velocity: object["velocity"] as? Double,
                hold: object["hold"] as? Double ?? 0
            )
        default:
            throw StepError.malformed("unknown step \(kind)")
        }
    }
}

enum StepError: Error, CustomStringConvertible {
    case malformed(String)
    case missingElement(String, String)

    var description: String {
        switch self {
        case .malformed(let detail): return "malformed step: \(detail)"
        case .missingElement(let name, let tree): return "element \(name) not found\n\(tree)"
        }
    }
}

struct StepPlayer {
    let app: XCUIApplication

    func coordinate(_ target: Target) throws -> XCUICoordinate {
        switch target {
        case .point(let x, let y):
            return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
        case .element(let name, let dx, let dy):
            let element = app.descendants(matching: .any)[name].firstMatch
            guard element.waitForExistence(timeout: 5) else { throw StepError.missingElement(name, app.debugDescription) }
            return element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: dx, dy: dy))
        }
    }

    func play(_ step: Step) throws {
        switch step {
        case .wait(let seconds):
            Thread.sleep(forTimeInterval: seconds)
        case .tap(let target):
            try coordinate(target).tap()
        case .doubleTap(let target):
            try coordinate(target).doubleTap()
        case .press(let target, let duration):
            try coordinate(target).press(forDuration: duration)
        case .pressDrag(let from, let to, let pressDuration, let velocity, let hold):
            let start = try coordinate(from)
            let end = try coordinate(to)
            let speed = velocity.map { XCUIGestureVelocity(CGFloat($0)) } ?? .default
            start.press(forDuration: pressDuration, thenDragTo: end, withVelocity: speed, thenHoldForDuration: hold)
        }
    }
}
