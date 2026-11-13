import Foundation

struct WindowPlacement: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct SavedState: Codable {
    var version: Int = 1
    var timer: TimerSnapshot
    var window: WindowPlacement?
    var locked: Bool = false
}

final class StateStore {
    let url: URL
    private var lastWrittenData: Data?

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FloatingStudyTimer", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    func load() throws -> SavedState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let saved = try JSONDecoder().decode(SavedState.self, from: data)
        guard saved.version == 1 else {
            throw NSError(domain: "FloatingStudyTimer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "记录文件版本较新，暂不覆盖它。"])
        }
        lastWrittenData = data
        return saved
    }

    func save(_ state: SavedState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        guard data != lastWrittenData else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        lastWrittenData = data
    }
}
