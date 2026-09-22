import AppKit
import WebKit

let html = """
<!doctype html><html><body style="background:#123"><script>
window.log = [];
let raf = 0, timer = 0, interval = 0;
function loop() { raf++; requestAnimationFrame(loop); }
requestAnimationFrame(loop);
function tick() { timer++; setTimeout(tick, 100); }
setTimeout(tick, 100);
setInterval(() => { interval++; }, 100);
document.addEventListener("visibilitychange", () => window.log.push({ t: Math.round(performance.now()), event: document.visibilityState }));
setInterval(() => { window.log.push({ t: Math.round(performance.now()), vis: document.visibilityState, raf, timer, interval }); raf = 0; timer = 0; interval = 0; }, 1000);
</script></body></html>
"""

final class Probe: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 400), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        web = WKWebView(frame: window.contentView!.bounds, configuration: WKWebViewConfiguration())
        window.contentView!.addSubview(web)
        web.loadHTMLString(html, baseURL: nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let mode = CommandLine.arguments.dropFirst().first ?? "minimize"
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            print("PHASE hide(\(mode)) at 4s")
            if mode == "minimize" { self.window.miniaturize(nil) }
            else if mode == "apphide" { NSApp.hide(nil) }
            else if mode == "orderout" { self.window.orderOut(nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) {
            print("PHASE show at 16s")
            if mode == "minimize" { self.window.deminiaturize(nil) }
            else if mode == "apphide" { NSApp.unhide(nil) }
            else if mode == "orderout" { self.window.makeKeyAndOrderFront(nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            self.web.evaluateJavaScript("JSON.stringify(window.log)") { result, error in
                print(result as? String ?? "error \(String(describing: error))")
                NSApp.terminate(nil)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Probe()
app.delegate = delegate
app.run()
