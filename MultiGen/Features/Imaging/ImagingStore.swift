//
//  ImagingStore.swift
//  MultiGen
//
//  Created by Codex on 2025/02/15.
//

import AppKit
import Combine
import Foundation

@MainActor
final class ImagingStore: ObservableObject {
    enum Segment: String, CaseIterable, Identifiable {
        case style
        case character
        case environment
        case blend
        case video

        var id: String { rawValue }

        var title: String {
            switch self {
            case .style: return "风格"
            case .character: return "人物"
            case .environment: return "场景"
            case .blend: return "合成"
            case .video: return "视频"
            }
        }
    }

    @Published var selectedSegment: Segment = .style
    @Published var promptInput: String = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var generatedImage: NSImage?

    func resetNotifications() {
        statusMessage = nil
        errorMessage = nil
    }

    func clearOutput(resetPrompt: Bool = false) {
        generatedImage = nil
        if resetPrompt {
            promptInput = ""
        }
        resetNotifications()
    }

    func generateImage(
        dependencies: AppDependencies,
        navigationStore: NavigationStore
    ) async {
        guard promptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            errorMessage = "请输入提示词"
            statusMessage = nil
            return
        }
        guard isGenerating == false else { return }
        isGenerating = true
        errorMessage = nil
        let routeLabel = dependencies.currentImageRoute().displayName
        statusMessage = "正在使用 \(dependencies.configuration.imageModel.displayName) · \(routeLabel)"

        let request = SceneJobRequest(
            action: .generateScene,
            fields: ["prompt": promptInput],
            channel: .image
        )

        do {
            let result = try await dependencies.imageService().generateImage(for: request)
            if let base64 = result.imageBase64,
               let data = Data(base64Encoded: base64),
               let image = NSImage(data: data) {
                generatedImage = image
            } else {
                generatedImage = nil
            }

            let auditEntry = AuditLogEntry(
                jobID: request.id,
                action: request.action,
                promptHash: String(promptInput.hashValue, radix: 16),
                assetRefs: [],
                modelVersion: result.metadata.model,
                metadata: [
                    "source": "Imaging-Style-MVP",
                    "segment": selectedSegment.rawValue
                ]
            )
            await dependencies.auditRepository.record(auditEntry)
            statusMessage = "生成完成 · \(routeLabel)"
            navigationStore.pendingAIChatSystemMessage = "影像模块完成一次图像生成（\(result.metadata.model)）。"
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
        isGenerating = false
    }
}
