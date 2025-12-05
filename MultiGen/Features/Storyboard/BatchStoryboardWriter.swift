import Foundation

/// 将批量分镜/提示词结果写入 StoryboardStore，复用现有解析器与存储结构。
struct BatchStoryboardWriter {
    struct StoryboardWriteResult {
        let touchedCount: Int
        let warning: String?
    }

    struct SoraWriteResult {
        let updatedCount: Int
        let warning: String?
    }

    private let parser = StoryboardResponseParser()

    func applyStoryboardResponse(
        _ response: String,
        project: ScriptProject,
        episode: ScriptEpisode,
        storyboardStore: StoryboardStore
    ) -> StoryboardWriteResult {
        let parsed = parser.parseEntries(from: response, nextShotNumber: 1)
        guard parsed.isEmpty == false else {
            return StoryboardWriteResult(touchedCount: 0, warning: "未解析出有效分镜 JSON。")
        }
        guard episode.scenes.isEmpty == false else {
            return StoryboardWriteResult(touchedCount: 0, warning: "当前剧集尚无场景，无法写入分镜。请先在剧本模块补充场景。")
        }

        let workspace = storyboardStore.ensureWorkspace(for: episode)
        var entries = workspace.entries
        var touched: [UUID] = []
        var nextShotCache: [UUID: Int] = [:]

        for parsedEntry in parsed {
            guard let scene = resolveScene(for: parsedEntry, in: episode) else {
                continue
            }
            var fields = parsedEntry.fields
            if fields.shotNumber <= 0 {
                fields.shotNumber = nextShotNumber(for: scene.id, existing: entries, cache: &nextShotCache)
            }
            fields.aiPrompt = ""

            if let idx = entries.firstIndex(where: { $0.sceneID == scene.id && $0.fields.shotNumber == fields.shotNumber }) {
                var entry = entries[idx]
                entry.version += 1
                entry.fields = fields
                entry.status = .pendingReview
                entry.updatedAt = .now
                entry.sceneID = scene.id
                entry.sceneTitle = scene.title
                entry.sceneSummary = scene.summary
                let revision = StoryboardRevision(
                    version: entry.version,
                    authorRole: .assistant,
                    summary: "批量分镜更新 镜\(fields.shotNumber)",
                    fields: fields,
                    sourceTurnID: nil
                )
                entry.revisions.append(revision)
                entries[idx] = entry
                touched.append(entry.id)
            } else {
                var entry = StoryboardEntry(
                    episodeID: episode.id,
                    fields: fields,
                    status: .pendingReview,
                    version: 1,
                    notes: "",
                    revisions: [
                        StoryboardRevision(
                            version: 1,
                            authorRole: .assistant,
                            summary: "批量分镜初稿 镜\(fields.shotNumber)",
                            fields: fields,
                            sourceTurnID: nil
                        )
                    ],
                    lastTurnID: nil,
                    sceneTitle: scene.title,
                    sceneSummary: scene.summary
                )
                entry.sceneID = scene.id
                entry.createdAt = .now
                entry.updatedAt = .now
                entries.append(entry)
                touched.append(entry.id)
            }
        }

        entries.sort { $0.fields.shotNumber < $1.fields.shotNumber }
        storyboardStore.saveEntries(entries, for: episode.id)
        return StoryboardWriteResult(touchedCount: touched.count, warning: nil)
    }

    func applySoraPrompts(
        _ response: String,
        episode: ScriptEpisode,
        storyboardStore: StoryboardStore
    ) -> SoraWriteResult {
        guard let workspace = storyboardStore.workspace(for: episode.id) else {
            return SoraWriteResult(updatedCount: 0, warning: "未找到分镜工作区，先生成分镜再写入提示词。")
        }
        guard let json = extractJSON(from: response),
              let data = json.data(using: .utf8) else {
            return SoraWriteResult(updatedCount: 0, warning: "未解析出有效提示词 JSON。")
        }

        struct PromptPayload: Decodable {
            let shotNumber: Int?
            let prompt: String?
        }
        struct PromptEnvelope: Decodable {
            let prompts: [PromptPayload]
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload: [PromptPayload]
        if let envelope = try? decoder.decode(PromptEnvelope.self, from: data) {
            payload = envelope.prompts
        } else if let array = try? decoder.decode([PromptPayload].self, from: data) {
            payload = array
        } else {
            return SoraWriteResult(updatedCount: 0, warning: "提示词 JSON 结构不符合要求。")
        }

        guard payload.isEmpty == false else {
            return SoraWriteResult(updatedCount: 0, warning: "提示词列表为空。")
        }

        var entries = workspace.entries
        var updated = 0
        for item in payload {
            guard let shot = item.shotNumber, shot > 0 else { continue }
            guard let text = item.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false else { continue }
            if let idx = entries.firstIndex(where: { $0.fields.shotNumber == shot }) {
                entries[idx].fields.aiPrompt = text
                entries[idx].updatedAt = .now
                updated += 1
            }
        }
        storyboardStore.saveEntries(entries, for: episode.id)
        return SoraWriteResult(updatedCount: updated, warning: updated == 0 ? "未匹配到对应镜号的分镜。" : nil)
    }

    private func resolveScene(for parsed: StoryboardResponseParser.ParsedStoryboardEntry, in episode: ScriptEpisode) -> (id: UUID, title: String, summary: String)? {
        if let id = parsed.sceneID,
           let scene = episode.scenes.first(where: { $0.id == id }) {
            return (scene.id, scene.title, scene.summary)
        }
        if let title = parsed.sceneTitle,
           let scene = episode.scenes.first(where: { normalized($0.title) == normalized(title) }) {
            return (scene.id, scene.title, scene.summary)
        }
        if let first = episode.scenes.sorted(by: { $0.order < $1.order }).first {
            return (first.id, first.title, first.summary)
        }
        return nil
    }

    private func nextShotNumber(for sceneID: UUID, existing: [StoryboardEntry], cache: inout [UUID: Int]) -> Int {
        if let cached = cache[sceneID] {
            cache[sceneID] = cached + 1
            return cached
        }
        let existingMax = existing
            .filter { $0.sceneID == sceneID }
            .map { $0.fields.shotNumber }
            .max() ?? 0
        let next = existingMax + 1
        cache[sceneID] = next + 1
        return next
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func extractJSON(from text: String) -> String? {
        if let fenced = extractFencedJSONSnippet(from: text) {
            return fenced
        }
        guard let firstBrace = text.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let lastBrace = text.lastIndex(where: { $0 == "}" || $0 == "]" }),
              firstBrace < lastBrace else { return nil }
        return String(text[firstBrace...lastBrace])
    }
    
    private func extractFencedJSONSnippet(from text: String) -> String? {
        guard let fenceStart = text.range(of: "```json") ?? text.range(of: "```JSON") ?? text.range(of: "```") else { return nil }
        let remainder = text[fenceStart.upperBound...]
        guard let fenceEnd = remainder.range(of: "```") else { return nil }
        return String(remainder[..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
