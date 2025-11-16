//
//  AIActionCenter.swift
//  MultiGen
//
//  Created by Codex on 2025/02/16.
//

import Combine
import Foundation

enum AIActionKind {
    case conversation
    case storyboardOperation
    case sceneComposer
    case imaging
    case diagnostics
}

struct AIActionRequest {
    let kind: AIActionKind
    let prompt: String
    let module: PromptDocument.Module
    let context: ChatContext
    let fields: [String: String]
    let channel: SceneJobChannel
    let assetReferences: [String]
    let origin: String
}

struct AIActionResult {
    let request: AIActionRequest
    let text: String?
    let image: NSImage?
    let metadata: SceneJobResult.Metadata
}

@MainActor
final class AIActionCenter: ObservableObject {
    private let dependencies: AppDependencies
    private let promptLibraryStore: PromptLibraryStore
    private let navigationStore: NavigationStore
    private let scriptStore: ScriptStore
    private let storyboardStore: StoryboardStore

    private var cancellables: Set<AnyCancellable> = []

    @Published private(set) var systemMessages: [String] = []

    init(
        dependencies: AppDependencies,
        promptLibraryStore: PromptLibraryStore,
        navigationStore: NavigationStore,
        scriptStore: ScriptStore,
        storyboardStore: StoryboardStore
    ) {
        self.dependencies = dependencies
        self.promptLibraryStore = promptLibraryStore
        self.navigationStore = navigationStore
        self.scriptStore = scriptStore
        self.storyboardStore = storyboardStore
    }

    func perform(_ request: AIActionRequest) async throws -> AIActionResult {
        let fields = AIChatRequestBuilder.makeFields(
            prompt: request.prompt,
            context: request.context,
            module: request.module,
            systemPrompt: promptLibraryStore.document(for: request.module).content,
            statusText: contextStatusText(for: request.context)
        )
        let sceneJobRequest = SceneJobRequest(
            action: .aiConsole,
            fields: fields,
            assetReferences: request.assetReferences,
            channel: request.channel
        )

        switch request.channel {
        case .text:
            let result = try await dependencies.textService().submit(job: sceneJobRequest)
            let auditEntry = AuditLogEntry(
                jobID: sceneJobRequest.id,
                action: sceneJobRequest.action,
                promptHash: String(result.metadata.prompt.hashValue, radix: 16),
                assetRefs: request.assetReferences,
                modelVersion: result.metadata.model,
                metadata: [
                    "source": request.origin,
                    "route": dependencies.currentTextRoute().displayName,
                    "context": contextStatusText(for: request.context)
                ]
            )
            await dependencies.auditRepository.record(auditEntry)

            if case .storyboardOperation = request.kind {
                applyStoryboardOperation(response: result.metadata.prompt)
            }
            appendSystemMessage("\(request.origin) · 文本请求 · \(dependencies.currentTextRoute().displayName)")
            return AIActionResult(
                request: request,
                text: result.metadata.prompt,
                image: nil,
                metadata: result.metadata
            )
        case .image:
            let result = try await dependencies.imageService().generateImage(for: sceneJobRequest)
            let image = NSImage(base64String: result.imageBase64)
            let auditEntry = AuditLogEntry(
                jobID: sceneJobRequest.id,
                action: sceneJobRequest.action,
                promptHash: String(sceneJobRequest.fields.hashValue, radix: 16),
                assetRefs: request.assetReferences,
                modelVersion: result.metadata.model,
                metadata: [
                    "source": request.origin,
                    "route": dependencies.currentImageRoute().displayName,
                    "context": contextStatusText(for: request.context)
                ]
            )
            await dependencies.auditRepository.record(auditEntry)
            appendSystemMessage("\(request.origin) · 图像请求 · \(dependencies.currentImageRoute().displayName)")
            return AIActionResult(
                request: request,
                text: nil,
                image: image,
                metadata: result.metadata
            )
        }
    }

    private func contextStatusText(for context: ChatContext) -> String {
        switch context {
        case .general:
            return "上下文：主页"
        case .script(_, let episode):
            return "上下文：剧本 · \(episode.displayLabel)"
        case .storyboard(_, let episode, let scene, let snapshot, _):
            var base = "上下文：分镜 · \(episode.displayLabel)"
            if let title = scene?.title ?? snapshot?.title {
                base += " · \(title)"
            }
            return base
        case .scriptProject(let project):
            return "上下文：项目 · \(project.title)"
        }
    }

    private func applyStoryboardOperation(response: String) {
        guard let handler = navigationStore.storyboardAutomationHandler else {
            appendSystemMessage("分镜自动化未激活，回复已记录。")
            return
        }
        if let result = handler.applySidebarAIResponse(response), result.touchedEntries > 0 {
            appendSystemMessage("分镜更新完成：\(result.touchedEntries) 个镜头已写入。")
        } else {
            appendSystemMessage("分镜回复未解析出有效结构。")
        }
    }

    private func appendSystemMessage(_ text: String) {
        systemMessages.append(text)
    }
}
