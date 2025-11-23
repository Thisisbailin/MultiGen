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
            case .character: return "角色&场景"
            case .environment: return "场景"
            case .blend: return "合成"
            case .video: return "视频"
            }
        }
    }

    @Published var selectedSegment: Segment = .character
    @Published private(set) var isGenerating = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var generatedImage: NSImage?
    @Published private(set) var generatedVideoURL: URL?
    @Published var videoDurationSeconds: Int = 4
    @Published var videoAspectRatio: String = "16:9"
    @Published var videoFPS: Int = 24

    func resetNotifications() {
        statusMessage = nil
        errorMessage = nil
    }

    func clearOutput() {
        generatedImage = nil
        generatedVideoURL = nil
        resetNotifications()
    }

    func generateImage(
        prompt: String,
        attachments: [ImagingAttachmentPayload],
        actionCenter: AIActionCenter,
        dependencies: AppDependencies,
        navigationStore: NavigationStore,
        summary: String,
        useMultimodalModel: Bool = false
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
        let isVideo = selectedSegment == .video
        let isMultimodal = useMultimodalModel && isVideo == false
        let routeLabel = isMultimodal ? dependencies.currentTextRoute().displayName : dependencies.currentImageRoute().displayName
        let modelLabel = isMultimodal ? dependencies.currentMultimodalModelLabel() : dependencies.currentImageModelLabel()
        statusMessage = "正在使用 \(routeLabel) · \(modelLabel)"

        let channel: SceneJobChannel = isVideo ? .video : (isMultimodal ? .text : .image)
        let action: SceneAction = .generateScene
        var fields = makeFields(prompt: trimmed, attachments: attachments)
        if isVideo {
            fields["videoDurationSeconds"] = "\(max(1, videoDurationSeconds))"
            fields["videoAspectRatio"] = videoAspectRatio
            fields["videoFPS"] = "\(max(1, videoFPS))"
        }
        if isMultimodal,
           let override = dependencies.configuration.relaySelectedMultimodalModel,
           override.isEmpty == false {
            fields["__modelOverride"] = override
        }
        let request = AIActionRequest(
            kind: .imaging,
            action: action,
            channel: channel,
            fields: fields,
            assetReferences: attachments.map { $0.fileName },
            module: .aiConsole,
            context: nil,
            contextSummaryOverride: summary,
            origin: "影像实验室"
        )

        if isMultimodal {
            do {
                let result = try await actionCenter.perform(request)
                let text = result.text ?? ""
                generatedVideoURL = nil
                if let image = try await resolveImage(from: result, fallbackText: text) {
                    generatedImage = image
                    statusMessage = "生成完成 · \(result.metadata.model) · \(result.route.displayName)"
                    navigationStore.pendingAIChatSystemMessage = "影像模块完成一次多模态生成（\(result.metadata.model)）。"
                } else {
                    generatedImage = nil
                    errorMessage = "多模态回复未包含可用的图像链接。"
                    statusMessage = nil
                }
            } catch {
                generatedImage = nil
                generatedVideoURL = nil
                errorMessage = error.localizedDescription
                statusMessage = nil
            }
            isGenerating = false
            return
        }

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
                    if isVideo {
                        generatedImage = nil
                        if let videoURL = result.videoURL ?? extractVideoURL(from: text) {
                            generatedVideoURL = videoURL
                            statusMessage = "视频生成完成 · \(result.metadata.model) · \(result.route.displayName)"
                            navigationStore.pendingAIChatSystemMessage = "影像模块完成一次视频生成（\(result.metadata.model)）。"
                        } else {
                            generatedVideoURL = nil
                            errorMessage = "未找到可用视频链接。"
                            statusMessage = nil
                        }
                    } else if isMultimodal {
                        generatedVideoURL = nil
                        if let image = try await resolveImage(from: result, fallbackText: text) {
                            generatedImage = image
                            statusMessage = "生成完成 · \(result.metadata.model) · \(result.route.displayName)"
                            navigationStore.pendingAIChatSystemMessage = "影像模块完成一次多模态生成（\(result.metadata.model)）。"
                        } else {
                            generatedImage = nil
                            errorMessage = "多模态回复未包含可用的图像链接。"
                            statusMessage = nil
                        }
                    } else {
                        generatedVideoURL = nil
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
            }
        } catch {
            generatedImage = nil
            generatedVideoURL = nil
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
        isGenerating = false
    }

    private func resolveImage(from result: AIActionResult, fallbackText: String) async throws -> NSImage? {
        if let image = result.image {
            return image
        }
        if let base64 = result.imageBase64,
           let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
           let image = NSImage(data: data) {
            return image
        }
        if let dataURL = result.imageURL {
            if dataURL.scheme == "data",
               let inline = extractInlineImageBase64(from: dataURL.absoluteString),
               let data = Data(base64Encoded: inline, options: .ignoreUnknownCharacters),
               let image = NSImage(data: data) {
                return image
            }
            if dataURL.scheme?.hasPrefix("http") == true {
                let (data, _) = try await URLSession.shared.data(from: dataURL)
                if let image = NSImage(data: data) { return image }
            }
        }
        if let base64Text = result.text {
            if let inline = extractInlineImageBase64(from: base64Text),
               let data = Data(base64Encoded: inline, options: .ignoreUnknownCharacters),
               let image = NSImage(data: data) {
                return image
            }
        }
        if let inline = extractInlineImageBase64(from: fallbackText),
           let data = Data(base64Encoded: inline, options: .ignoreUnknownCharacters),
           let image = NSImage(data: data) {
            return image
        }
        if let url = extractImageURL(from: fallbackText) {
            let (data, _) = try await URLSession.shared.data(from: url)
            return NSImage(data: data)
        }
        return nil
    }

    private func extractVideoURL(from text: String) -> URL? {
        let pattern = #"https?:\/\/[^\s\)]+\.mp4"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let urlRange = Range(match.range(at: 0), in: text) else {
            return nil
        }
        return URL(string: String(text[urlRange]))
    }

    private func extractImageURL(from text: String) -> URL? {
        let markdownPattern = #"!\[[^\]]*\]\((.*?)\)"#
        if let regex = try? NSRegularExpression(pattern: markdownPattern) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let urlRange = Range(match.range(at: 1), in: text) {
                let urlString = String(text[urlRange])
                return URL(string: urlString)
            }
        }
        let plainPattern = #"https?:\/\/[^\s\)]+(?:png|jpg|jpeg|gif|webp|svg)"#
        if let regex = try? NSRegularExpression(pattern: plainPattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let urlRange = Range(match.range(at: 0), in: text) {
                return URL(string: String(text[urlRange]))
            }
        }
        return nil
    }

    private func extractInlineImageBase64(from text: String) -> String? {
        let pattern = #"data:image\/[a-zA-Z0-9\+\-\.]+;base64,([A-Za-z0-9+\/=]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let dataRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[dataRange])
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
