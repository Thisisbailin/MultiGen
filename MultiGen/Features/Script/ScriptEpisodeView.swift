import SwiftUI
import AppKit

struct ScriptEpisodeView: View {
    @ObservedObject var store: ScriptStore
    let project: ScriptProject
    let selectedEpisode: ScriptEpisode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let episode = selectedEpisode {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(episode.displayLabel)
                                .font(.system(.title, weight: .semibold))
                            Text("更新 \(episode.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .foregroundStyle(.secondary)
                        }
                        SceneEditorList(
                            scenes: episode.scenes.sorted { $0.order < $1.order },
                            onTitleChange: { sceneID, value in
                                store.updateSceneTitle(projectID: project.id, episodeID: episode.id, sceneID: sceneID, title: value)
                            },
                            onBodyChange: { sceneID, value in
                                store.updateSceneBody(projectID: project.id, episodeID: episode.id, sceneID: sceneID, body: value)
                            },
                            onLocationChange: { sceneID, value in
                                store.updateSceneLocationHint(projectID: project.id, episodeID: episode.id, sceneID: sceneID, hint: value)
                            },
                            onTimeChange: { sceneID, value in
                                store.updateSceneTimeHint(projectID: project.id, episodeID: episode.id, sceneID: sceneID, hint: value)
                            },
                            onDelete: { sceneID in
                                store.deleteScene(projectID: project.id, episodeID: episode.id, sceneID: sceneID)
                            }
                        )
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
                } else {
                    EpisodePlaceholderView()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
    }
}

private struct EpisodePlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("暂无剧集内容")
                .font(.title3.bold())
            Text("使用工具栏“新增剧集”按钮导入或编写内容。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct SceneEditorList: View {
    let scenes: [ScriptScene]
    let onTitleChange: (UUID, String) -> Void
    let onBodyChange: (UUID, String) -> Void
    let onLocationChange: (UUID, String) -> Void
    let onTimeChange: (UUID, String) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
                SceneEditorCard(
                    order: index + 1,
                    scene: scene,
                    titleBinding: Binding(
                        get: { scene.title },
                        set: { onTitleChange(scene.id, $0) }
                    ),
                    bodyBinding: Binding(
                        get: { scene.body },
                        set: { onBodyChange(scene.id, $0) }
                    ),
                    locationBinding: Binding(
                        get: { scene.locationHint },
                        set: { onLocationChange(scene.id, $0) }
                    ),
                    timeBinding: Binding(
                        get: { scene.timeHint },
                        set: { onTimeChange(scene.id, $0) }
                    ),
                    showDelete: scenes.count > 1,
                    onDelete: { onDelete(scene.id) }
                )
                if index < scenes.count - 1 {
                    Divider()
                        .padding(.vertical, 12)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SceneEditorCard: View {
    let order: Int
    let scene: ScriptScene
    let titleBinding: Binding<String>
    let bodyBinding: Binding<String>
    let locationBinding: Binding<String>
    let timeBinding: Binding<String>
    let showDelete: Bool
    let onDelete: () -> Void
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("场景 \(order)")
                        .font(.caption)
                        .foregroundStyle(Color.secondary.opacity(0.6))
                    TextField("例如：酒吧 · 傍晚", text: titleBinding)
                        .font(.title3.weight(.semibold))
                        .textFieldStyle(.plain)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isEditing ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(isEditing ? "完成" : "编辑") {
                        isEditing.toggle()
                    }
                    .buttonStyle(.bordered)
                    if showDelete {
                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            HStack(spacing: 8) {
                if isEditing {
                    TextField("可选：地点/内外信息（例：酒吧·内）", text: locationBinding)
                        .textFieldStyle(.roundedBorder)
                    TextField("可选：时间/氛围（例：夜）", text: timeBinding)
                        .textFieldStyle(.roundedBorder)
                } else {
                    inlineHint(icon: "mappin.and.ellipse", text: scene.locationHint, placeholder: "可选：地点/内外信息（例：酒吧·内）")
                    inlineHint(icon: "clock", text: scene.timeHint, placeholder: "可选：时间/氛围（例：夜）")
                }
            }
            SceneTextEditor(text: bodyBinding)
                .frame(minHeight: 200)
                .padding(.vertical, 12)
        }
        .padding(.vertical, 14)
    }

    private func inlineHint(icon: String, text: String, placeholder: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(Color.secondary)
            Text(text.isEmpty ? placeholder : text)
                .font(.subheadline)
                .foregroundStyle(text.isEmpty ? Color.secondary.opacity(0.6) : .primary)
                .lineLimit(1)
        }
    }
}

private struct SceneTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> AutoSizingTextView {
        let textView = AutoSizingTextView()
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.string = text
        return textView
    }

    func updateNSView(_ nsView: AutoSizingTextView, context: Context) {
        if nsView.string != text {
            nsView.string = text
            nsView.invalidateIntrinsicContentSize()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? AutoSizingTextView else { return }
            text = textView.string
            textView.invalidateIntrinsicContentSize()
        }
    }
}

final class AutoSizingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let textContainer = textContainer,
              let layoutManager = layoutManager else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 80)
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: usedRect.height + textContainerInset.height * 2)
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}
