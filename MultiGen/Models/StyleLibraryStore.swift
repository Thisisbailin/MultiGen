import Foundation
import Combine
import AppKit

struct StyleReference: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var note: String
    var prompt: String
    var imageData: Data?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "未命名风格",
        note: String = "",
        prompt: String = "",
        imageData: Data? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.prompt = prompt
        self.imageData = imageData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@MainActor
final class StyleLibraryStore: ObservableObject {
    @Published private(set) var styles: [StyleReference]
    private let storageURL: URL

    init() {
        storageURL = StyleLibraryStore.makeStorageURL()
        styles = StyleLibraryStore.load(from: storageURL)
    }

    func addStyle(from imageData: Data, title: String = "未命名风格") {
        var item = StyleReference(title: title, imageData: imageData)
        item.updatedAt = .now
        styles.insert(item, at: 0)
        persist()
    }

    func updateStyle(id: UUID, mutate: (inout StyleReference) -> Void) {
        guard let idx = styles.firstIndex(where: { $0.id == id }) else { return }
        mutate(&styles[idx])
        styles[idx].updatedAt = .now
        persist()
    }

    func removeStyle(id: UUID) {
        styles.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(styles)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("StyleLibraryStore persist error: \(error)")
        }
    }

    private static func load(from url: URL) -> [StyleReference] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([StyleReference].self, from: data)) ?? []
    }

    private static func makeStorageURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("MultiGen", isDirectory: true)
            .appendingPathComponent("style-library.json")
    }
}
