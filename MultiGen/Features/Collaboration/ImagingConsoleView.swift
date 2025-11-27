import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImagingConsoleView: View {
    @EnvironmentObject private var actionCenter: AIActionCenter
    @EnvironmentObject private var promptLibraryStore: PromptLibraryStore

    @State private var messages: [AIChatMessage] = []
    @State private var expandedIDs: Set<UUID> = []
    @State private var inputText: String = ""
    @State private var selectedImageData: Data?
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var previewImage: NSImage?

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
                ScrollView([.vertical, .horizontal]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
                .frame(minWidth: 520, minHeight: 420)
            }
        }
    }

    // MARK: - UI

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("影像模块 · 多模态生图")
                .font(.headline)

            uploadArea

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Divider()
            specControls
            Divider()
            angleControls
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
                .disabled(isSending)
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
        guard let imageData = selectedImageData else {
            errorMessage = "请先上传参考图"
            return
        }
        let base64 = imageData.base64EncodedString()
        let mime = "image/jpeg"
        let dataURI = "data:\(mime);base64,\(base64)"
        let systemPrompt = promptLibraryStore.document(for: .imagingAssistant).content.trimmingCharacters(in: .whitespacesAndNewlines)

        let controlPrompt = buildControlPrompt()
        let finalPrompt = [controlPrompt, trimmed].filter { $0.isEmpty == false }.joined(separator: "\n")

        var fields: [String: String] = [
            "prompt": finalPrompt,
            "image_base64": base64,
            "imageBase64": base64,
            "image_url": dataURI,
            "image_mime": mime
        ]
        let contentPayload: [[String: Any]] = [
            ["type": "text", "text": finalPrompt],
            ["type": "image_url", "image_url": ["url": dataURI]]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: contentPayload),
           let text = String(data: data, encoding: .utf8) {
            fields["openai_content"] = text
        }
        if systemPrompt.isEmpty == false {
            fields["systemPrompt"] = systemPrompt
        }

        let request = AIActionRequest(
            kind: .conversation,
            action: .aiConsole,
            channel: .text,
            fields: fields,
            assetReferences: [],
            module: nil,
            context: .general,
            contextSummaryOverride: "影像模块",
            origin: "影像模块"
        )

        messages.append(AIChatMessage(role: .user, text: finalPrompt, images: imageData.toNSImageList()))
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
                    if let image = result.image {
                        images.append(image)
                    } else if let b64 = result.imageBase64,
                              let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
                              let img = NSImage(data: data) {
                        images.append(img)
                    } else if let url = result.imageURL,
                              let data = try? Data(contentsOf: url),
                              let img = NSImage(data: data) {
                        images.append(img)
                    }
                    messages.append(
                        AIChatMessage(
                            role: .assistant,
                            text: result.text ?? "",
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
