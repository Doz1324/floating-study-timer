import AppKit

@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出验证窗口", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "全屏覆盖验证"
        window.delegate = self
        window.collectionBehavior = [.fullScreenPrimary]
        window.backgroundColor = NSColor(srgbRed: 0.94, green: 0.95, blue: 0.96, alpha: 1)
        let label = NSTextField(labelWithString: "全屏覆盖验证")
        label.font = .systemFont(ofSize: 38, weight: .medium)
        label.textColor = NSColor(white: 0.25, alpha: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        let detail = NSTextField(labelWithString: "这是独立的测试应用。进入全屏后，观察悬浮计时器是否仍在原位置。")
        detail.font = .systemFont(ofSize: 16)
        detail.textColor = NSColor(white: 0.4, alpha: 1)
        detail.translatesAutoresizingMaskIntoConstraints = false
        let button = NSButton(title: "进入 / 退出全屏", target: self, action: #selector(fullScreen))
        button.translatesAutoresizingMaskIntoConstraints = false
        for view in [label, detail, button] { window.contentView!.addSubview(view) }
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor, constant: -45),
            detail.centerXAnchor.constraint(equalTo: label.centerXAnchor),
            detail.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 20),
            button.centerXAnchor.constraint(equalTo: label.centerXAnchor),
            button.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 24)
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if reportURL != nil { window.toggleFullScreen(nil) }
    }
    private var reportURL: URL? {
        let args = CommandLine.arguments
        guard args.count == 3, args[1] == "--report-fullscreen" else { return nil }
        return URL(fileURLWithPath: args[2])
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        if let reportURL { try? String(window.windowNumber).write(to: reportURL, atomically: true, encoding: .utf8) }
    }
    @objc private func fullScreen() { window.toggleFullScreen(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
enum FullScreenFixture {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = FixtureDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
