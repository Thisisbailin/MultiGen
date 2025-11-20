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
    @Published private(set) var isGenerating = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var generatedImage: NSImage?

    func resetNotifications() {
        statusMessage = nil
        errorMessage = nil
    }

    func clearOutput() {
        generatedImage = nil
        resetNotifications()
    }

    func generateImage(
        prompt: String,
        attachments: [ImagingAttachmentPayload],
        actionCenter: AIActionCenter,
        dependencies: AppDependencies,
        navigationStore: NavigationStore,
        summary: String
    ) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            errorMessage = "请输入提示词"
            statusMessage = nil
            return
        }
        guard isGenerating == false else { return }
        isGenerating = true
        errorMessage = nil
        statusMessage = "正在使用 \(dependencies.currentTextRoute().displayName) · \(dependencies.currentTextModelLabel())"

        let request = AIActionRequest(
            kind: .imaging,
            action: .generateScene,
            channel: .text,
            fields: makeFields(prompt: trimmed, attachments: attachments),
            assetReferences: attachments.map { $0.fileName },
            module: .aiConsole,
            context: nil,
            contextSummaryOverride: summary,
            origin: "影像实验室"
        )

        var accumulated = ""
        do {
            let stream = actionCenter.stream(request)
            for try await event in stream {
                switch event {
                case .partial(let delta):
                    accumulated += delta
                    statusMessage = "正在生成…（\(accumulated.count) 字）"
                case .completed(let result):
                    let text = result.text ?? accumulated
                    if let image = try await resolveImage(from: result, fallbackText: text) {
                        generatedImage = image
                        statusMessage = "生成完成 · \(result.metadata.model) · \(result.route.displayName)"
                        navigationStore.pendingAIChatSystemMessage = "影像模块完成一次图像生成（\(result.metadata.model)）。"
                    } else {
                        generatedImage = nil
                        errorMessage = "AI 回复未包含可用的图像链接。"
                        statusMessage = nil
                    }
                }
            }
        } catch {
            generatedImage = nil
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
        isGenerating = false
    }

    private func resolveImage(from result: AIActionResult, fallbackText: String) async throws -> NSImage? {
        if let image = result.image {
            return image
        }
        if let url = extractImageURL(from: fallbackText) {
            let (data, _) = try await URLSession.shared.data(from: url)
            return NSImage(data: data)
        }
        return nil
    }

    private func extractImageURL(from text: String) -> URL? {
        let pattern = #"!\[[^\]]*\]\((.*?)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let urlRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return URL(string: String(text[urlRange]))
    }

    private func makeFields(prompt: String, attachments: [ImagingAttachmentPayload]) -> [String: String] {
        var fields: [String: String] = [
            "prompt": prompt
        ]
        if attachments.isEmpty == false {
            fields["imageAttachmentCount"] = "\(attachments.count)"
            for (index, attachment) in attachments.enumerated() {
                let key = "imageAttachment\(index + 1)"
                fields["\(key)FileName"] = attachment.fileName
                fields["\(key)Base64"] = attachment.base64Data
            }
        }
        return fields
    }
}

struct ImagingAttachmentPayload: Codable, Sendable {
    let fileName: String
    let base64Data: String
}
