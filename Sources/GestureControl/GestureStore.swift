import Foundation

struct GestureStore {
    let url: URL

    init(url: URL? = nil) {
        if let url { self.url = url; return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.url = support.appendingPathComponent("GestureControl/gestures.json")
    }

    func load() throws -> [SavedGesture] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([SavedGesture].self, from: Data(contentsOf: url))
    }

    func save(_ gestures: [SavedGesture]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(gestures).write(to: url, options: .atomic)
    }
}
