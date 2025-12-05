import Foundation

/// 构造批量分镜/提示词阶段的 prompt 字段，复用现有解析器格式。
struct BatchStoryboardPromptBuilder {
    struct ContextInputs {
        let project: ScriptProject
        let storyboardGuide: String
    }

    struct EpisodeStoryboardInputs {
        let project: ScriptProject
        let episode: ScriptEpisode
        let accumulatedEpisodeOverview: String
        let storyboardGuide: String
        let projectSummary: String
        let characterSummary: String
    }

    struct EpisodeSoraInputs {
        let project: ScriptProject
        let episode: ScriptEpisode
        let storyboardScript: String
        let promptGuide: String
        let projectSummary: String
        let characterSummary: String
    }

    func contextPrompt(_ inputs: ContextInputs) -> String {
        """
        你是剧集项目的总览助手。请基于以下资料生成三段内容，并用固定标记分隔，方便后续解析：
        【项目简介】
        【角色概述】
        【剧集概述】

        项目标题：\(inputs.project.title)
        项目简介（已有）：\(inputs.project.synopsis.ifEmptyPlaceholder("暂无简介"))
        分镜指导文档（用户导入）：\(sanitized(inputs.storyboardGuide))
        剧集数量：\(inputs.project.episodes.count)

        输出要求：
        - 段落1 【项目简介】：300-500 字，含题材/基调/背景/核心冲突。
        - 段落2 【角色概述】：按重要度排序，包含外形/性格/动机/关系，200-400 字。
        - 段落3 【剧集概述】：按剧集序号逐集简述剧情走向，每集 2-4 句。
        - 只输出三段正文，中间保留上述标记，不要列表/代码块/其他解释。
        """
    }

    func storyboardPrompt(_ inputs: EpisodeStoryboardInputs) -> [String: String] {
        var fields: [String: String] = [:]
        let prompt = """
        你是资深分镜导演。请按整集生成分镜，输出兼容解析器的 JSON。

        项目标题：\(inputs.project.title)
        项目简介：\(sanitized(inputs.projectSummary))
        主要角色概述：\(sanitized(inputs.characterSummary))
        累积剧集概述（第1集至当前集）：\(sanitized(inputs.accumulatedEpisodeOverview))
        当前剧集：\(inputs.episode.displayLabel)
        当前剧集正文：\(sanitized(inputs.episode.markdown, limit: 6000))
        分镜指导文档（用户导入）：\(sanitized(inputs.storyboardGuide, limit: 4000))

        输出要求：
        1) 仅输出 JSON，结构需兼容：\(StoryboardResponseParser.responseFormatHint)
        2) 每个场景的 shots 需包含：shotNumber, shotScale, cameraMovement, duration, dialogueOrOS, visualSummary, soundDesign。
        3) 严禁返回除 JSON 以外的文字/解释/代码块。
        4) 若无法生成，请返回 {"scenes":[]}。
        """
        fields["prompt"] = prompt
        fields["responseFormat"] = StoryboardResponseParser.responseFormatHint
        return fields
    }

    func soraPrompt(_ inputs: EpisodeSoraInputs) -> [String: String] {
        var fields: [String: String] = [:]
        let prompt = """
        你是专业分镜提示词设计师。请为下方分镜脚本的每个镜头生成 Sora 提示词，要求纯文本 JSON。

        项目标题：\(inputs.project.title)
        项目简介：\(sanitized(inputs.projectSummary))
        主要角色概述：\(sanitized(inputs.characterSummary))
        当前剧集：\(inputs.episode.displayLabel)
        分镜脚本（AI 已生成并确认）：\(sanitized(inputs.storyboardScript, limit: 7000))
        提示词撰写指导文档（用户导入）：\(sanitized(inputs.promptGuide, limit: 4000))

        输出要求：
        - 仅输出 JSON：{"prompts":[{"shotNumber":1,"prompt":"..."}]}
        - 提示词需对应镜号 shotNumber，聚焦画面/光线/色调/构图/焦段/运动/材质，避免解释。
        - 不要返回非 JSON 内容或多余说明。
        """
        fields["prompt"] = prompt
        return fields
    }

    private func sanitized(_ text: String, limit: Int = 3200) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "（无内容）" }
        if trimmed.count <= limit { return trimmed }
        return "\(trimmed.prefix(limit))…（已截断）"
    }
}

private extension String {
    func ifEmptyPlaceholder(_ placeholder: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeholder : trimmed
    }
}
