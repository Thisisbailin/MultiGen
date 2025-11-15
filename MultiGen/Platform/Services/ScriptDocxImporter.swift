import Foundation

struct ScriptDocxImportItem {
    let episodeNumber: Int
    let title: String
    let body: String
}

struct ScriptDocxImporter {
    private let episodePattern = #"第\s*([0-9０-９一二三四五六七八九十百千]+)\s*集"#

    func parseDocument(at url: URL) throws -> [ScriptDocxImportItem] {
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            throw ImportError.readFailed
        }

        guard let text = DocxTextExtractor.extractText(from: data) else {
            throw ImportError.unsupportedFormat
        }

        return parseEpisodes(from: text)
    }

    private func parseEpisodes(from text: String) -> [ScriptDocxImportItem] {
        let regex = try? NSRegularExpression(pattern: episodePattern, options: [])
        guard let regex else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        var items: [ScriptDocxImportItem] = []
        for (index, match) in matches.enumerated() {
            guard match.numberOfRanges >= 2 else { continue }
            let numberRange = match.range(at: 1)
            let numberString = nsText.substring(with: numberRange)
            let episodeNumber = parseEpisodeNumber(from: numberString)
            let contentStart = match.range.location + match.range.length
            let contentEnd = (index + 1 < matches.count) ? matches[index + 1].range.location : nsText.length
            let bodyRange = NSRange(location: contentStart, length: max(contentEnd - contentStart, 0))
            let body = nsText.substring(with: bodyRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = "第\(episodeNumber)集"
            items.append(ScriptDocxImportItem(episodeNumber: episodeNumber, title: title, body: body))
        }
        return items
    }

    private func parseEpisodeNumber(from string: String) -> Int {
        let digits = string.trimmingCharacters(in: .whitespaces)
        if let arabic = Int(digits) {
            return arabic
        }
        let mapper: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
            "六": 6, "七": 7, "八": 8, "九": 9, "十": 10, "百": 100, "千": 1000
        ]
        var total = 0
        var current = 0
        for char in digits {
            if let value = mapper[char] {
                if value >= 10 {
                    if current == 0 { current = 1 }
                    current *= value
                    total += current
                    current = 0
                } else {
                    current = current * 10 + value
                }
            }
        }
        total += current
        return max(total, 1)
    }

    enum ImportError: LocalizedError {
        case accessDenied
        case readFailed
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "无法访问选中的文件。"
            case .readFailed:
                return "读取文件失败，请重试。"
            case .unsupportedFormat:
                return "暂不支持该 Word 文件结构，请使用常规 docx 格式。"
            }
        }
    }
}

private enum DocxTextExtractor {
    static func extractText(from data: Data) -> String? {
        guard let archive = try? DocxArchive(data: data) else { return nil }
        return archive.extractDocumentText()
    }
}

private final class DocxArchive {
    private let tempDirectory: URL

    init(data: Data) throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let docxURL = tempDirectory.appendingPathComponent("document.docx")
        try data.write(to: docxURL)
        try Self.unzip(docxURL, to: tempDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func extractDocumentText() -> String? {
        let documentXML = tempDirectory.appendingPathComponent("word/document.xml")
        guard let xmlData = try? Data(contentsOf: documentXML) else { return nil }
        guard let xml = String(data: xmlData, encoding: .utf8) else { return nil }
        return Self.strip(xml: xml)
    }

    private static func unzip(_ url: URL, to destination: URL) throws {
        let process = Process()
        process.launchPath = "/usr/bin/unzip"
        process.arguments = ["-qq", url.path, "-d", destination.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw ScriptDocxImporter.ImportError.unsupportedFormat
        }
    }

    private static func strip(xml: String) -> String {
        var result = xml
        result = result.replacingOccurrences(of: "</w:p>", with: "\n")
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return result
    }
}
