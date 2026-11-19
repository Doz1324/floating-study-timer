import AppKit

/// Runs against the real panels, button actions and run loop with an isolated data file.
/// Injects pointer samples in this process only. The user's cursor is never moved.
@main @MainActor
enum WakeWindowTests {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func require(_ test: Bool, _ message: String) throws {
        if !test { throw Failure(description: message) }
    }

    static func sleep(_ milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    static func wait(for seconds: Double, until ready: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !ready() {
            if ProcessInfo.processInfo.systemUptime >= deadline { throw Failure(description: "等待窗口状态超时") }
            try await sleep(40)
        }
    }

    static func main() {
        let args = CommandLine.arguments
        guard args.count == 4, args[1] == "--data-file",
              !FileManager.default.fileExists(atPath: args[2]) else { exit(2) }
        var cursor: NSPoint?
        let app = NSApplication.shared
        let delegate = AppDelegate(pointerLocation: { cursor ?? NSEvent.mouseLocation })
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        Task { @MainActor in
            do {
                try await run(data: URL(fileURLWithPath: args[2]), fixture: args[3]) { cursor = $0 }
                print("PASS 空格开始/暂停/继续、长按、跨应用焦点、清醒模式、五档满 30 秒和主动返回")
                app.terminate(nil)
            } catch {
                print("FAIL \(error)")
                exit(1)
            }
        }
        withExtendedLifetime(delegate) { app.run() }
    }

    static func run(data: URL, fixture: String, setPointer: (NSPoint) -> Void) async throws {
        func clock() -> NSWindow? { NSApp.windows.first { $0.title == "悬浮计时" && $0.isVisible } }
        func target() -> NSWindow? { NSApp.windows.first { $0.title == "清醒秒表" && $0.isVisible } }
        func snapshot() throws -> TimerSnapshot {
            guard let state = try StateStore(url: data).load() else { throw Failure(description: "缺少状态文件") }
            return state.timer
        }
        try await wait(for: 5) { clock() != nil }
        guard let panel = clock(), let view = panel.contentView as? TimerView else {
            throw Failure(description: "缺少悬浮钟")
        }
        // These tests use performClick. Desktop clicks must not change a test round.
        panel.ignoresMouseEvents = true
        view.layoutSubtreeIfNeeded()
        let wake = view.buttons[4]
        try require(!wake.isHidden, "展开模式缺少入口")
        func pressSpace(repeating: Bool = false) {
            for type: NSEvent.EventType in [.keyDown, .keyUp] {
                let key = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                    context: nil, characters: " ", charactersIgnoringModifiers: " ",
                    isARepeat: repeating && type == .keyDown, keyCode: 49)!
                panel.sendEvent(key)
            }
        }
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: view.bounds.midX, y: view.bounds.midY),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        view.locked = true
        panel.sendEvent(click)
        try require(panel.isKeyWindow, "点击时间后无法接收空格")
        view.locked = false
        pressSpace()
        try require(try snapshot().phase == .running, "空格未开始计时")
        pressSpace(repeating: true)
        try require(try snapshot().phase == .running, "长按空格重复切换")
        pressSpace()
        try require(try snapshot().phase == .paused, "空格未暂停")
        pressSpace()
        try require(try snapshot().phase == .running, "空格未继续")
        view.buttons[3].performClick(nil)
        let home = panel.frame
        let event = NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
            trackingNumber: 0, userData: nil)!
        view.mouseExited(with: event)
        view.layoutSubtreeIfNeeded()
        try require(view.isCompact && wake.isHidden, "迷你模式按钮未收起")
        view.mouseEntered(with: event)
        view.layoutSubtreeIfNeeded()
        try require(!wake.isHidden && view.bounds.contains(wake.frame), "悬停入口丢失")
        let host = Process()
        host.executableURL = URL(fileURLWithPath: fixture)
        let report = data.deletingLastPathComponent().appendingPathComponent("fullscreen-id")
        host.arguments = ["--report-fullscreen", report.path]
        try host.run()
        defer { if host.isRunning { host.terminate() } }
        try await wait(for: 8) { FileManager.default.fileExists(atPath: report.path) }
        try require(!panel.isKeyWindow, "切到全屏应用后悬浮钟仍持有键盘焦点")
        let id = try String(contentsOf: report, encoding: .utf8)
        guard let fixtureID = Int(id) else { throw Failure(description: "缺少全屏窗口编号") }
        let origin = NSPoint(x: home.midX, y: home.midY)
        setPointer(origin)
        // Exercise the normal application action even when the real pointer is outside the mini clock.
        view.mouseEntered(with: event)
        view.layoutSubtreeIfNeeded()
        let start = ProcessInfo.processInfo.systemUptime
        wake.performClick(nil)
        try await wait(for: 1) { target() != nil }
        guard let disc = target() else { throw Failure(description: "缺少跳动目标") }
        let saved = try snapshot()
        try require(saved.phase == .paused && disc.ignoresMouseEvents, "没有暂停或目标拦截鼠标")
        panel.makeKey()
        pressSpace()
        try require(try snapshot().phase == .paused && target() != nil, "清醒模式下空格误启动学习计时")
        let ids = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                   as? [[String: Any]])?.compactMap { $0[kCGWindowNumber as String] as? Int } ?? []
        guard let hostOrder = ids.firstIndex(of: fixtureID), let clockOrder = ids.firstIndex(of: panel.windowNumber),
              let discOrder = ids.firstIndex(of: disc.windowNumber) else { throw Failure(description: "三个窗口未同时出现在当前桌面") }
        try require(clockOrder < hostOrder && discOrder < hostOrder, "小秒表或主窗口被全屏应用覆盖")
        try await sleep(1800)
        try require(view.timeLabel.stringValue.hasPrefix("1档 · 0次") && target() != nil, "静止指针误抓")
        if host.isRunning { host.terminate() }
        var sawTopLevel = false
        while target() != nil && ProcessInfo.processInfo.systemUptime - start < 33 {
            setPointer(NSPoint(x: disc.frame.midX, y: disc.frame.midY))
            try await sleep(230)
            sawTopLevel = sawTopLevel || view.timeLabel.stringValue.hasPrefix("5档")
            try require(panel.frame == home, "挑战改变了主窗口位置")
        }
        let after = try snapshot()
        try require(sawTopLevel && target() == nil && ProcessInfo.processInfo.systemUptime - start >= 30,
                    "未显示第五档或未玩满三十秒")
        try require(after.phase == .paused && after.elapsed == saved.elapsed, "到时自动续计或多计了学习时间")
        view.mouseEntered(with: event)
        view.layoutSubtreeIfNeeded()
        view.buttons[0].performClick(nil)
        try require(try snapshot().phase == .running, "到时后手动继续失败")
        view.mouseEntered(with: event); view.layoutSubtreeIfNeeded()
        wake.performClick(nil)
        view.layoutSubtreeIfNeeded()
        guard let back = view.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.title == "回到学习" && !$0.isHidden }) else {
            throw Failure(description: "缺少回到学习按钮")
        }
        back.performClick(nil)
        try require(try snapshot().phase == .running && target() == nil, "主动返回未续计")
    }
}
