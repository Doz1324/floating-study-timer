import AppKit

final class TimerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "悬浮计时"
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary,
                              .stationary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        appearance = NSAppearance(named: .darkAqua)
    }
}

/// Decorative text does not block dragging or the right-click menu.
final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class TimerButton: NSButton {
    private var hovered = false
    private var hoverArea: NSTrackingArea?
    private var symbolKey = ""
    var primary = false

    init(symbol: String, title: String, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        focusRingType = .none
        self.target = target
        self.action = action
        setSymbol(symbol, title: title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setSymbol(_ symbol: String, title: String) {
        let key = symbol + "|" + title
        guard symbolKey != key else { return }
        symbolKey = key
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        toolTip = title
        setAccessibilityLabel(title)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let fill: NSColor
        if primary {
            fill = NSColor(srgbRed: 0.74, green: 0.89, blue: 0.82, alpha: isHighlighted ? 0.65 : 1)
            contentTintColor = NSColor(white: 0.08, alpha: 1)
        } else {
            fill = NSColor(white: 1, alpha: isHighlighted ? 0.2 : hovered ? 0.13 : 0.06)
            contentTintColor = isEnabled ? NSColor(white: 0.86, alpha: 1) : NSColor(white: 0.4, alpha: 1)
        }
        fill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        super.draw(dirtyRect)
    }
}

final class TimerView: NSView {
    let timeLabel = PassthroughLabel(labelWithString: "00:00")
    private(set) var buttons: [TimerButton] = []
    private var tracking: NSTrackingArea?
    private var renderedKey = ""
    private(set) var hovered = false
    var locked = false { didSet { needsDisplay = true } }
    var makeMenu: (() -> NSMenu)?
    var toggleSize: (() -> Void)?
    var isCompact: Bool { bounds.height < 88 }

    init(target: AnyObject, play: Selector, stop: Selector, reset: Selector, size: Selector) {
        super.init(frame: .zero)
        timeLabel.alignment = .center
        timeLabel.maximumNumberOfLines = 1
        timeLabel.lineBreakMode = .byClipping
        timeLabel.setAccessibilityLabel("计时时间")
        addSubview(timeLabel)
        buttons = [
            TimerButton(symbol: "play.fill", title: "开始", target: target, action: play),
            TimerButton(symbol: "stop.fill", title: "结束并记录", target: target, action: stop),
            TimerButton(symbol: "arrow.counterclockwise", title: "复位（可从右键菜单撤销）", target: target, action: reset),
            TimerButton(symbol: "arrow.down.right.and.arrow.up.left", title: "迷你模式", target: target, action: size)
        ]
        buttons[0].primary = true
        buttons.forEach(addSubview)
        setAccessibilityRole(.group)
        setAccessibilityLabel("悬浮计时器；右键设置，拖动移动，右下角缩放")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func refresh(timer: StudyTimer) {
        let key = "\(timer.display)|\(timer.phase.rawValue)|\(timer.mode.rawValue)|\(timer.plannedSeconds)|\(StudyTimer.format(seconds: timer.elapsed))"
        guard renderedKey != key else { return }
        renderedKey = key
        timeLabel.stringValue = timer.display
        timeLabel.textColor = timer.isOvertime ? NSColor(srgbRed: 1, green: 0.72, blue: 0.44, alpha: 1)
            : timer.phase == .paused || timer.phase == .finished ? NSColor(white: 0.68, alpha: 1) : .white
        let status: String
        switch timer.phase {
        case .ready: status = "未开始"
        case .running: status = "计时中"
        case .paused: status = "已暂停"
        case .finished: status = "已结束并记录"
        }
        let mode = timer.mode == .stopwatch ? "正计时" : "倒计时 · \(Int(timer.plannedSeconds / 60)) 分钟"
        toolTip = "\(mode) · \(status)\n实际学习 \(StudyTimer.format(seconds: timer.elapsed))\n右键设置 · 拖动移动 · 右下角缩放"
        timeLabel.setAccessibilityValue("\(mode)，\(status)，\(timer.display)")
        let playTitle = timer.phase == .running ? "暂停" : timer.phase == .paused ? "继续" : timer.phase == .finished ? "开始下一项" : "开始"
        buttons[0].setSymbol(timer.phase == .running ? "pause.fill" : "play.fill", title: playTitle)
        buttons[1].isEnabled = timer.phase == .running || timer.phase == .paused
        buttons[2].isEnabled = timer.phase != .ready
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let compact = isCompact
        let showControls = !compact || hovered
        let gap: CGFloat = compact ? 8 : 12
        let diameter: CGFloat = compact ? 22 : min(34, min(bounds.height * 0.28, (bounds.width - 28 - gap * 3) / 4))
        let groupWidth = diameter * 4 + gap * 3
        let origin = (bounds.width - groupWidth) / 2
        for (i, button) in buttons.enumerated() {
            button.isHidden = !showControls
            button.frame = NSRect(x: origin + CGFloat(i) * (diameter + gap), y: compact ? 4 : 12,
                                  width: diameter, height: diameter)
        }
        buttons[3].setSymbol(compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                             title: compact ? "展开" : "迷你模式")
        let availableHeight = compact ? (showControls ? bounds.height - 26 : bounds.height)
                                     : bounds.height - diameter - 24
        var fontSize = min(compact ? 34 : 72, availableHeight * (compact ? 0.7 : 0.75))
        let availableWidth = bounds.width - 20
        while fontSize > 14 {
            let width = (timeLabel.stringValue as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)]).width
            if width <= availableWidth { break }
            fontSize -= 1
        }
        timeLabel.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let labelHeight = ceil(fontSize * 1.3)
        let lowerEdge: CGFloat = compact ? (showControls ? 26 : 0) : diameter + 22
        timeLabel.frame = NSRect(x: 10, y: lowerEdge + (availableHeight - labelHeight) / 2,
                                 width: availableWidth, height: labelHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: isCompact ? 14 : 18, yRadius: isCompact ? 14 : 18)
        NSColor(srgbRed: 0.105, green: 0.115, blue: 0.125, alpha: 0.97).setFill()
        shape.fill()
        NSColor(white: 1, alpha: 0.11).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        if hovered && !locked {
            NSColor(white: 1, alpha: 0.28).setStroke()
            let grip = NSBezierPath()
            for offset in [CGFloat(0), 4] {
                grip.move(to: NSPoint(x: bounds.width - 15 + offset, y: 7))
                grip.line(to: NSPoint(x: bounds.width - 7, y: 15 - offset))
            }
            grip.lineWidth = 1
            grip.stroke()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        if let window { setHovered(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))) }
    }

    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        needsLayout = true
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func menu(for event: NSEvent) -> NSMenu? { makeMenu?() }

    override func mouseDown(with event: NSEvent) {
        guard let window, !locked else { return }
        let point = convert(event.locationInWindow, from: nil)
        if point.x > bounds.width - 20 && point.y < 20 {
            let start = NSEvent.mouseLocation
            let original = window.frame
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                if next.type == .leftMouseUp { break }
                let current = NSEvent.mouseLocation
                let width = min(480, max(144, original.width + current.x - start.x))
                let height = min(240, max(56, original.height - current.y + start.y))
                window.setFrame(NSRect(x: original.minX, y: original.maxY - height, width: width, height: height), display: true)
            }
        } else if event.clickCount == 2 {
            toggleSize?()
        } else {
            window.performDrag(with: event)
        }
    }
}
