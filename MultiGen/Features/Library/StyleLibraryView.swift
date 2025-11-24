import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StyleLibraryView: View {
    @EnvironmentObject private var store: StyleLibraryStore
    @EnvironmentObject private var actionCenter: AIActionCenter
    @EnvironmentObject private var promptLibraryStore: PromptLibraryStore
    @State private var isProcessing = false
    @State private var statusMessage: String?

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
                                onDelete: { store.removeStyle(id: style.id) }
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
        let base64 = ensureCompressedData(data: data, maxBytes: 1_200_000).base64EncodedString()
        let systemPrompt = promptLibraryStore.document(for: .promptHelperStyle).content.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = """
请根据参考图直接详细描绘画面本身，输出 300-500 字中文提示词，用逗号或顿号串联短语，覆盖主体/场景、外观细节、光线方向与质感、色调对比、材质纹理、构图/景别/镜头感、时代/流派/风格暗示。如无人物请说明“无人物”。只输出正文，不要解释或代码块。
"""
        let fields: [String: String] = {
            var f: [String: String] = [
                "prompt": prompt,
                // 同时提供兼容字段，避免模型忽略图片
                "imageBase64": base64,
                "imageAttachmentCount": "1",
                "imageAttachment1FileName": "style-reference.jpg",
                "imageAttachment1Base64": base64
            ]
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let data = style.imageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 240)
                    .overlay(Image(systemName: "photo").font(.largeTitle))
            }
            Text(style.title)
                .font(.headline)
            if style.prompt.isEmpty == false {
                ScrollView {
                    Text(style.prompt)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 140, maxHeight: 260)
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 6)
        )
    }
}
