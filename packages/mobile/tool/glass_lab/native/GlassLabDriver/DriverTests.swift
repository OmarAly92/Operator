import XCTest

final class DriverTests: XCTestCase {
    func testScene() throws {
        let environment = ProcessInfo.processInfo.environment
        let target = try XCTUnwrap(environment["GLASS_TARGET"], "GLASS_TARGET missing")
        let scene = environment["GLASS_SCENE"] ?? ""
        let steps = try Step.decode(environment["GLASS_STEPS"] ?? "[]")
        let settle = Double(environment["GLASS_SETTLE"] ?? "") ?? 1.5
        let out = environment["GLASS_OUT"].map { URL(fileURLWithPath: $0) }
        let app = XCUIApplication(bundleIdentifier: target)
        if !scene.isEmpty {
            app.launchEnvironment["GLASS_LAB_SCENE"] = scene
            app.launchEnvironment["GLASS_LAB_BACKDROP"] = environment["GLASS_BACKDROP"] ?? "stripes"
            app.launchEnvironment["GLASS_LAB_BARE"] = environment["GLASS_BARE"] ?? "0"
        }
        app.launch()
        dismissSystemPrompts()
        if scene.isEmpty {
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        } else {
            let ready = app.descendants(matching: .any)["scene.ready"]
            XCTAssertTrue(ready.waitForExistence(timeout: 20), "scene.ready never appeared\n\(app.debugDescription)")
        }
        Thread.sleep(forTimeInterval: settle)
        let missing = !scene.isEmpty && app.descendants(matching: .any)["scene.missing"].exists
        try out.map { try XCUIScreen.main.screenshot().pngRepresentation.write(to: $0.appendingPathComponent("ready.png")) }
        let start = Date().timeIntervalSince1970
        let player = StepPlayer(app: app)
        for step in missing ? [] : steps {
            try player.play(step)
        }
        let done = Date().timeIntervalSince1970
        Thread.sleep(forTimeInterval: settle)
        if let out {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: out.appendingPathComponent("settled.png"))
            let timing: [String: Any] = ["start": start, "done": done, "missing": missing]
            try JSONSerialization.data(withJSONObject: timing).write(to: out.appendingPathComponent("timing.json"))
        }
    }

    private func dismissSystemPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2) else { return }
            let choice = ["Don’t Allow", "Don't Allow", "Not Now"].lazy.map { alert.buttons[$0] }.first { $0.exists }
            guard let choice else { return }
            choice.tap()
        }
    }
}
