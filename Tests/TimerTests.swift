import Foundation

final class Clock {
    var uptime: TimeInterval = 100
    var wall = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { uptime += seconds; wall += seconds }
    func make(_ snapshot: TimerSnapshot = TimerSnapshot()) -> StudyTimer {
        StudyTimer(snapshot: snapshot, uptime: { self.uptime }, date: { self.wall })
    }
}

struct Failure: Error, CustomStringConvertible { let description: String }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure(description: message) }
}
func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.00001 }

@main
enum TimerTests {
    static func main() throws {
        let cases: [(String, () throws -> Void)] = [
            ("实际时长不依赖界面刷新次数", {
                let c = Clock(), t = Clock()
                let timer = c.make(), other = t.make()
                timer.toggle(); other.toggle()
                c.advance(173.25)
                for _ in 0..<693 { t.advance(0.25); _ = other.display }
                try expect(near(timer.elapsed, 173.25) && near(timer.elapsed, other.elapsed), "计时漂移")
            }),
            ("暂停和继续排除休息时段", {
                let c = Clock(), timer = c.make()
                timer.toggle(); c.advance(61.4); timer.pause(); c.advance(900)
                try expect(timer.display == "01:01", "暂停仍在累计")
                timer.toggle(); c.advance(28.6)
                try expect(near(timer.elapsed, 90), "继续没有累计原时长")
            }),
            ("系统时钟变化不影响实际时长", {
                let c = Clock(), timer = c.make()
                timer.toggle(); c.advance(12); c.wall -= 86_400
                try expect(near(timer.elapsed, 12), "受系统日期影响")
            }),
            ("正倒计时切换保留正在进行的学习", {
                let c = Clock(), timer = c.make()
                timer.toggle(); c.advance(40); timer.setPlan(minutes: 2); timer.setMode(.countdown)
                try expect(timer.display == "01:20" && timer.phase == .running, "切换清空或暂停")
                c.advance(10); timer.setMode(.stopwatch)
                try expect(timer.display == "00:50", "实际时长被倒计时替换")
            }),
            ("倒计时首秒和到零边界", {
                let c = Clock(), timer = c.make()
                timer.setPlan(minutes: 1); timer.setMode(.countdown); timer.toggle()
                c.advance(0.2); try expect(timer.display == "01:00", "首秒过早减少")
                c.advance(59.8); try expect(timer.display == "00:00", "零点显示错误")
                c.advance(1); try expect(timer.display == "+00:01", "超时显示错误")
                try expect(timer.phase == .running, "到零自动停止了实际时长")
            }),
            ("结束记录实际时长而非剩余或超时", {
                let c = Clock(), timer = c.make()
                timer.setPlan(minutes: 1); timer.setMode(.countdown)
                timer.toggle(); c.advance(85); let record = timer.finish()
                c.advance(100)
                try expect(record?.seconds == 85 && record?.plannedSeconds == 60, "记录了错误时长")
                try expect(timer.elapsed == 85 && timer.phase == .finished, "结束后仍计时")
                try expect(timer.finish() == nil && timer.records.count == 1, "重复记录")
            }),
            ("下一项从零重新开始并保留上一项", {
                let c = Clock(), timer = c.make()
                timer.toggle(); c.advance(30); timer.finish(); c.advance(20); timer.toggle(); c.advance(8)
                try expect(timer.elapsed == 8 && timer.records.first?.seconds == 30, "新旧任务混在一起")
            }),
            ("误复位可撤销且不补算空白时间", {
                let c = Clock(), timer = c.make()
                timer.toggle(); c.advance(70); timer.reset(); c.advance(500)
                try expect(timer.display == "00:00" && timer.canUndoReset, "没有复位或无法撤销")
                timer.undoReset()
                try expect(timer.elapsed == 70 && timer.phase == .paused, "撤销误算休息时间")
                timer.toggle(); c.advance(10)
                try expect(timer.elapsed == 80, "撤销后不能继续")
            }),
            ("恢复运行中的检查点时保持暂停", {
                let c = Clock(), timer = c.make()
                timer.toggle(); c.advance(70.75)
                let checkpoint = timer.snapshot(); c.advance(86_400)
                let recovered = c.make(checkpoint)
                try expect(recovered.phase == .paused && recovered.elapsed == 70.75, "重开补算离线时间")
            }),
            ("复位不删除已结束记录", {
                let c = Clock(), timer = c.make()
                timer.toggle(); c.advance(20); timer.finish(); timer.reset(); timer.undoReset()
                try expect(timer.records.count == 1 && timer.phase == .finished, "记录丢失")
            }),
            ("显示跨越一小时和一天", {
                try expect(StudyTimer.format(seconds: 3599) == "59:59", "小时边界错误")
                try expect(StudyTimer.format(seconds: 3600) == "01:00:00", "小时不显示")
                try expect(StudyTimer.format(seconds: 90061) == "25:01:01", "一天后归零")
            }),
            ("计划时长拒绝非法输入", {
                let timer = StudyTimer()
                timer.setPlan(minutes: 0); timer.setPlan(minutes: .infinity); timer.setPlan(minutes: 1441)
                try expect(timer.plannedSeconds == 1500, "接受非法时长")
                timer.setPlan(minutes: 1440)
                try expect(timer.plannedSeconds == 86400, "拒绝有效时长")
            }),
            ("保存恢复时长、记录和窗口位置", {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: directory) }
                let store = StateStore(url: directory.appendingPathComponent("state.json"))
                let c = Clock(), timer = c.make()
                timer.toggle(); c.advance(123.4); timer.finish()
                let frame = WindowPlacement(x: 123, y: 456, width: 172, height: 64)
                try store.save(SavedState(timer: timer.snapshot(), window: frame, locked: true))
                let saved = try store.load()
                try expect(saved?.timer.records == timer.records && saved?.window?.y == 456 && saved?.locked == true, "存储丢失信息")
            }),
            ("损坏的记录必须报告错误", {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: url) }
                try Data("invalid JSON".utf8).write(to: url)
                var failed = false
                do { _ = try StateStore(url: url).load() } catch { failed = true }
                try expect(failed, "损坏记录被悄悄当作空记录")
                let unchanged = try String(contentsOf: url, encoding: .utf8)
                try expect(unchanged == "invalid JSON", "原文件被改写")
            })
        ] + wakeCases
        var failures = 0
        for (name, body) in cases {
            do { try body(); print("PASS  \(name)") }
            catch { failures += 1; print("FAIL  \(name): \(error)") }
        }
        print("\(cases.count - failures)/\(cases.count) passed")
        if failures > 0 { exit(1) }
    }
}
