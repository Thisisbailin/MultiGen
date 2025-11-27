import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StyleLibraryView: View {
    @EnvironmentObject private var store: StyleLibraryStore
    @EnvironmentObject private var actionCenter: AIActionCenter
    @EnvironmentObject private var promptLibraryStore: PromptLibraryStore
    @State private var isProcessing = false
    @State private var statusMessage: String?
    @State private var previewImage: NSImage?

    private var styles: [StyleReference] {
        store.styles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if styles.isEmpty {
                AssetLibraryPlaceholderView(title: "尚未上传风格参考")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(styles) { style in
                            StyleCard(
                                style: style,
                                onAnalyze: { analyze(style) },
                                onDelete: { store.removeStyle(id: style.id) },
                                onImageTap: { image in previewImage = image }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .sheet(isPresented: Binding(get: { previewImage != nil }, set: { if $0 == false { previewImage = nil } })) {
            if let image = previewImage {
                ScrollView([.vertical, .horizontal]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
                .frame(minWidth: 480, minHeight: 360)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("风格资料库")
                    .font(.title2.bold())
                Text("上传参考图，分析得到风格提示词，后续可用于角色/场景提示词调性对齐。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                pickImage()
            } label: {
                Label("上传风格图", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing)
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]
        if panel.runModal() == .OK, let url = panel.url, let data = compressedImageData(from: url, maxDimension: 1024, quality: 0.78) {
            store.addStyle(from: data, title: url.deletingPathExtension().lastPathComponent)
        }
    }

    private func analyze(_ style: StyleReference) {
        guard isProcessing == false else { return }
        guard let data = style.imageData else {
            statusMessage = "无图片可分析"
            return
        }
        isProcessing = true
        statusMessage = "AI 正在分析风格…"
        let compressed = ensureCompressedData(data: data, maxBytes: 1_200_000)
        let base64 = compressed.base64EncodedString()
        let mime = "image/jpeg"
        let dataURI = "data:\(mime);base64,\(base64)"
        let systemPrompt = promptLibraryStore.document(for: .promptHelperStyle).content.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = """
你是一名专业生图提示词工程师。请精准反推“如何写提示词才能一比一还原生成这张图”。要求：
- 输出 200-500 字中文，直接给出可粘贴使用的生图提示词正文，勿加序号/解释/前缀/代码块。
- 覆盖：主体与场景（身份/姿态/表情/动作/视角）、服饰与配件、材质与纹理、光线方向与强度、色调与对比、构图与景别、镜头感（焦段/景深/虚化）、背景与环境细节、风格/流派/时代暗示、画质/渲染特征（如写实/插画/3D等）。
- 如果无人物，请明确描述主体与环境细节。
"""
        let fields: [String: String] = {
            var f: [String: String] = [
                "prompt": prompt,
                // 通用兼容字段，避免模型忽略图片
                "image_base64": base64,
                "imageBase64": base64,
                "image_url": dataURI,
                "image_mime": mime,
                "imageAttachmentCount": "1",
                "imageAttachment1FileName": "style-reference.jpg",
                "imageAttachment1Base64": base64
            ]
            let contentPayload: [[String: Any]] = [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": dataURI]]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: contentPayload),
               let text = String(data: data, encoding: .utf8) {
                f["openai_content"] = text
            }
            if systemPrompt.isEmpty == false {
                f["systemPrompt"] = systemPrompt
            }
            return f
        }()
        let request = AIActionRequest(
            kind: .diagnostics,
            action: .aiConsole,
            channel: .text,
            fields: fields,
            assetReferences: [],
            module: .promptHelperStyle,
            context: .general,
            contextSummaryOverride: "风格分析",
            origin: "风格资料库"
        )
        Task {
            defer {
                Task { @MainActor in isProcessing = false }
            }
            do {
                let result = try await actionCenter.perform(request)
                let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                await MainActor.run {
                    if text.isEmpty == false {
                        store.updateStyle(id: style.id) { item in
                            item.prompt = text
                        }
                        statusMessage = "分析完成，提示词已写入"
                    } else {
                        statusMessage = "AI 未返回结果"
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = "分析失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Helpers

private func compressedImageData(from url: URL, maxDimension: CGFloat = 512, quality: CGFloat = 0.72) -> Data? {
    guard let image = NSImage(contentsOf: url) else { return try? Data(contentsOf: url) }
    return compressedImageData(from: image, maxDimension: maxDimension, quality: quality)
}

private func compressedImageData(from image: NSImage, maxDimension: CGFloat = 512, quality: CGFloat = 0.72) -> Data? {
    let targetSize: NSSize
    if image.size.width > image.size.height {
        let ratio = maxDimension / image.size.width
        targetSize = NSSize(width: maxDimension, height: image.size.height * ratio)
    } else {
        let ratio = maxDimension / image.size.height
        targetSize = NSSize(width: image.size.width * ratio, height: maxDimension)
    }
    let newImage = NSImage(size: targetSize)
    newImage.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
    newImage.unlockFocus()
    guard let tiff = newImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return image.tiffRepresentation }
    return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
}

private func ensureCompressedData(data: Data, maxBytes: Int = 1_200_000) -> Data {
    if data.count <= maxBytes { return data }
    if let image = NSImage(data: data),
       let compressed = compressedImageData(from: image, maxDimension: 1024, quality: 0.7),
       compressed.count < data.count {
        return compressed
    }
    return data
}

private struct StyleCard: View {
    let style: StyleReference
    let onAnalyze: () -> Void
    let onDelete: () -> Void
    let onImageTap: (NSImage) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let data = style.imageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onTapGesture { onImageTap(image) }
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 240, height: 240)
                    .overlay(Image(systemName: "photo").font(.largeTitle))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(style.title)
                    .font(.headline)
                if style.prompt.isEmpty == false {
                    ScrollView {
                        Text(style.prompt)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(minHeight: 160, maxHeight: 260)
                } else {
                    Text("尚未分析风格")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        onAnalyze()
                    } label: {
                        Label("分析风格", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 6)
        )
    }
}
