import Foundation

enum PagesTextExtractor {
    static func extractText(from url: URL) -> String? {
        guard url.pathExtension.lowercased() == "pages" else { return nil }
        // 尝试使用 textutil 转换为纯文本
        let process = Process()
        process.launchPath = "/usr/bin/textutil"
        process.arguments = ["-convert", "txt", "-stdout", url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
