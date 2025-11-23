import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImagingView: View {
    private enum ImageModelChoice: String, CaseIterable, Identifiable {
        case image
        case multimodal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .image: return "图像模型"
            case .multimodal: return "多模态（文本端口）"
            }
        }
    }

    @EnvironmentObject private var store: ImagingStore
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var actionCenter: AIActionCenter
    @EnvironmentObject private var navigationStore: NavigationStore
    @State private var promptText: String = ""
    @State private var attachments: [ImagingAttachmentPayload] = []
    @State private var imageModelChoice: ImageModelChoice = .image

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                segmentPicker
                contentForSelection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("影像模块 · macOS")
                .font(.system(.title, weight: .semibold))
            Text("可在本页直接输入提示并发起生成，也可继续通过左侧智能协同面板触发。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var segmentPicker: some View {
        Picker("模式", selection: $store.selectedSegment) {
            ForEach(tabSegments) { segment in
                Text(segment.title).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)
    }

    private var tabSegments: [ImagingStore.Segment] {
        [.style, .character, .video]
    }

    private var contentForSelection: some View {
        Group {
            switch store.selectedSegment {
            case .style:
                stylePlaceholder
            case .video:
                videoContent
            default:
                imageContent
            }
        }
    }

    private var imageContent: some View {
        VStack(spacing: 16) {
            composerPanel(isVideo: false)
            instructions(isVideo: false)
            resultPanel
        }
    }

    private var videoContent: some View {
        VStack(spacing: 16) {
            videoControls
            composerPanel(isVideo: true)
            instructions(isVideo: true)
            resultPanel
        }
    }

    private func instructions(isVideo: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("如何使用", systemImage: "sparkles")
                .font(.headline)
            Text(isVideo
                 ? "选择“视频”标签，设定时长/帧率/比例后，点击下方生成或在左侧智能协同面板触发。结果视频链接会出现在下方。"
                 : "在本页直接输入提示并可附加参考图片，也可在左侧智能协同面板触发。生成完成后，结果会自动展示在下方。")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func composerPanel(isVideo: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(isVideo ? "视频生成" : "图像生成", systemImage: isVideo ? "video.badge.plus" : "photo.badge.plus")
                .font(.headline)

            if isVideo == false {
                Picker("模型", selection: $imageModelChoice) {
                    ForEach(ImageModelChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $promptText)
                    .frame(minHeight: 120)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )

                if promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("请输入提示词，可结合参考图进行引导")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
            }

            attachmentSection

            HStack(spacing: 12) {
                Button {
                    startGenerate()
                } label: {
                    Label(store.isGenerating ? "生成中..." : (isVideo ? "生成视频" : "生成图像"), systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerateDisabled)

                Button {
                    promptText = ""
                    attachments.removeAll()
                    store.clearOutput()
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(promptText.isEmpty && attachments.isEmpty && store.generatedImage == nil && store.generatedVideoURL == nil)

                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("参考图片（最多 \(maxAttachmentCount) 张）", systemImage: "paperclip")
                Spacer()
                Button {
                    pickAttachments()
                } label: {
                    Label("添加图片", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(attachments.count >= maxAttachmentCount)
            }

            if attachments.isEmpty {
                Text("未添加参考图，可直接生成。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                    HStack {
                        Text(attachment.fileName)
                            .lineLimit(1)
                        Spacer()
                        Button(role: .destructive) {
                            attachments.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.footnote)
                }
            }
        }
    }

    private var videoControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("视频生成控制 (Sora/视频模型)")
                .font(.headline)
            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("时长 (秒)")
                    Stepper(value: $store.videoDurationSeconds, in: 1...20) {
                        Text("\(store.videoDurationSeconds)s")
                    }
                }
                VStack(alignment: .leading) {
                    Text("帧率")
                    Stepper(value: $store.videoFPS, in: 1...60) {
                        Text("\(store.videoFPS) fps")
                    }
                }
                VStack(alignment: .leading) {
                    Text("比例")
                    TextField("例如 16:9 或 9:16", text: $store.videoAspectRatio)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("提示：控制字段会随视频请求一起发送至中转平台（如 Sora），用于调节输出尺寸与时长。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = store.errorMessage {
                statusBanner(text: error, systemImage: "exclamationmark.triangle.fill", tint: .orange)
            } else if let status = store.statusMessage {
                statusBanner(text: status, systemImage: "checkmark.seal.fill", tint: .green)
            } else {
                statusBanner(text: "等待指令…", systemImage: "hourglass", tint: .secondary)
            }

            if let videoURL = store.generatedVideoURL {
                VStack(alignment: .leading, spacing: 8) {
                    Text("生成视频已准备好：")
                        .font(.headline)
                    Text(videoURL.absoluteString)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
            } else if let image = store.generatedImage {
                ScrollView {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                        .shadow(radius: 10)
                        .padding(.vertical, 8)
                }
                .frame(maxHeight: 440)
            } else {
                placeholderPanel(title: "等待生成", subtitle: "在本页或智能协同面板发起生成后，结果会出现在这里。")
                    .frame(maxHeight: 320)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stylePlaceholder: some View {
        placeholderPanel(
            title: "风格标签页即将上线",
            subtitle: "敬请期待，可先使用“角色&场景”或“视频”进行生成。"
        )
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func placeholderPanel(title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var isGenerateDisabled: Bool {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isGenerating
    }

    private var maxAttachmentCount: Int { 3 }

    private func pickAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        let availableSlots = maxAttachmentCount - attachments.count
        let selected = panel.urls.prefix(availableSlots)
        var newItems: [ImagingAttachmentPayload] = []
        for url in selected {
            guard let data = try? Data(contentsOf: url) else { continue }
            let payload = ImagingAttachmentPayload(
                fileName: url.lastPathComponent,
                base64Data: data.base64EncodedString()
            )
            newItems.append(payload)
        }
        attachments.append(contentsOf: newItems)
    }

    private func startGenerate() {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let summary = "影像模块 · \(store.selectedSegment.title)"
        let payloads = attachments
        let useMultimodal = store.selectedSegment != .video && imageModelChoice == .multimodal
        Task {
            await store.generateImage(
                prompt: trimmed,
                attachments: payloads,
                actionCenter: actionCenter,
                dependencies: dependencies,
                navigationStore: navigationStore,
                summary: summary,
                useMultimodalModel: useMultimodal
            )
        }
    }

    private func statusBanner(text: String, systemImage: String, tint: Color) -> some View {
        HStack {
            Image(systemName: systemImage)
            Text(text)
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(tint)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

}
