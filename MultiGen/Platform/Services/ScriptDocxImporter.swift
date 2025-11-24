import Foundation
import AppKit

struct ScriptDocxImportItem {
    let episodeNumber: Int
    let title: String
    let body: String
    let scenes: [SceneImportItem]
}

struct SceneImportItem {
    let index: Int
    let title: String
    let body: String
    let locationHint: String
    let timeHint: String
}

struct ScriptImportPayload {
    let synopsis: String
    let characters: [ProjectCharacterProfile]
    let outlines: [EpisodeOutline]
    let episodes: [ScriptDocxImportItem]
}

struct ScriptDocxImporter {
    private let episodePatterns = [
        #"(?m)^\s*第\s*([0-9０-９〇零一二三四五六七八九十百千万亿兆拾佰仟]+)\s*集[：:\\s·、，,]*"#,
        #"(?m)^\s*第\s*([一二三四五六七八九十百千万亿兆〇零0-9]+)\s*集"#,
        #"第\s*([0-9０-９〇零一二三四五六七八九十百千万亿兆拾佰仟]+)\s*集"# // 无行首锚点兜底
    ]
    private let sectionPattern = #"【([^】]+)】"#

    func parseDocument(at url: URL) throws -> ScriptImportPayload {
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let raw = DocxTextExtractor.extractText(from: url) ?? PagesTextExtractor.extractText(from: url) else {
            throw ImportError.unsupportedFormat
        }
        let text = normalize(raw)

        let sections = extractSections(from: text)

        let synopsis = sections["简介及全文大纲"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mainCharacters = sections["主要人物"] ?? ""
        let supporting = sections["相关配角"] ?? ""
        let characters = parseCharacters(from: mainCharacters + "\n" + supporting)
        let outlines = parseOutlines(from: sections["分集大纲"] ?? "")

        let episodesText = extractEpisodesText(from: text)
        let episodes = parseEpisodes(from: episodesText)

        return ScriptImportPayload(
            synopsis: synopsis,
            characters: characters,
            outlines: outlines,
            episodes: episodes
        )
    }

    private func extractSections(from text: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: sectionPattern, options: []) else { return [:] }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        var sections: [String: String] = [:]
        for (idx, match) in matches.enumerated() {
            guard match.numberOfRanges >= 2 else { continue }
            let name = ns.substring(with: match.range(at: 1))
            let start = match.range.location + match.range.length
            let end = (idx + 1 < matches.count) ? matches[idx + 1].range.location : ns.length
            let range = NSRange(location: start, length: max(end - start, 0))
            let content = ns.substring(with: range)
            sections[name] = content
        }
        return sections
    }

    private func extractEpisodesText(from text: String) -> String {
        let ns = text as NSString
        guard let (_, matches) = firstEpisodeMatches(in: text),
              let first = matches.first else {
            return text
        }
        let start = first.range.location
        let range = NSRange(location: start, length: ns.length - start)
        return ns.substring(with: range)
    }

