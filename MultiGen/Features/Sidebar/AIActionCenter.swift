//
//  AIActionCenter.swift
//  MultiGen
//
//  Created by Codex on 2025/02/16.
//

import AppKit
import Combine
import Foundation

enum AIActionKind {
    case conversation
    case storyboardOperation
    case projectSummary
    case sceneComposer
    case diagnostics
}

struct AIActionRequest {
    let kind: AIActionKind
    let action: SceneAction
    let channel: SceneJobChannel
    let fields: [String: String]
    let assetReferences: [String]
    let module: PromptDocument.Module?
    let context: ChatContext?
    let contextSummaryOverride: String?
    let origin: String
}

struct AIActionResult {
    let request: AIActionRequest
    let text: String?
    let image: NSImage?
    let imageBase64: String?
    let imageURL: URL?
    let videoURL: URL?
    let metadata: SceneJobResult.Metadata
    let route: AIRoute
}

enum AIActionStreamEvent {
    case partial(String)
    case completed(AIActionResult)
}

@MainActor
final class AIActionCenter: ObservableObject {
    private let dependencies: AppDependencies
    private let navigationStore: NavigationStore

    init(
        dependencies: AppDependencies,
        navigationStore: NavigationStore
    ) {
        self.dependencies = dependencies
        self.navigationStore = navigationStore
    }

    func perform(_ request: AIActionRequest) async throws -> AIActionResult {
        let contextDescription = contextStatusText(
            override: request.contextSummaryOverride,
            context: request.context
        )
        let sceneRequest = SceneJobRequest(
            action: request.action,
            fields: request.fields,
            assetReferences: request.assetReferences,
            channel: request.channel
        )
        logRequest(request: request, sceneRequest: sceneRequest)

        let route = dependencies.currentTextRoute()
        let result = try await dependencies.textService().submit(job: sceneRequest)
        let renderedImage = Self.decodeImage(base64: result.imageBase64)
        var textPayload = result.metadata.prompt
        if let inlineURL = result.imageURL?.absoluteString {
            textPayload += "\n\(inlineURL)"
        } else if let base64 = result.imageBase64, base64.isEmpty == false {
            textPayload += "\ndata:image/png;base64,\(base64)"
        }
        await recordAudit(
            jobID: sceneRequest.id,
            kind: request.kind,
            jobAction: request.action,
            route: route,
            metadata: result.metadata,
            assetRefs: request.assetReferences,
            contextDescription: contextDescription,
            origin: request.origin,
            module: request.module
        )
        if case .storyboardOperation = request.kind {
        }
        notifyIfNeeded(
            route: route,
            request: request,
            channelLabel: "文本",
            model: result.metadata.model
        )
        let resultPayload = AIActionResult(
            request: request,
            text: textPayload,
            image: renderedImage,
            imageBase64: result.imageBase64,
            imageURL: result.imageURL,
            videoURL: result.videoURL,
            metadata: result.metadata,
            route: route
        )
        logTextResult(resultPayload)
        return resultPayload
    }

    func stream(_ request: AIActionRequest) -> AsyncThrowingStream<AIActionStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let contextDescription = contextStatusText(
                        override: request.contextSummaryOverride,
                        context: request.context
                    )
                    let sceneRequest = SceneJobRequest(
                        action: request.action,
                        fields: request.fields,
                        assetReferences: request.assetReferences,
                        channel: request.channel
                    )
                    logRequest(request: request, sceneRequest: sceneRequest)

                    let route = dependencies.currentTextRoute()
                    var accumulated = ""
                    var resolvedModel = dependencies.currentTextModelLabel()

                    let stream = dependencies.textService().stream(job: sceneRequest)
                    for try await chunk in stream {
                        if chunk.textDelta.isEmpty == false {
                            accumulated += chunk.textDelta
                            continuation.yield(.partial(chunk.textDelta))
                        }
                        if let identifier = chunk.modelIdentifier, chunk.isTerminal {
                            resolvedModel = identifier
                        } else if let identifier = chunk.modelIdentifier, resolvedModel.isEmpty {
                            resolvedModel = identifier
                        }
                    }

