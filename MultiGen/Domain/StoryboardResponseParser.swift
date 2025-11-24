//
//  StoryboardResponseParser.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

/// 解析 AI 返回的分镜 JSON 文本，并提供格式提示。
struct StoryboardResponseParser {
    struct ParsedStoryboardEntry {
        var fields: StoryboardEntryFields
        var sceneID: UUID?
        var sceneTitle: String?
        var sceneSummary: String?
    }

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
        var dialogueOrOS: String?
        var dialogue: String?
        var dialog: String?
        var os: String?
        var narration: String?
        var description: String?
        var visualSummary: String?
        var soundDesign: String?

        func makeFields(defaultShotNumber: Int) -> StoryboardEntryFields {
            let number = shotNumber ?? shot ?? number ?? index ?? defaultShotNumber
            let scaleValue = shotScale ?? scale ?? sceneScale ?? ""
            let movementValue = cameraMovement ?? camera ?? movement ?? ""
            let durationValue = duration ?? time ?? ""
            let dialogueValue = dialogueOrOS ?? dialogue ?? dialog ?? os ?? narration ?? ""
            let visualValue = visualSummary ?? description ?? ""
            let soundValue = soundDesign ?? ""

            return StoryboardEntryFields(
                shotNumber: number,
                shotScale: scaleValue,
                cameraMovement: movementValue,
                duration: durationValue,
                dialogueOrOS: dialogueValue,
                aiPrompt: "",
                visualSummary: visualValue,
                soundDesign: soundValue
            )
        }
    }

    struct ResponseEnvelope: Decodable {
        let entries: [EntryPayload]
    }

    struct ScenePayload: Decodable {
        var sceneId: UUID?
        var sceneTitle: String?
        var scene: String?
        var title: String?
        var sceneSummary: String?
        var summary: String?
        var overview: String?
        var shots: [EntryPayload]?
        var entries: [EntryPayload]?

        var resolvedTitle: String? {
            sceneTitle ?? scene ?? title
        }

        var resolvedSummary: String? {
            sceneSummary ?? summary ?? overview
        }
        var resolvedSceneID: UUID? { sceneId }

        var resolvedEntries: [EntryPayload] {
            shots ?? entries ?? []
        }
    }

    struct SceneEnvelope: Decodable {
        let scenes: [ScenePayload]
    }

    static let responseFormatHint = """
    请以 JSON 输出，推荐结构：{"scenes":[{"sceneId":"<提供的 sceneId>","sceneTitle":"场景标题","sceneSummary":"摘要","shots":[{"shotNumber":1,"shotScale":"中景","cameraMovement":"推镜","duration":"4s","dialogueOrOS":"……","visualSummary":"……","soundDesign":"……"}]}]}。如仅生成单个场景，也可直接输出 {"entries":[...]}。
    """

    func parseEntries(from text: String, nextShotNumber: Int) -> [ParsedStoryboardEntry] {
        guard let jsonString = extractJSON(from: text),
              let data = jsonString.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let sceneEnvelope = try? decoder.decode(SceneEnvelope.self, from: data) {
            return flattenScenes(sceneEnvelope.scenes, startingShot: nextShotNumber)
        } else if let envelope = try? decoder.decode(ResponseEnvelope.self, from: data) {
            return flatten(entries: envelope.entries, sceneID: nil, sceneTitle: nil, sceneSummary: nil, startingShot: nextShotNumber)
        } else if let arrayPayload = try? decoder.decode([EntryPayload].self, from: data) {
            return flatten(entries: arrayPayload, sceneID: nil, sceneTitle: nil, sceneSummary: nil, startingShot: nextShotNumber)
        } else {
            return []
        }
    }

    private func flattenScenes(_ scenes: [ScenePayload], startingShot: Int) -> [ParsedStoryboardEntry] {
        var all: [ParsedStoryboardEntry] = []
        var currentShot = max(startingShot, 1)
        for scene in scenes {
            let sceneEntries = flatten(
                entries: scene.resolvedEntries,
                sceneID: scene.resolvedSceneID,
                sceneTitle: scene.resolvedTitle,
                sceneSummary: scene.resolvedSummary,
                startingShot: currentShot
            )
            if let lastShot = sceneEntries.map(\.fields.shotNumber).max() {
                currentShot = lastShot + 1
            }
            all.append(contentsOf: sceneEntries)
        }
        return all
    }

    private func flatten(
        entries: [EntryPayload],
        sceneID: UUID?,
        sceneTitle: String?,
        sceneSummary: String?,
        startingShot: Int
    ) -> [ParsedStoryboardEntry] {
        guard entries.isEmpty == false else { return [] }
        var resolved: [ParsedStoryboardEntry] = []
        var currentShot = max(startingShot, 1)

        for payload in entries {
            var fields = payload.makeFields(defaultShotNumber: currentShot)
            if fields.shotNumber <= 0 {
                fields.shotNumber = currentShot
            }
            currentShot = fields.shotNumber + 1
            resolved.append(
                ParsedStoryboardEntry(
                    fields: fields,
                    sceneID: sceneID,
                    sceneTitle: sceneTitle,
                    sceneSummary: sceneSummary
                )
            )
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
        guard let fenceStart = text.range(of: "```json") ?? text.range(of: "```JSON") ?? text.range(of: "```") else { return nil }
        let remainder = text[fenceStart.upperBound...]
        guard let fenceEnd = remainder.range(of: "```") else { return nil }
        return String(remainder[..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