    private func parseEpisodes(from text: String) -> [ScriptDocxImportItem] {
        guard let (regex, matches) = firstEpisodeMatches(in: text) else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return [] }
            return [
                ScriptDocxImportItem(
                    episodeNumber: 1,
                    title: "整片",
                    body: trimmed,
                    scenes: parseScenes(in: trimmed, episodeNumber: 1)
                )
            ]
        }
        let nsText = text as NSString

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
            let scenes = parseScenes(in: body, episodeNumber: episodeNumber)
            let title = "第\(episodeNumber)集"
            items.append(ScriptDocxImportItem(episodeNumber: episodeNumber, title: title, body: body, scenes: scenes))
        }
        return items
    }

    private func firstEpisodeMatches(in text: String) -> (NSRegularExpression, [NSTextCheckingResult])? {
        let ns = text as NSString
        for pattern in episodePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
                if matches.isEmpty == false {
                    return (regex, matches)
                }
            }
        }
        return nil
    }

    private func parseScenes(in body: String, episodeNumber: Int) -> [SceneImportItem] {
        let pattern = #"(?m)^\s*(\d+)[-—–](\d+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsBody = body as NSString
        let matches = regex.matches(in: body, options: [], range: NSRange(location: 0, length: nsBody.length))

        guard matches.isEmpty == false else {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return [] }
            return [
                SceneImportItem(
                    index: 1,
                    title: "第\(episodeNumber)集",
                    body: trimmed,
                    locationHint: "",
                    timeHint: ""
                )
            ]
        }

        var scenes: [SceneImportItem] = []
        for (index, match) in matches.enumerated() {
            let sceneStart = match.range.location + match.range.length
            let sceneEnd = (index + 1 < matches.count) ? matches[index + 1].range.location : nsBody.length
            let sceneRange = NSRange(location: sceneStart, length: max(sceneEnd - sceneStart, 0))
            let sceneBlock = nsBody.substring(with: sceneRange)
            let parsed = parseSceneBlock(sceneBlock, fallbackIndex: index + 1, episodeNumber: episodeNumber)
            scenes.append(parsed)
        }
        return scenes
    }

    private func normalize(_ text: String) -> String {
        var normalized = text
        let replacements: [String: String] = [
            "\u{00A0}": " ",
            "\u{200B}": "",
            "\u{2028}": "\n",
            "\u{2029}": "\n",
            "\u{FEFF}": "",
            "\r\n": "\n",
            "\r": "\n",
            "\u{202F}": " "
        ]
        for (k, v) in replacements {
            normalized = normalized.replacingOccurrences(of: k, with: v)
        }
        return normalized
    }

    private func stripPunctuation(_ text: String) -> String {
        let punctuation = CharacterSet(charactersIn: "。！？！，、；：？！（）【】《》“”‘’")
        return text.trimmingCharacters(in: punctuation.union(.whitespacesAndNewlines))
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

    private func parseCharacters(from text: String) -> [ProjectCharacterProfile] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        var result: [ProjectCharacterProfile] = []
        let pattern = #"^\s*([^（(：:]+)\s*[（(]([^）)]*)[)）]?\s*(.*)$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        for line in lines {
            if let regex,
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length)),
               match.numberOfRanges >= 4 {
                let ns = line as NSString
                let name = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                let role = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                let rest = ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
                let desc = [role, rest].filter { $0.isEmpty == false }.joined(separator: "｜")
                result.append(ProjectCharacterProfile(name: name, description: desc))
            } else {
                result.append(ProjectCharacterProfile(name: line, description: ""))
            }
        }
        return result
    }

    private func parseOutlines(from text: String) -> [EpisodeOutline] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && $0.hasPrefix("第") }
        var outlines: [EpisodeOutline] = []
        let pattern = #"第\s*([0-9０-９一二三四五六七八九十百千]+)\s*集[:：]\s*(.+)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        for line in lines {
            if let regex,
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length)),
               match.numberOfRanges >= 3 {
                let ns = line as NSString
                let numberString = ns.substring(with: match.range(at: 1))
                let number = parseEpisodeNumber(from: numberString)
                let summary = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                outlines.append(EpisodeOutline(episodeNumber: number, title: "第\(number)集", summary: summary))
            }
        }
        return outlines.sorted { $0.episodeNumber < $1.episodeNumber }
    }

    private func parseSceneBlock(_ block: String, fallbackIndex: Int, episodeNumber: Int) -> SceneImportItem {
        let lines = block
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        var title = "场景\(fallbackIndex)"
        var location = ""
        var time = ""
        var bodyLines: [String] = []
        var charactersLine: String?

        for line in lines {
            if line.hasPrefix("场景") {
                if let range = line.range(of: "：") ?? line.range(of: ":") {
                    let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    title = stripPunctuation(value)
                    location = title
                    continue
                }
            }
            if line.hasPrefix("人物") {
                charactersLine = line
                continue
            }
            if time.isEmpty, line.contains("日") || line.contains("夜") || line.contains("晨") || line.contains("晚") || line.contains("内") || line.contains("外") {
                time = stripPunctuation(line)
                continue
            }
            bodyLines.append(line)
        }

        if title.isEmpty {
            title = "第\(episodeNumber)集 · 场景\(fallbackIndex)"
        }

        if let charactersLine {
            bodyLines.insert(charactersLine, at: 0)
        }

        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return SceneImportItem(
            index: fallbackIndex,
            title: title,
            body: body,
            locationHint: location,
            timeHint: time
        )
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
    static func extractText(from url: URL) -> String? {
        if url.pathExtension.lowercased() == "docx",
           let data = try? Data(contentsOf: url),
           let archive = try? DocxArchive(data: data) {
            return archive.extractDocumentText()
        }
        if let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            return attributed.string
        }
        return nil
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
