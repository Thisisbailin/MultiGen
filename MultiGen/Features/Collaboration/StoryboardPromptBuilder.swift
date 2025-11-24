import Foundation

struct StoryboardPromptBuilder {
    let project: ScriptProject
    let episode: ScriptEpisode
    let scenes: [ScriptScene]
    let workspace: StoryboardWorkspace?
    let systemPrompt: String?

    func makeFields() -> [String: String] {
        var fields: [String: String] = [:]
        if let systemPrompt {
            let trimmed = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                fields["systemPrompt"] = trimmed
            }
        }
        fields["prompt"] = makePromptBody()
        fields["responseFormat"] = StoryboardResponseParser.responseFormatHint
        return fields
    }

    private func makePromptBody() -> String {
        """
        你将扮演资深分镜导演，请严格按照以下顺序理解上下文，并最终只输出 JSON：

        项目标题：\(project.title)
        项目简介：\(project.synopsis.ifEmptyPlaceholder())
        剧集：\(episode.displayLabel)

        \(sceneLines())

        场景元数据（JSON，仅供引用 sceneId）：\(sceneMetadataJSON())

        输出要求：
        1) 仅输出 {"scenes":[...]} JSON，不要使用 ```json 或其他说明；
        2) 每个 scene 对象必须包含 sceneId、sceneTitle、sceneSummary、shots；
        3) shots 内需包含 shotNumber/shotScale/cameraMovement/duration/dialogueOrOS/visualSummary/soundDesign（无需提示词），shotNumber 在所属场景内递增；
        4) 严禁创建新场景或把多个场景合并；
        5) 无法生成时返回 {"scenes":[]}。
        """
    }

    private func sceneLines() -> String {
        guard scenes.isEmpty == false else { return "（暂无场景，请补充剧本文本）" }
        return scenes
            .sorted(by: { $0.order < $1.order })
            .map { scene in
                "场景：\(scene.title)\n场景内容：\(sanitized(scene.body, limit: 2500))"
            }
            .joined(separator: "\n\n")
    }

    private func sceneMetadataJSON() -> String {
        struct Metadata: Codable {
            let id: UUID
            let title: String
            let summary: String
            let order: Int
        }
        let payload = scenes
            .sorted(by: { $0.order < $1.order })
            .map { scene in
                Metadata(
                    id: scene.id,
                    title: scene.title,
                    summary: scene.summary,
                    order: scene.order
                )
            }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(payload),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "[]"
    }

    private func sanitized(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "（暂无内容）" }
        if trimmed.count <= limit {
            return trimmed
        }
        let prefixText = trimmed.prefix(limit)
        return "\(prefixText)…（已截断）"
    }
}

private extension String {
    func ifEmptyPlaceholder(_ placeholder: String = "（暂无内容）") -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeholder : trimmed
    }
}
