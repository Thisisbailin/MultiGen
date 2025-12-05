import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImagingConsoleView: View {
    @EnvironmentObject private var configuration: AppConfiguration
    @EnvironmentObject private var actionCenter: AIActionCenter
    @EnvironmentObject private var promptLibraryStore: PromptLibraryStore

    @State private var messages: [AIChatMessage] = []
    @State private var expandedIDs: Set<UUID> = []
    @State private var inputText: String = ""
    @State private var selectedImageData: Data?
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var previewImage: NSImage?
    @State private var lastRequestPrompt: String = ""
    @State private var lastRequestModelLabel: String = ""
    @State private var lastRequestTimestamp: Date?
    @State private var lastSentImageData: Data?

    // 规格控制
    @State private var imageCount: Int = 1
    @State private var aspectRatio: AspectRatioOption = .r169
    @State private var resolution: ResolutionOption = .r1k

    // 角度控制
    @State private var rotation: Double = 0
    @State private var shotScale: ShotScale = .medium
    @State private var focusStyle: FocusStyle = .standard
    @State private var tilt: TiltStyle = .level

    var body: some View {
        HStack(spacing: 12) {
            leftPanel
                .frame(width: 320)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))

            VStack(spacing: 10) {
                ChatMessageList(
                    messages: messages,
                    expandedIDs: $expandedIDs,
                    onImageTap: { img in previewImage = img }
                )
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))

                inputBar
            }
        }
        .padding(12)
        .sheet(isPresented: Binding(get: { previewImage != nil }, set: { if $0 == false { previewImage = nil } })) {
            if let image = previewImage {
                ImagePreviewSheet(image: image) { previewImage = nil }
            }
        }
    }

    // MARK: - UI

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("影像模块 · 多模态生图")
                .font(.headline)

            uploadArea
            statusCard

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Divider()
            specControls
            Divider()
            angleControls
            requestSummaryCard
        }
    }

    private var uploadArea: some View {
        VStack(spacing: 8) {
            if let data = selectedImageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                    .foregroundColor(.secondary)
                    .frame(height: 180)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title)
                            Text("上传参考图（必选）")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    )
            }
            HStack {
                Button(action: pickImage) {
                    Label(selectedImageData == nil ? "选择图片" : "重新选择", systemImage: "paperclip")
                }
                .buttonStyle(.bordered)
                if selectedImageData != nil {
                    Button(role: .destructive) { selectedImageData = nil } label: {
                        Label("移除", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var specControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("规格控制")
                .font(.subheadline.bold())
            HStack {
                Stepper(value: $imageCount, in: 1...4) {
                    Text("生成张数：\(imageCount)")
                }
                .help("生成几张图")
            }
            Picker("比例", selection: $aspectRatio) {
                ForEach(AspectRatioOption.allCases, id: \._id) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            Picker("分辨率", selection: $resolution) {
                ForEach(ResolutionOption.allCases, id: \._id) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var angleControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("角度与镜头")
                .font(.subheadline.bold())
            VStack(alignment: .leading) {
                Text("旋转：\(Int(rotation))°")
                Slider(value: $rotation, in: -90...90, step: 5)
                    .help("镜头向左/右旋转")
            }
            Picker("景别", selection: $shotScale) {
                ForEach(ShotScale.allCases, id: \._id) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker("景深", selection: $focusStyle) {
                ForEach(FocusStyle.allCases, id: \._id) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker("俯仰", selection: $tilt) {
                ForEach(TiltStyle.allCases, id: \._id) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var statusCard: some View {
        let currentPrompt = makeFinalPrompt(userText: inputText.trimmingCharacters(in: .whitespacesAndNewlines))
        let ready = missingSetupReason == nil && selectedImageData != nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(ready ? "准备就绪" : "待完善", systemImage: ready ? "checkmark.shield" : "exclamationmark.triangle")
                    .foregroundStyle(ready ? .green : .orange)
                Spacer()
                if isSending {
                    ProgressView().controlSize(.small)
                }
            }
            if let missing = missingSetupReason {
                Text(missing).font(.caption).foregroundStyle(.secondary)
            } else if selectedImageData == nil {
                Text("请上传参考图后再发送。").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("模型：\(configuration.relaySelectedTextModel ?? "未配置") · 即将发送多模态请求")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if ready && currentPrompt.isEmpty == false {
                Text("请求摘要：\(currentPrompt)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }

    private var requestSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("请求追踪")
                    .font(.subheadline.bold())
                Spacer()
                if let ts = lastRequestTimestamp {
                    Text(ts.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if lastRequestPrompt.isEmpty {
                Text("尚未发送请求，上传参考图并填写提示词后点击发送。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("模型：\(lastRequestModelLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lastRequestPrompt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("提示词（描述需要保留或微调的点，默认保持原图其它细节不变）")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $inputText)
                    .frame(minHeight: 60, maxHeight: 120)
                    .padding(6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.secondary.opacity(0.2)))
                .onSubmit { send() }
                .submitLabel(.send)
            Button(action: send) {
                if isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || canSend == false)
            }
        }
    }

    // MARK: - Actions

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .heic]
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            selectedImageData = ensureCompressedData(data: data, maxBytes: 900_000)
        }
    }

    private func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSending == false else { return }
        if let missing = missingSetupReason {
            errorMessage = missing
            return
        }
        guard let imageData = selectedImageData else {
            errorMessage = "请先上传参考图"
            return
        }
        let base64 = imageData.base64EncodedString()
        let mime = "image/jpeg"
        let dataURI = "data:\(mime);base64,\(base64)"
        let systemPrompt = promptLibraryStore.document(for: .imagingAssistant).content.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalPrompt = makeFinalPrompt(userText: trimmed)

        var fields = AIChatRequestBuilder.makeFields(
            prompt: finalPrompt,
            context: .general,
            module: .imagingAssistant,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
        )
        // 附件与 OpenAI 样式内容，复用主页多模态字段
        fields["image_base64"] = base64
        fields["imageBase64"] = base64
        fields["image_url"] = dataURI
        fields["image_mime"] = mime
        let contentPayload: [[String: Any]] = [
            ["type": "text", "text": finalPrompt],
            ["type": "image_url", "image_url": ["url": dataURI]]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: contentPayload),
           let text = String(data: data, encoding: .utf8) {
            fields["openai_content"] = text
        }

        let request = AIActionRequest(
            kind: .conversation,
            action: .aiConsole,
            channel: .text,
            fields: fields,
            assetReferences: [],
            module: .imagingAssistant,
            context: .general,
            contextSummaryOverride: "影像模块",
            origin: "影像模块"
        )

        messages.append(AIChatMessage(role: .user, text: finalPrompt, images: imageData.toNSImageList()))
        lastRequestPrompt = finalPrompt
        lastRequestModelLabel = configuration.relaySelectedTextModel ?? "未配置模型"
        lastRequestTimestamp = Date()
        lastSentImageData = imageData
        isSending = true
        errorMessage = nil
        inputText = ""

        Task {
            defer { Task { @MainActor in isSending = false } }
            do {
                let result = try await actionCenter.perform(request)
                await MainActor.run {
                    let detail = "Model: \(result.metadata.model)"
                    var images: [NSImage] = []
                    var generatedData: Data?

                    if let image = result.image {
                        images.append(image)
                        generatedData = image.tiffRepresentation
                    } else if let b64 = result.imageBase64,
                              let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
                              let img = NSImage(data: data) {
                        images.append(img)
                        generatedData = data
                    } else if let url = result.imageURL,
                              let data = try? Data(contentsOf: url),
                              let img = NSImage(data: data) {
                        images.append(img)
                        generatedData = data
                    }

                    let baseText = sanitizeDisplayText(result.text ?? "")
                    var notes: [String] = []
                    if let generatedData, let original = lastSentImageData, generatedData == original {
                        notes.append("模型可能回显了参考图，未检测到改动。")
                    }
                    if images.isEmpty && baseText.isEmpty {
                        notes.append("模型未返回图片或文本，请检查提示词或模型支持情况。")
                    }
                    let combinedText = ([baseText] + notes).filter { $0.isEmpty == false }.joined(separator: "\n")

                    messages.append(
                        AIChatMessage(
                            role: .assistant,
                            text: combinedText.isEmpty ? "（无文本返回）" : combinedText,
                            detail: detail,
                            images: images
                        )
                    )
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    messages.append(AIChatMessage(role: .assistant, text: "错误：\(error.localizedDescription)", detail: nil))
                }
            }
        }
    }

    private func makeFinalPrompt(userText: String) -> String {
        let controlPrompt = buildControlPrompt()
        return [controlPrompt, userText].filter { $0.isEmpty == false }.joined(separator: "\n")
    }

    private var canSend: Bool {
        missingSetupReason == nil && selectedImageData != nil
    }

    private var missingSetupReason: String? {
        if configuration.relayAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "未配置中转 API Key，请先在设置中填写。"
        }
        if (configuration.relaySelectedTextModel ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "未选择文本模型，请先在设置中选择。"
        }
        return nil
    }

    private func buildControlPrompt() -> String {
        let sizeText = "规格：生成\(imageCount)张，比例 \(aspectRatio.label)，分辨率 \(resolution.label)"
        let angleText = "镜头：旋转 \(Int(rotation))°，景别 \(shotScale.label)，景深 \(focusStyle.label)，俯仰 \(tilt.label)"
        let safety = "除上述调整外，严格保持参考图的主体、构图、色调与细节不变。"
        return [sizeText, angleText, safety].joined(separator: "\n")
    }
}

// MARK: - Options

private enum AspectRatioOption: CaseIterable {
    case r11, r43, r169, r916

    var label: String {
        switch self {
        case .r11: return "1:1"
        case .r43: return "4:3"
        case .r169: return "16:9"
        case .r916: return "9:16"
        }
    }

    var _id: String { label }
}

private enum ResolutionOption: CaseIterable {
    case r512
    case r1k
    case r2k

    var label: String {
        switch self {
        case .r512: return "512px"
        case .r1k: return "1K"
        case .r2k: return "2K"
        }
    }

    var _id: String { label }
}

private enum ShotScale: CaseIterable {
    case long, medium, close, extremeClose

    var label: String {
        switch self {
        case .long: return "远景"
        case .medium: return "中景"
        case .close: return "近景"
        case .extremeClose: return "特写"
        }
    }

    var _id: String { label }
}

private enum FocusStyle: CaseIterable {
    case deep, standard, shallow

    var label: String {
        switch self {
        case .deep: return "深景"
        case .standard: return "标准"
        case .shallow: return "浅景"
        }
    }

    var _id: String { label }
}

private enum TiltStyle: CaseIterable {
    case up, level, down

    var label: String {
        switch self {
        case .up: return "仰拍"
        case .level: return "平视"
        case .down: return "俯拍"
        }
    }

    var _id: String { label }
}

// MARK: - Helpers

private extension Data {
    func toNSImageList() -> [NSImage] {
        guard let img = NSImage(data: self) else { return [] }
        return [img]
    }
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

private func sanitizeDisplayText(_ text: String) -> String {
    // 去除 data URI/base64 等不可视巨大内容，保留可读文字/URL
    let pattern = #"data:image\/[a-zA-Z0-9.+-]+;base64,[A-Za-z0-9+/=]+"#
    let regex = try? NSRegularExpression(pattern: pattern, options: [])
    let range = NSRange(location: 0, length: (text as NSString).length)
    let stripped = regex?.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "[图片数据已省略]") ?? text
    let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    // 避免超长文本影响布局
    let limit = 2000
    if trimmed.count > limit {
        let prefix = trimmed.prefix(limit)
        return "\(prefix)…（已截断）"
    }
    return trimmed
}
