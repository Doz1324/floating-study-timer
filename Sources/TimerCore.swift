import Foundation

enum TimerMode: String, Codable { case stopwatch, countdown }
enum TimerPhase: String, Codable { case ready, running, paused, finished }

struct StudyRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let seconds: TimeInterval
    let mode: TimerMode
    let plannedSeconds: TimeInterval?
}

struct TimerSnapshot: Codable {
    var mode: TimerMode = .stopwatch
    var phase: TimerPhase = .ready
    var elapsed: TimeInterval = 0
    var plannedSeconds: TimeInterval = 25 * 60
    var startedAt: Date?
    var records: [StudyRecord] = []
}

/// Uses a monotonic clock, so changing the system date cannot change study time.
/// A restored running timer is paused at its last checkpoint, excluding app downtime.
final class StudyTimer {
    private(set) var mode: TimerMode
    private(set) var phase: TimerPhase
    private(set) var plannedSeconds: TimeInterval
    private(set) var records: [StudyRecord]
    private var accumulated: TimeInterval
    private var anchor: TimeInterval?
    private var startedAt: Date?
    private var undoSnapshot: TimerSnapshot?
    private let uptime: () -> TimeInterval
    private let date: () -> Date

    init(snapshot: TimerSnapshot = TimerSnapshot(),
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         date: @escaping () -> Date = Date.init) {
        self.uptime = uptime
        self.date = date
        mode = snapshot.mode
        phase = snapshot.phase == .running ? .paused : snapshot.phase
        plannedSeconds = Self.validPlan(snapshot.plannedSeconds)
        accumulated = snapshot.elapsed.isFinite ? max(0, snapshot.elapsed) : 0
        startedAt = snapshot.startedAt
        records = snapshot.records
    }

    var elapsed: TimeInterval {
        accumulated + (anchor.map { max(0, uptime() - $0) } ?? 0)
    }

    var isOvertime: Bool { mode == .countdown && elapsed > plannedSeconds }
    var canUndoReset: Bool { undoSnapshot != nil }

    var display: String {
        let actual = elapsed
        if mode == .stopwatch { return Self.format(seconds: actual) }
        let remaining = plannedSeconds - actual
        if remaining < 0 { return "+" + Self.format(seconds: -remaining) }
        return Self.format(seconds: ceil(remaining))
    }

    func toggle() {
        if phase == .running { pause(); return }
        undoSnapshot = nil
        if phase == .finished {
            accumulated = 0
            startedAt = nil
        }
        if startedAt == nil { startedAt = date() }
        anchor = uptime()
        phase = .running
    }

    func pause() {
        guard phase == .running else { return }
        accumulated = elapsed
        anchor = nil
        phase = .paused
    }

    @discardableResult
    func finish() -> StudyRecord? {
        guard phase == .running || phase == .paused else { return nil }
        pause()
        phase = .finished
        undoSnapshot = nil
        guard accumulated > 0, let startedAt else { return nil }
        let record = StudyRecord(id: UUID(), startedAt: startedAt, endedAt: date(),
                                 seconds: accumulated, mode: mode,
                                 plannedSeconds: mode == .countdown ? plannedSeconds : nil)
        records.append(record)
        return record
    }

    func reset() {
        guard phase != .ready || elapsed > 0 else { return }
        undoSnapshot = snapshot()
        anchor = nil
        accumulated = 0
        startedAt = nil
        phase = .ready
    }

    /// Restores as paused; time spent deciding whether to undo is not study time.
    func undoReset() {
        guard let saved = undoSnapshot else { return }
        mode = saved.mode
        plannedSeconds = saved.plannedSeconds
        accumulated = saved.elapsed
        startedAt = saved.startedAt
        phase = saved.phase == .running ? .paused : saved.phase
        anchor = nil
        undoSnapshot = nil
    }

    func setMode(_ mode: TimerMode) { self.mode = mode }

    func setPlan(minutes: Double) {
        guard minutes.isFinite, (1...1440).contains(minutes) else { return }
        plannedSeconds = minutes * 60
    }

    func snapshot() -> TimerSnapshot {
        TimerSnapshot(mode: mode, phase: phase, elapsed: elapsed,
                      plannedSeconds: plannedSeconds, startedAt: startedAt, records: records)
    }

    static func format(seconds: TimeInterval) -> String {
        let whole = Int(min(Double(Int.max / 2), max(0, seconds.isFinite ? seconds : 0)))
        let h = whole / 3600, m = whole / 60 % 60, s = whole % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s)
                     : String(format: "%02d:%02d", m, s)
    }

    private static func validPlan(_ seconds: TimeInterval) -> TimeInterval {
        seconds.isFinite && (60...86400).contains(seconds) ? seconds : 1500
    }
}
