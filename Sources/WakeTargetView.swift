import AppKit

final class WakeTargetView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = WakeRound.diameter / 2
        layer?.backgroundColor = NSColor(srgbRed: 0.74, green: 0.89, blue: 0.82, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 0.12, alpha: 0.65).cgColor
        let icon = NSImageView(frame: bounds.insetBy(dx: 11, dy: 11))
        icon.image = NSImage(systemSymbolName: "stopwatch", accessibilityDescription: "清醒秒表")
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = NSColor(white: 0.1, alpha: 1)
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
