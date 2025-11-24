//
//  AIChatRequestBuilder.swift
//  MultiGen
//
//  Created by Codex on 2025/02/15.
//

import Foundation

struct AIChatRequestBuilder {
    static func makeFields(
        prompt: String,
        context: ChatContext,
        module: PromptDocument.Module,
        systemPrompt: String?
    ) -> [String: String] {
        var fields: [String: String] = [
            "prompt": prompt
        ]

        if let systemPrompt, systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            fields["systemPrompt"] = systemPrompt
        }

        let extras = contextFields(for: context)
        extras.forEach { key, value in
            guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
            fields[key] = value
        }

        if case .storyboard = context {
            fields["responseFormat"] = StoryboardResponseParser.responseFormatHint
        }

        return fields
    }

    static func contextFields(for context: ChatContext) -> [String: String] {
        switch context {
        case .general:
            return [:]
        case .script(let project, let episode):
            return [
                "scriptContext": makeScriptContext(episode: episode, project: project)
            ]
        case .storyboard(let project, let episode, let scene, let snapshot, let workspace):
            var payload: [String: String] = [
                "scriptContext": makeScriptContext(episode: episode, project: project)
            ]
            if let scene {
                payload["sceneContext"] = makeSceneContext(scene: scene)
            } else if let snapshot {
                payload["sceneContext"] = makeSceneContext(snapshot: snapshot)
            }
            if let storyboardSummary = makeStoryboardContext(workspace: workspace) {
                payload["storyboardContext"] = storyboardSummary
            }
            return payload
        case .scriptProject(let project):
            return [
                "projectContext": makeProjectContext(project: project)
            ]
        }
    }

    private static func makeScriptContext(episode: ScriptEpisode, project: ScriptProject?) -> String {
        var lines: [String] = []
        if let project {
            lines.append("项目：\(project.title)")
        }
        lines.append("剧集：\(episode.displayLabel)")
        if episode.synopsis.isEmpty == false {
            lines.append("简介：\(episode.synopsis)")
        }
        let body = sanitizedBody(episode.markdown, limit: 6000)
        lines.append("正文：\n\(body)")
        return lines.joined(separator: "\n")
    }

    private static func makeStoryboardContext(workspace: StoryboardWorkspace?) -> String? {
        guard let workspace else { return nil }
        let entries = workspace.orderedEntries
        guard entries.isEmpty == false else { return nil }
        let maxShots = 12
        var blocks: [String] = []
        for entry in entries.prefix(maxShots) {
            var segment: [String] = []
            segment.append("镜\(entry.fields.shotNumber) · \(entry.sceneTitle)")
            let tags = [
                entry.fields.shotScale.isEmpty ? nil : "景别：\(entry.fields.shotScale)",
                entry.fields.cameraMovement.isEmpty ? nil : "运镜：\(entry.fields.cameraMovement)",
                entry.fields.duration.isEmpty ? nil : "时长：\(entry.fields.duration)"
            ].compactMap { $0 }.joined(separator: "｜")
            if tags.isEmpty == false {
                segment.append(tags)
            }
            if entry.sceneSummary.isEmpty == false {
                segment.append("画面：\(entry.sceneSummary)")
            }
            if entry.fields.dialogueOrOS.isEmpty == false {
                segment.append("台词/OS：\(entry.fields.dialogueOrOS)")
            }
            if entry.fields.aiPrompt.isEmpty == false {
                segment.append("提示词：\(entry.fields.aiPrompt)")
            }
            if entry.notes.isEmpty == false {
                segment.append("备注：\(entry.notes)")
            }
            blocks.append(segment.joined(separator: "\n"))
        }
        if entries.count > maxShots {
            blocks.append("……其余 \(entries.count - maxShots) 个镜头已省略。")
        }
        return blocks.joined(separator: "\n\n")
    }

    private static func makeSceneContext(scene: ScriptScene) -> String {
        makeSceneContext(
            title: scene.title,
            order: scene.order,
            summary: scene.summary,
            body: scene.body
        )
    }

    private static func makeSceneContext(snapshot: StoryboardSceneContextSnapshot) -> String {
        makeSceneContext(
            title: snapshot.title,
            order: snapshot.order,
            summary: snapshot.summary,
            body: snapshot.body
        )
    }

    private static func makeSceneContext(title: String, order: Int?, summary: String, body: String) -> String {
        var lines: [String] = []
        if let order {
            lines.append("场景：\(title) · 序号 \(order)")
        } else {
            lines.append("场景：\(title)")
        }
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            lines.append("摘要：\(summary)")
        }
        let normalizedBody = sanitizedBody(body, limit: 3000)
        lines.append("正文：\n\(normalizedBody)")
        return lines.joined(separator: "\n")
    }

    private static func makeProjectContext(project: ScriptProject) -> String {
        var lines: [String] = []
        lines.append("项目：\(project.title)")
        lines.append("类型：\(project.type.displayName)")
        lines.append("")
        lines.append("剧本文本（按集与场景顺序）：")
        for episode in project.orderedEpisodes {
            let episodeTitle = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let episodeHeader = episodeTitle.isEmpty ? "第\(episode.episodeNumber)集" : "第\(episode.episodeNumber)集 · \(episodeTitle)"
            lines.append(episodeHeader)
            let scenes = episode.scenes.sorted { $0.order < $1.order }
            for scene in scenes {
                let extras = [scene.locationHint, scene.timeHint].filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
                let header = extras.isEmpty ? scene.title : ([scene.title] + extras).joined(separator: " · ")
                lines.append("场景\(scene.order)：\(header)")
                let body = scene.body.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append(body.isEmpty ? "（无正文）" : body)
            }
            lines.append("") // blank between episodes
        }
        return lines.joined(separator: "\n")
    }

    private static func sanitizedBody(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return "（尚未提供剧本文本）"
        }
        if trimmed.count <= limit {
            return trimmed
        }
        let prefixText = trimmed.prefix(limit)
        return "\(prefixText)…（已截断）"
    }
}
