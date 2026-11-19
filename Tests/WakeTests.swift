import Foundation
import CoreGraphics

private let screen = CGRect(x: -1440, y: 80, width: 1440, height: 850)
private let panel = CGRect(x: -256, y: 793, width: 240, height: 112)
private let pointer = CGPoint(x: -75, y: 818)

private func makeRound(_ timer: StudyTimer, _ now: Double) throws -> WakeRound {
    guard let game = WakeRound(timer: timer, now: now, screen: screen, clock: panel, pointer: pointer) else {
        throw Failure(description: "没有生成小秒表")
    }
    return game
}

let wakeCases: [(String, () throws -> Void)] = [
    ("静止不会命中，随机落点避开鼠标、边缘和原时钟", {
        for _ in 0..<80 {
            let g = try makeRound(StudyTimer(), 0)
            try expect(hypot(g.center.x - pointer.x, g.center.y - pointer.y) <= 115, "首次出现过远")
            for time in [0.0, 1.8, 3.6, 5.5, 8.0, 12.0, 18.0, 29.999] {
                g.advance(to: time, pointer: pointer)
                let r = WakeRound.diameter / 2
                let target = CGRect(x: g.center.x-r, y: g.center.y-r, width: r*2, height: r*2)
                try expect(screen.contains(target) && !target.intersects(panel) && !target.contains(pointer), "落点无效")
            }
            try expect(g.catches == 0 && g.level == 1 && g.outcome == nil, "静止指针得分")
            g.advance(to: 30, pointer: pointer)
            try expect(g.outcome == .timeUp, "超时未收起")
        }
    }),
    ("每六次升一档，漏抓不升档，最高档继续换位置", {
        let game = try makeRound(StudyTimer(), 0)
        let first = game.center
        game.advance(to: 1.499, pointer: pointer)
        try expect(game.center == first && game.level == 1, "第一档提前跳转")
        game.advance(to: 1.5, pointer: pointer)
        try expect(game.center != first && near(game.nextJump, 3.0), "漏抓时速度改变")
        let stages = [(1...5, 1, 1.5), (6...11, 2, 1.1), (12...17, 3, 0.8),
                      (18...23, 4, 0.6), (24...28, 5, 0.45)]
        var now = 1.5
        for (hits, level, dwell) in stages {
            for count in hits {
                now += 0.1
                let target = game.center
                game.advance(to: now, pointer: target)
                try expect(game.catches == count && game.level == level && game.center != target, "升档边界或命中换位错误")
                try expect(near(game.nextJump, now + dwell), "新档速度未立即生效")
                let pending = game.center
                if count != hits.lowerBound { continue }
                now = game.nextJump
                game.advance(to: now, pointer: target)
                try expect(game.center != pending && game.catches == count && game.level == level, "漏抓改变了命中进度")
                try expect(near(game.nextJump, now + dwell), "漏抓改变了档位速度")
            }
        }
    }),
    ("命中再多也玩到三十秒，到时保持暂停并扣除整局", {
        for mode: TimerMode in [.stopwatch, .countdown] {
            let c = Clock(), t = c.make()
            t.setMode(mode); t.toggle(); c.advance(12)
            let game = try makeRound(t, c.uptime), start = c.uptime, display = t.display
            try expect(game.remaining(at: start) == 30, "初始倒计时错误")
            for offset in (1...29).map(Double.init) + [29.999] {
                c.advance(start + offset - c.uptime)
                game.advance(to: c.uptime, pointer: game.center)
                try expect(game.outcome == nil && t.phase == .paused && t.display == display, "提前结束或误计学习时长")
            }
            try expect(game.level == 5 && game.catches == 30 && game.remaining(at: c.uptime) == 1, "最高档或末秒状态错误")
            c.advance(start + 30 - c.uptime)
            game.advance(to: c.uptime, pointer: game.center)
            try expect(game.outcome == .timeUp && game.catches == 30 && game.remaining(at: c.uptime) == 0, "截止瞬间多算命中")
            c.advance(8)
            try expect(t.phase == .paused && t.elapsed == 12 && t.records.isEmpty, "时间到后自动继续或拆分任务")
            t.toggle(); c.advance(3)
            try expect(t.finish()?.seconds == 15 && t.records.count == 1, "学习记录包含了挑战时长")
        }
    }),
    ("截止前手动退出可恢复，到点或迟到的退出一律保持暂停", {
        for time in [29.999, 30, 35] {
            let c = Clock(), t = c.make()
            t.toggle(); c.advance(8)
            let game = try makeRound(t, 0)
            c.advance(time)
            game.end(.returned, at: time)
            let early = time < 30
            try expect(game.outcome == (early ? .returned : .timeUp) && t.phase == (early ? .running : .paused), "返回边界错误")
            game.end(.returned, at: time + 1)
            try expect(near(t.elapsed, 8), "重复结束误算时间")
        }
    }),
    ("主动返回只继续原来运行的任务，中断或重开保持暂停", {
        for phase: TimerPhase in [.ready, .paused, .finished, .running] {
            let c = Clock(), t = c.make()
            if phase != .ready { t.toggle(); c.advance(20) }
            if phase == .paused { t.pause() }
            if phase == .finished { t.finish() }
            let old = t.elapsed, records = t.records
            let game = try makeRound(t, 0)
            c.advance(5); game.end(.returned, at: 5)
            try expect(t.phase == phase && t.elapsed == old && t.records == records, "恢复或历史记录有误")
        }
        let c = Clock(), t = c.make()
        t.toggle(); c.advance(30)
        let game = try makeRound(t, 0)
        try expect(c.make(t.snapshot()).phase == .paused, "重开后未暂停")
        game.end(.interrupted, at: 5); c.advance(100)
        try expect(t.phase == .paused && t.elapsed == 30, "睡眠中断后误续计")
    }),
    ("快速划过目标也命中，无空间时保留原计时", {
        let t = StudyTimer()
        t.toggle()
        let invalid = WakeRound(timer: t, now: 0, screen: panel, clock: panel, pointer: pointer)
        try expect(invalid == nil && t.phase == .running, "无法启动却扣除了学习时间")
        let g = try makeRound(t, 0), target = g.center
        let beyond = CGPoint(x: 2 * target.x - pointer.x, y: 2 * target.y - pointer.y)
        g.advance(to: 0.2, pointer: beyond)
        try expect(g.catches == 1, "快速划过漏抓")
    })
]