                    let metadata = SceneJobResult.Metadata(
                        prompt: accumulated,
                        model: resolvedModel,
                        duration: 0
                    )

                    await recordAudit(
                        jobID: sceneRequest.id,
                        kind: request.kind,
                        jobAction: request.action,
                        route: route,
                        metadata: metadata,
                        assetRefs: request.assetReferences,
                        contextDescription: contextDescription,
                        origin: request.origin,
                        module: request.module
                    )


                    notifyIfNeeded(
                        route: route,
                        request: request,
                        channelLabel: "文本",
                        model: metadata.model
                    )

                    let resultPayload = AIActionResult(
                        request: request,
                        text: accumulated,
                        image: nil,
                        imageBase64: nil,
                        imageURL: nil,
                        videoURL: nil,
                        metadata: metadata,
                        route: route
                    )
                    logTextResult(resultPayload)
                    continuation.yield(.completed(resultPayload))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func recordAudit(
        jobID: UUID,
        kind: AIActionKind,
        jobAction: SceneAction,
        route: AIRoute,
        metadata: SceneJobResult.Metadata,
        assetRefs: [String],
        contextDescription: String,
        origin: String,
        module: PromptDocument.Module?
    ) async {
        var auditMetadata: [String: String] = [
            "source": origin,
            "route": route.displayName,
            "context": contextDescription,
            "kind": "\(kind)"
        ]
        if let module {
            auditMetadata["module"] = module.id
        }
        let entry = AuditLogEntry(
            jobID: jobID,
            action: jobAction,
            promptHash: String(metadata.prompt.hashValue, radix: 16),
            assetRefs: assetRefs,
            modelVersion: metadata.model,
            metadata: auditMetadata
        )
        await dependencies.auditRepository.record(entry)
    }

    private func notifyIfNeeded(route: AIRoute, request: AIActionRequest, channelLabel: String, model: String) {
        guard request.kind != .conversation else { return }
        let text = "\(request.origin) · \(channelLabel)（\(route.displayName) · \(model)）"
        appendSystemMessage(text)
    }

    private func appendSystemMessage(_ text: String) {
        navigationStore.pendingAIChatSystemMessage = text
    }

    private func contextStatusText(override: String?, context: ChatContext?) -> String {
        if let override, override.isEmpty == false {
            return override
        }
        guard let context else {
            return "上下文：系统"
        }
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

    private func logRequest(request: AIActionRequest, sceneRequest: SceneJobRequest) {
            let route = dependencies.currentTextRoute()
        let modelOverride = request.fields["__modelOverride"]
        let modelLabel = modelOverride ?? dependencies.currentTextModelLabel()
        print(
            """
            [AIActionCenter] Request ->
            Kind: \(request.kind)
            Channel: \(request.channel.rawValue)
            Module: \(request.module?.id ?? "none")
            Context: \(request.contextSummaryOverride ?? "n/a")
            Route: \(route.displayName)
            Model: \(modelLabel)
            Fields: \(sceneRequest.fields)
            Assets: \(sceneRequest.assetReferences)
            """
        )
    }

    private func logTextResult(_ result: AIActionResult) {
        print(
            """
            [AIActionCenter] Text result <- Route: \(result.route.displayName), Model: \(result.metadata.model)
            Preview: \(result.text?.prefix(160) ?? "")
            """
        )
    }

    private func logImageResult(_ result: AIActionResult) {
        print(
            """
            [AIActionCenter] Image result <- Route: \(result.route.displayName), Model: \(result.metadata.model)
            """
        )
    }

    private func logVideoResult(_ result: AIActionResult) {
        print(
            """
            [AIActionCenter] Video result <- Route: \(result.route.displayName), Model: \(result.metadata.model), URL: \(result.videoURL?.absoluteString ?? "n/a")
            """
        )
    }

    private static func decodeImage(base64: String?) -> NSImage? {
        guard let base64, base64.isEmpty == false,
              let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return NSImage(data: data)
    }
}
