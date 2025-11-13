//
//  StoryboardView.swift
//  MultiGen
//
//  Created by Joe on 2025/11/13.
//

import SwiftUI

struct StoryboardView: View {
    @StateObject private var store: StoryboardDialogueStore
    @State private var exportErrorMessage: String?

    init(store: StoryboardDialogueStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    selectionSummary

                    if let banner = store.bannerMessage {
                        InfoBanner(text: banner)
                    }

                    currentSceneSection
                }
                .padding(24)
                .padding(.bottom, 220)
            }

            HStack {
                Spacer()
                aiComposerSection
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar(content: toolbarContent)
        .alert("错误", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { _ in store.errorMessage = nil }
        )) {
            Button("确定", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert("导出失败", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { _ in exportErrorMessage = nil }
        )) {
            Button("确定", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Label(store.selectedEpisodeDisplay, systemImage: "film")
                if let savedAt = store.lastSavedAt {
                    Label("已保存：\(savedAt.formatted(date: .numeric, time: .shortened))", systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 16) {
                Label(store.selectedSceneDisplay, systemImage: "square.stack.3d.up")
                Label(store.selectedShotDisplay, systemImage: "camera.aperture")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var currentSceneSection: some View {
        Group {
            if let scene = store.currentScene {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scene.title)
                                .font(.title2.bold())
                            if scene.summary.isEmpty == false {
                                Text(scene.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text(scene.countDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            selectNextScene()
                        } label: {
                            Label("下一个场景", systemImage: "arrow.forward.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.scenes.count <= 1)
                    }
                    Divider()
                    VStack(spacing: 14) {
                        if scene.entries.isEmpty {
                            placeholder("该场景尚无分镜，请新增或请求 AI 生成。")
                        } else {
                            ForEach(scene.entries) { entry in
                                ShotReviewCard(
                                    entry: entry,
                                    isSelected: store.selectedEntryID == entry.id,
                                    onDelete: { store.deleteEntry(entry.id) },
                                    onFocus: { store.focus(entryID: entry.id) }
                                )
                            }
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                )
            } else {
                placeholder("暂无场景。请先通过 AI 生成或点击“新增分镜”创建首个镜头。")
            }
        }
    }

    private var aiComposerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI 分镜助手", systemImage: "wand.and.stars")
                    .font(.headline)
                Spacer()
                if store.isGenerating {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("描述新增镜头或对当前镜头的调整…", text: $store.messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    OptionTag(title: "提示词模版", isOn: store.includePromptHint) {
                        store.includePromptHint.toggle()
                    }
                    OptionTag(title: "剧本摘要", isOn: store.includeScriptContext) {
                        store.includeScriptContext.toggle()
                    }
                    OptionTag(title: "分镜上下文", isOn: store.includeStoryboardContext) {
                        store.includeStoryboardContext.toggle()
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    store.sendMessage()
                } label: {
                    Label("发送 AI", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.canSend == false)

                Button {
                    store.createManualEntry()
                } label: {
                    Label("新增镜头", systemImage: "plus.square.on.square")
                }
                .buttonStyle(.bordered)
                .disabled(store.selectedEpisode == nil)

                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("模型：\(store.currentModelDisplayName)")
                    Text("线路：\(store.currentRouteDescription)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
        )
        .frame(maxWidth: 800)
    }

    private func toolbarContent() -> some ToolbarContent {
        ToolbarItemGroup {
            Picker("剧集", selection: Binding(
                get: { store.selectedEpisodeID },
                set: { store.selectEpisode(id: $0) }
            )) {
                ForEach(store.episodes) { episode in
                    Text(episode.displayLabel).tag(Optional(episode.id))
                }
            }
            .labelsHidden()
            .frame(width: 180)

            if store.scenes.isEmpty == false {
                Picker("场景", selection: sceneSelectionBinding) {
                    ForEach(store.scenes) { scene in
                        Text(scene.title).tag(Optional(scene.id))
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            if store.entriesForSelectedScene.isEmpty == false {
                Picker("镜头", selection: entrySelectionBinding) {
                    ForEach(store.entriesForSelectedScene) { entry in
                        Text("镜 \(entry.fields.shotNumber)").tag(Optional(entry.id))
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            Menu {
                ForEach(StoryboardExportFormat.allCases) { format in
                    Button(format.displayName) {
                        exportStoryboard(as: format)
                    }
                }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .disabled(store.workspace == nil || store.entries.isEmpty)
        }
    }

    private var sceneSelectionBinding: Binding<String?> {
        Binding(
            get: { store.selectedSceneID },
            set: { store.selectScene(id: $0) }
        )
    }

    private var entrySelectionBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedEntryID },
            set: { store.selectEntry(id: $0) }
        )
    }

    private func selectNextScene() {
        guard let current = store.currentScene,
              let index = store.scenes.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIndex = store.scenes.index(after: index)
        let target = nextIndex < store.scenes.count ? store.scenes[nextIndex] : store.scenes.first
        store.selectScene(id: target?.id)
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func exportStoryboard(as format: StoryboardExportFormat) {
        guard let workspace = store.workspace else {
            exportErrorMessage = "请选择剧集后再导出。"
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(workspace.episodeTitle).\(format.fileExtension)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let exporter = StoryboardExporter()
            let (data, _) = try exporter.export(workspace: workspace, format: format)
            try data.write(to: url, options: .atomic)
            store.publishInfoBanner("已导出 \(format.displayName)：\(url.lastPathComponent)")
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}

private struct ShotReviewCard: View {
    let entry: StoryboardEntry
    let isSelected: Bool
    let onDelete: () -> Void
    let onFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                tagStack
                Spacer()
                StatusBadge(status: entry.status)
            }

            Text(entry.sceneTitle)
                .font(.headline)
            if entry.sceneSummary.isEmpty == false {
                Text(entry.sceneSummary)
                    .font(.subheadline)
            }

            infoRow(title: "画面描述", value: entry.fields.aiPrompt)
            infoRow(title: "台词 / OS", value: entry.fields.dialogueOrOS)

            HStack {
                Button {
                    onFocus()
                } label: {
                    Label("查看镜头", systemImage: "viewfinder")
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .buttonStyle(.borderless)

                Spacer()
                Text("版本 \(entry.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.2)
        )
    }

    private var tagStack: some View {
        HStack(spacing: 8) {
            ShotTag("镜 \(entry.fields.shotNumber)")
            ShotTag(entry.fields.shotScale.isEmpty ? "景别待定" : entry.fields.shotScale)
            ShotTag(entry.fields.cameraMovement.isEmpty ? "运镜待定" : entry.fields.cameraMovement)
            ShotTag(entry.fields.duration.isEmpty ? "--" : entry.fields.duration)
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "（暂无内容）" : value)
                .font(.body)
        }
    }
}

private struct ShotTag: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
    }
}

private struct StatusBadge: View {
    let status: StoryboardEntryStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.18))
            )
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .draft: return .gray
        case .pendingReview: return .orange
        case .approved: return .green
        }
    }
}

private struct InfoBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
            Text(text)
                .lineLimit(2)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .foregroundStyle(.orange)
    }
}

struct StoryboardScreen: View {
    @StateObject private var store: StoryboardDialogueStore

    init(builder: @escaping () -> StoryboardDialogueStore) {
        _store = StateObject(wrappedValue: builder())
    }

    var body: some View {
        StoryboardView(store: store)
    }
}
private struct OptionTag: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                Text(title)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}
