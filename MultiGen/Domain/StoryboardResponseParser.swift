//
//  StoryboardResponseParser.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

/// 解析 AI 返回的分镜 JSON 文本，并提供格式提示。
struct StoryboardResponseParser {
    struct EntryPayload: Decodable {
        var shotNumber: Int?
        var shot: Int?
        var number: Int?
        var index: Int?
        var shotScale: String?
        var scale: String?
        var sceneScale: String?
        var cameraMovement: String?
        var camera: String?
        var movement: String?
        var duration: String?
        var time: String?
        var dialogue: String?
        var dialog: String?
        var os: String?
        var narration: String?
        var aiPrompt: String?
        var prompt: String?
        var description: String?

        func makeFields(defaultShotNumber: Int) -> StoryboardEntryFields {
            let number = shotNumber ?? shot ?? number ?? index ?? defaultShotNumber
            let scaleValue = shotScale ?? scale ?? sceneScale ?? ""
            let movementValue = cameraMovement ?? camera ?? movement ?? ""
            let durationValue = duration ?? time ?? ""
            let dialogueValue = dialogue ?? dialog ?? os ?? narration ?? description ?? ""
            let promptValue = aiPrompt ?? prompt ?? ""

            return StoryboardEntryFields(
                shotNumber: number,
                shotScale: scaleValue,
                cameraMovement: movementValue,
                duration: durationValue,
                dialogueOrOS: dialogueValue,
                aiPrompt: promptValue
            )
        }
    }

    struct ResponseEnvelope: Decodable {
        let entries: [EntryPayload]
    }

    static let responseFormatHint = """
    请以 JSON 输出，形如 {"entries":[{"shotNumber":1,"shotScale":"中景","cameraMovement":"推镜","duration":"4s","dialogue":"……","aiPrompt":"……"}]}，字段必须完整且使用双引号。
    """

    func parseEntries(from text: String, nextShotNumber: Int) -> [StoryboardEntryFields] {
        guard let jsonString = extractJSON(from: text),
              let data = jsonString.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let payloads: [EntryPayload]
        if let envelope = try? decoder.decode(ResponseEnvelope.self, from: data) {
            payloads = envelope.entries
        } else if let arrayPayload = try? decoder.decode([EntryPayload].self, from: data) {
            payloads = arrayPayload
        } else {
            return []
        }

        var resolved: [StoryboardEntryFields] = []
        var currentShot = max(nextShotNumber, 1)

        for payload in payloads {
            var fields = payload.makeFields(defaultShotNumber: currentShot)
            if fields.shotNumber <= 0 {
                fields.shotNumber = currentShot
            }
            currentShot = fields.shotNumber + 1
            resolved.append(fields)
        }

        return resolved
    }

    static func sampleJSON(seed: UUID, count: Int = 2, startingShot: Int = 1) -> String {
        let entries = (0..<count).map { offset -> [String: Any] in
            let shotNumber = startingShot + offset
            return [
                "shotNumber": shotNumber,
                "shotScale": offset.isMultiple(of: 2) ? "中近景" : "大全景",
                "cameraMovement": offset.isMultiple(of: 2) ? "推镜" : "跟拍",
                "duration": "\(4 + offset)s",
                "dialogue": offset.isMultiple(of: 2) ? "OS：凌然凝视霓虹反射。" : "台词：\"我们没有退路\"",
                "aiPrompt": "镜\(shotNumber)：赛博朋克都市，\(offset.isMultiple(of: 2) ? "静态氛围" : "疾速追逐")，参考 seed:\(seed.uuidString.prefix(6))"
            ]
        }

        let data = try? JSONSerialization.data(withJSONObject: ["entries": entries], options: [.prettyPrinted, .withoutEscapingSlashes])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private func extractJSON(from text: String) -> String? {
        if let fenced = extractFencedJSON(from: text) {
            return fenced
        }

        guard let firstBrace = text.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let lastBrace = text.lastIndex(where: { $0 == "}" || $0 == "]" }),
              firstBrace < lastBrace else {
            return nil
        }

        return String(text[firstBrace...lastBrace])
    }

    private func extractFencedJSON(from text: String) -> String? {
        guard let fenceStart = text.range(of: "```json") else { return nil }
        let remainder = text[fenceStart.upperBound...]
        guard let fenceEnd = remainder.range(of: "```") else { return nil }
        return String(remainder[..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
