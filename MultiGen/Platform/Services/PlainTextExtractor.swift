import Foundation

enum PlainTextExtractor {
    static func extractText(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        guard ext == "txt" else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
