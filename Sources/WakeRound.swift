import Foundation
import CoreGraphics

/// A single round, driven by monotonic timestamps and cursor positions in screen coordinates.
final class WakeRound {
    enum Outcome { case timeUp, returned, interrupted }

    static let diameter: CGFloat = 52
    private static let duration: TimeInterval = 30
    static let catchesPerLevel = 6
    private static let dwellTimes = [1.5, 1.1, 0.8, 0.6, 0.45]
    let started: TimeInterval
    private(set) var center: CGPoint
    private(set) var catches = 0
    var level: Int { min(1 + catches / Self.catchesPerLevel, Self.dwellTimes.count) }
    private(set) var outcome: Outcome?
    private(set) var nextJump: TimeInterval
    let playArea: CGRect
    private let clockFrame: CGRect
    private let timer: StudyTimer
    private let wasRunning: Bool
    private var lastPointer: CGPoint

    init?(timer: StudyTimer, now: TimeInterval, screen: CGRect, clock: CGRect, pointer: CGPoint) {
        let inset = Self.diameter / 2 + 8
        guard screen.width > 2 * inset, screen.height > 2 * inset else { return nil }
        playArea = screen.insetBy(dx: inset, dy: inset)
        clockFrame = clock
        guard let first = Self.position(in: playArea, clock: clock, pointer: pointer, previous: nil) else { return nil }
        center = first
        self.timer = timer
        wasRunning = timer.phase == .running
        started = now
        nextJump = now + Self.dwellTimes[0]
        lastPointer = pointer
        timer.pause()
    }

    func remaining(at now: TimeInterval) -> Int {
        max(0, Int(ceil(started + Self.duration - now)))
    }

    func advance(to now: TimeInterval, pointer: CGPoint) {
        guard outcome == nil else { return }
        if now >= started + Self.duration { end(.timeUp, at: now); return }

        // Test against the displayed target before moving it. A jump itself cannot score.
        let caught = Self.crossedTarget(from: lastPointer, to: pointer, center: center)
        lastPointer = pointer
        if caught { catches += 1 }
        guard caught || now >= nextJump else { return }
        guard let next = Self.position(in: playArea, clock: clockFrame, pointer: pointer, previous: center) else {
            end(.interrupted, at: now)
            return
        }
        center = next
        nextJump = now + Self.dwellTimes[level - 1]
    }

    func end(_ reason: Outcome, at now: TimeInterval) {
        guard outcome == nil else { return }
        outcome = now >= started + Self.duration ? .timeUp : reason
        if outcome == .returned, wasRunning, timer.phase == .paused {
            timer.toggle()
        }
    }

    private static func crossedTarget(from a: CGPoint, to b: CGPoint, center: CGPoint) -> Bool {
        guard a != b else { return false }
        let dx = b.x - a.x, dy = b.y - a.y
        let radius = diameter / 2
        // A fast pass between two samples also counts as touching the disc.
        let t = min(1, max(0, ((center.x - a.x) * dx + (center.y - a.y) * dy) / (dx * dx + dy * dy)))
        return hypot(a.x + t * dx - center.x, a.y + t * dy - center.y) <= radius
    }

    private static func position(in area: CGRect, clock: CGRect, pointer: CGPoint, previous: CGPoint?) -> CGPoint? {
        let clearance = diameter / 2 + 8
        let excluded = clock.insetBy(dx: -clearance, dy: -clearance)
        func available(_ p: CGPoint) -> Bool {
            guard area.contains(p), !excluded.contains(p),
                  hypot(p.x - pointer.x, p.y - pointer.y) > clearance else { return false }
            return previous.map { hypot(p.x - $0.x, p.y - $0.y) >= diameter * 1.5 } ?? true
        }
        if previous == nil {
            let angle = Double.random(in: 0..<(2 * .pi))
            for radius: CGFloat in [78, 110, 160, 220, 300] {
                for i in 0..<16 {
                    let theta = angle + Double(i) * .pi / 8
                    let p = CGPoint(x: pointer.x + radius * cos(theta), y: pointer.y + radius * sin(theta))
                    if available(p) { return p }
                }
            }
        }
        for _ in 0..<40 {
            let p = CGPoint(x: .random(in: area.minX..<area.maxX), y: .random(in: area.minY..<area.maxY))
            if available(p) { return p }
        }
        // Deterministic fallback on a small or nearly covered display.
        for y in stride(from: area.minY, to: area.maxY, by: clearance) {
            for x in stride(from: area.minX, to: area.maxX, by: clearance) {
                let p = CGPoint(x: x, y: y)
                if available(p) { return p }
            }
        }
        return nil
    }
}
