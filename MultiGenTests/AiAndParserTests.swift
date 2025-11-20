//
//  AiAndParserTests.swift
//  MultiGenTests
//
//  Created by Codex on 2025/02/15.
//

import Testing
@testable import MultiGen

struct PromptTemplateCatalogTests {
    @Test func workflowTemplatesCoverAllActions() async throws {
        let lookup = Dictionary(uniqueKeysWithValues: PromptTemplateCatalog.templates.map { ($0.id, $0) })
        for action in SceneAction.workflowActions {
            let template = lookup[action]
            #expect(template != nil, "\(action.rawValue) 缺少模板")
            #expect(template?.fields.isEmpty == false, "\(action.rawValue) 模板字段为空")
        }
    }
}

struct StoryboardResponseParserTests {
    @Test func parseEntriesFromSimpleEnvelope() {
        let parser = StoryboardResponseParser()
        let json = """
        {"entries":[{"shotNumber":1,"shotScale":"大全景","cameraMovement":"推镜","duration":"4s","dialogue":"旁白","aiPrompt":"提示1"}]}
        """
        let entries = parser.parseEntries(from: json, nextShotNumber: 1)
        #expect(entries.count == 1)
        let fields = entries.first?.fields
        #expect(fields?.shotNumber == 1)
        #expect(fields?.cameraMovement == "推镜")
        #expect(fields?.dialogueOrOS.contains("旁白") == true)
    }

    @Test func parseSceneEnvelopeMaintainsShotOrdering() {
        let parser = StoryboardResponseParser()
        let json = """
        {"scenes":[{"sceneTitle":"夜市","entries":[{"shot":0,"camera":"跟拍"},{"shot":2,"camera":"俯拍"}]}]}
        """
        let entries = parser.parseEntries(from: json, nextShotNumber: 3)
        #expect(entries.count == 2)
        #expect(entries.first?.fields.shotNumber == 3)
        #expect(entries.last?.fields.shotNumber == 4)
    }
}

struct AIChatRequestBuilderTests {
    @Test func storyboardContextInjectsSceneAndResponseFormat() {
        let scene = ScriptScene(order: 1, title: "地下实验室", summary: "紧张气氛", body: "人物悄然潜入。")
        let episode = ScriptEpisode(episodeNumber: 1, title: "Pilot", markdown: "整集 Markdown", scenes: [scene])
        let project = ScriptProject(title: "测试项目", episodes: [episode])
        let entry = StoryboardEntry(
            episodeID: episode.id,
            fields: StoryboardEntryFields(shotNumber: 1, shotScale: "中景", cameraMovement: "推镜"),
            sceneTitle: scene.title,
            sceneSummary: scene.summary
        )
        let workspace = StoryboardWorkspace(
            episodeID: episode.id,
            episodeNumber: episode.episodeNumber,
            episodeTitle: episode.displayLabel,
            episodeSynopsis: episode.synopsis,
            entries: [entry]
        )
        let snapshot = StoryboardSceneContextSnapshot(
            id: scene.id,
            title: scene.title,
            order: scene.order,
            summary: scene.summary,
            body: scene.body
        )
        let context = ChatContext.storyboard(
            project: project,
            episode: episode,
            scene: scene,
            snapshot: snapshot,
            workspace: workspace
        )
        let fields = AIChatRequestBuilder.makeFields(
            prompt: "帮我生成分镜",
            context: context,
            module: .storyboard,
            systemPrompt: "系统提示词"
        )
        #expect(fields["systemPrompt"] == "系统提示词")
        #expect(fields["responseFormat"] == StoryboardResponseParser.responseFormatHint)
        #expect(fields["sceneContext"]?.contains("地下实验室") == true)
        #expect(fields["scriptContext"]?.contains("剧集：") == true)
        #expect(fields["storyboardContext"]?.contains("镜1") == true)
    }
}
