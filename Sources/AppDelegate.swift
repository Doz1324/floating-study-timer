import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var timer = StudyTimer()
    private var panel: TimerPanel!
    private var timerView: TimerView!
    private var statusItem: NSStatusItem!
    private var ticker: Timer?
    private var checkpoint: Timer?
    private var round: WakeRound?
    private var targetPanel: TimerPanel?
    private var roundTicker: Timer?
    private let pointerLocation: @MainActor () -> NSPoint
    private var store: StateStore!
    private var persistenceEnabled = true
    private var storageError: String?
    private var locked = false
    private var largeSize = NSSize(width: 240, height: 112)
    private var countdownAnnounced = false
    private var isRestoring = true

    init(pointerLocation: @escaping @MainActor () -> NSPoint = { NSEvent.mouseLocation }) {
        self.pointerLocation = pointerLocation
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--data-file"), args.indices.contains(index + 1) {
            store = StateStore(url: URL(fileURLWithPath: args[index + 1]))
        } else {
            store = StateStore()
        }
        var saved: SavedState?
        do { saved = try store.load() }
        catch {
            persistenceEnabled = false
            storageError = "原记录读取失败，已保留原文件：\(error.localizedDescription)"
        }
        timer = StudyTimer(snapshot: saved?.timer ?? TimerSnapshot())
        locked = saved?.locked ?? false
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var frame = NSRect(x: screen.maxX - 264, y: screen.maxY - 136, width: 240, height: 112)
        if let placement = saved?.window,
           [placement.x, placement.y, placement.width, placement.height].allSatisfy(\.isFinite) {
            frame = NSRect(x: placement.x, y: placement.y,
                           width: min(480, max(144, placement.width)), height: min(240, max(56, placement.height)))
        }
        panel = TimerPanel(frame: visibleFrame(frame))
        panel.onSpace = { [weak self] in self?.toggleTimer() }
        panel.delegate = self
        timerView = TimerView(target: self, play: #selector(toggleTimer), stop: #selector(stopTimer),
                              reset: #selector(resetTimer), size: #selector(toggleSize),
                              wake: #selector(startWake), returnToStudy: #selector(returnToStudy))
        timerView.locked = locked
        timerView.buttons[3].isEnabled = !locked
        timerView.makeMenu = { [weak self] in self?.makeMenu() ?? NSMenu() }
        timerView.toggleSize = { [weak self] in self?.toggleSize() }
        panel.contentView = timerView
        if frame.height >= 88 { largeSize = frame.size }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "stopwatch", accessibilityDescription: "悬浮计时")
        statusItem.button?.toolTip = "悬浮计时 · 点击设置或退出"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        ticker = Timer(timeInterval: 0.2, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.main.add(ticker!, forMode: .common)
        checkpoint = Timer(timeInterval: 5, target: self, selector: #selector(save), userInfo: nil, repeats: true)
        RunLoop.main.add(checkpoint!, forMode: .common)
        isRestoring = false
        refresh()
        panel.orderFrontRegardless()
        save()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showTimer()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        interruptWake()
        timer.pause()
        save()
    }

    @objc private func refresh() {
        guard round == nil else { return }
        timerView?.refresh(timer: timer)
        if timer.mode == .countdown && timer.phase == .running && timer.elapsed >= timer.plannedSeconds {
            if !countdownAnnounced {
                // A visual state change is enough; no disruptive alert or automatic stop.
                countdownAnnounced = true
                NSAccessibility.post(element: timerView.timeLabel, notification: .announcementRequested,
                    userInfo: [.announcement: "计划时间已到，继续记录实际学习时长", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
        } else { countdownAnnounced = false }
    }

    @objc private func startWake() {
        guard round == nil, let screen = panel.screen else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard let game = WakeRound(timer: timer, now: now, screen: screen.visibleFrame,
                                   clock: panel.frame, pointer: pointerLocation()) else { return }
        round = game
        let size = WakeRound.diameter
        let frame = NSRect(x: game.center.x - size / 2, y: game.center.y - size / 2, width: size, height: size)
        let target = TimerPanel(frame: frame)
        target.title = "清醒秒表"
        target.ignoresMouseEvents = true
        target.contentView = WakeTargetView(frame: NSRect(origin: .zero, size: frame.size))
        targetPanel = target
        target.orderFrontRegardless()
        timerView.showRound(level: game.level, catches: game.catches, seconds: game.remaining(at: now))
        save()
        let pulse = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(advanceWake), userInfo: nil, repeats: true)
        roundTicker = pulse
        RunLoop.main.add(pulse, forMode: .common)
    }

    @objc private func advanceWake() {
        guard let round, let targetPanel else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let old = round.center
        round.advance(to: now, pointer: pointerLocation())
        if round.outcome != nil {
            closeWake()
            return
        }
        if old != round.center {
            let radius = WakeRound.diameter / 2
            targetPanel.setFrameOrigin(NSPoint(x: round.center.x - radius, y: round.center.y - radius))
        }
        timerView.showRound(level: round.level, catches: round.catches, seconds: round.remaining(at: now))
    }

    @objc private func returnToStudy() { endWake(.returned) }
    private func interruptWake() { endWake(.interrupted) }

    private func endWake(_ reason: WakeRound.Outcome) {
        guard let round else { return }
        round.end(reason, at: ProcessInfo.processInfo.systemUptime)
        closeWake()
    }

    private func closeWake() {
        roundTicker?.invalidate()
        roundTicker = nil
        targetPanel?.close()
        targetPanel = nil
        round = nil
        changed()
    }

    @objc private func toggleTimer() {
        guard round == nil else { return }
        timer.toggle()
        changed()
    }
    @objc private func stopTimer() { timer.finish(); changed() }
    @objc private func resetTimer() { timer.reset(); changed() }
    @objc private func undoReset() { timer.undoReset(); changed() }
    @objc private func useStopwatch() { timer.setMode(.stopwatch); changed() }
    @objc private func useCountdown() { timer.setMode(.countdown); changed() }
    private func changed() { refresh(); save() }

    @objc private func toggleSize() {
        guard !locked else { return }
        let old = panel.frame
        let size: NSSize
        if timerView.isCompact { size = largeSize }
        else { largeSize = old.size; size = NSSize(width: 172, height: 64) }
        // Keep the top-left corner fixed when changing between compact and expanded.
        let frame = NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height)
        panel.setFrame(visibleFrame(frame), display: true)
        save()
    }

    @objc private func toggleLock() {
        locked.toggle()
        timerView.locked = locked
        timerView.buttons[3].isEnabled = !locked
        save()
    }

    @objc private func showTimer() {
        panel.setFrame(visibleFrame(panel.frame), display: true)
        panel.orderFrontRegardless()
    }

    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func willSleep() { interruptWake(); timer.pause(); changed() }
    @objc private func activeSpaceChanged() {
        panel.orderFrontRegardless()
        targetPanel?.orderFrontRegardless()
    }
    @objc private func screensChanged() {
        guard panel != nil else { return }
        let next = visibleFrame(panel.frame)
        if let round, next != panel.frame || panel.screen?.frame.contains(round.playArea) != true {
            interruptWake()
        }
        if next != panel.frame { panel.setFrame(next, display: true) }
    }

    func windowDidMove(_ notification: Notification) { save() }
    func windowDidResize(_ notification: Notification) { save() }

    @objc private func save() {
        guard !isRestoring, panel != nil, persistenceEnabled else { return }
        let frame = panel.frame
        let state = SavedState(timer: timer.snapshot(), window: WindowPlacement(x: frame.minX, y: frame.minY,
            width: frame.width, height: frame.height), locked: locked)
        do { try store.save(state); storageError = nil }
        catch { storageError = "暂时无法保存：\(error.localizedDescription)" }
        if storageError != nil { statusItem.button?.toolTip = storageError }
    }

    private func visibleFrame(_ proposed: NSRect) -> NSRect {
        let screens = NSScreen.screens.map(\.visibleFrame)
        if screens.contains(where: { $0.contains(proposed) }) { return proposed }
        let target = screens.max(by: { a, b in
            let ia = a.intersection(proposed), ib = b.intersection(proposed)
            return (ia.isNull ? 0 : ia.width * ia.height) < (ib.isNull ? 0 : ib.width * ib.height)
        }) ?? NSScreen.main?.visibleFrame ?? proposed
        var frame = proposed
        frame.origin.x = max(target.minX, min(frame.minX, target.maxX - frame.width))
        frame.origin.y = max(target.minY, min(frame.minY, target.maxY - frame.height))
        return frame
    }

    func menuNeedsUpdate(_ menu: NSMenu) { populate(menu) }
    private func makeMenu() -> NSMenu { let menu = NSMenu(); populate(menu); return menu }

    @discardableResult
    private func item(_ menu: NSMenu, _ title: String, _ action: Selector?, enabled: Bool = true) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: "")
        result.target = self
        result.isEnabled = enabled
        menu.addItem(result)
        return result
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        if round != nil {
            item(menu, "回到学习", #selector(returnToStudy))
            item(menu, "退出悬浮计时", #selector(quit))
            return
        }
        item(menu, "实际学习  \(StudyTimer.format(seconds: timer.elapsed))", nil, enabled: false)
        item(menu, timer.phase == .running ? "暂停" : timer.phase == .paused ? "继续" : timer.phase == .finished ? "开始下一项" : "开始", #selector(toggleTimer))
        item(menu, "结束并记录", #selector(stopTimer), enabled: timer.phase == .running || timer.phase == .paused)
        item(menu, "复位", #selector(resetTimer), enabled: timer.phase != .ready)
        if timer.canUndoReset { item(menu, "撤销复位", #selector(undoReset)) }
        item(menu, "复制实际时长", #selector(copyCurrent))
        item(menu, "清醒", #selector(startWake))
        menu.addItem(.separator())
        item(menu, "正计时", #selector(useStopwatch)).state = timer.mode == .stopwatch ? .on : .off
        item(menu, "倒计时", #selector(useCountdown)).state = timer.mode == .countdown ? .on : .off
        item(menu, "计划时长：\(Int(timer.plannedSeconds / 60)) 分钟…", #selector(setDuration))
        menu.addItem(.separator())
        item(menu, timerView.isCompact ? "展开" : "迷你模式", #selector(toggleSize), enabled: !locked)
        item(menu, "锁定位置和大小", #selector(toggleLock)).state = locked ? .on : .off
        item(menu, "找回悬浮窗", #selector(showTimer))

        let recordsItem = item(menu, "最近记录", nil)
        let recordsMenu = NSMenu()
        recordsMenu.autoenablesItems = false
        if timer.records.isEmpty { item(recordsMenu, "结束一项计时后保存在这里", nil, enabled: false) }
        for record in timer.records.suffix(10).reversed() {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd HH:mm"
            let entry = item(recordsMenu, "\(formatter.string(from: record.endedAt))  ·  \(StudyTimer.format(seconds: record.seconds))", #selector(copyRecord(_:)))
            entry.representedObject = record.id.uuidString
            entry.toolTip = "点击复制实际学习时长"
        }
        if !timer.records.isEmpty {
            recordsMenu.addItem(.separator())
            item(recordsMenu, "复制全部记录", #selector(copyAllRecords))
        }
        recordsItem.submenu = recordsMenu
        if let storageError {
            menu.addItem(.separator())
            item(menu, storageError, nil, enabled: false)
        }
        menu.addItem(.separator())
        item(menu, "退出悬浮计时", #selector(quit))
    }

    @objc private func setDuration() {
        let previousApp = NSWorkspace.shared.frontmostApplication
        defer {
            if previousApp?.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp?.activate(options: [])
            }
        }
        let alert = NSAlert()
        alert.messageText = "计划学习多少分钟？"
        alert.informativeText = "输入 1–1440 的整数。修改后切换到倒计时，已学时长会保留。"
        let input = NSTextField(string: String(Int(timer.plannedSeconds / 60)))
        input.frame = NSRect(x: 0, y: 0, width: 240, height: 26)
        input.alignment = .center
        input.setAccessibilityLabel("计划分钟数")
        alert.accessoryView = input
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        alert.window.level = .statusBar
        alert.window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
        alert.window.initialFirstResponder = input
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let minutes = Int(text), (1...1440).contains(minutes) else {
                alert.informativeText = "请输入 1–1440 的整数，例如 45。"
                continue
            }
            timer.setPlan(minutes: Double(minutes))
            timer.setMode(.countdown)
            changed()
            break
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func copyCurrent() { copy(durationText(timer.elapsed)) }
    @objc private func copyRecord(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let record = timer.records.first(where: { $0.id.uuidString == id }) else { return }
        copy(durationText(record.seconds))
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        "\(StudyTimer.format(seconds: seconds))（\(String(format: "%.2f", seconds / 60)) 分钟）"
    }

    @objc private func copyAllRecords() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let rows = timer.records.map { record in
            "\(formatter.string(from: record.startedAt))\t\(formatter.string(from: record.endedAt))\t\(String(format: "%.2f", record.seconds / 60))\t\(StudyTimer.format(seconds: record.seconds))"
        }
        copy((["开始时间\t结束时间\t实际分钟\t实际时长"] + rows).joined(separator: "\n"))
    }
}
