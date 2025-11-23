//
//  StoryboardView.swift
//  MultiGen
//
//  Created by Joe on 2025/11/13.
//

import SwiftUI

struct StoryboardView: View {
    @EnvironmentObject private var navigationStore: NavigationStore
    @EnvironmentObject private var dependencies: AppDependencies
    @StateObject private var store: StoryboardDialogueStore
    @State private var exportErrorMessage: String?

    init(store: StoryboardDialogueStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                selectionSummary

                if let banner = store.bannerMessage {
                    InfoBanner(text: banner)
                }

                currentSceneSection
            }
            .padding(24)
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
        .onAppear {
            if let savedProject = navigationStore.currentStoryboardProjectID {
                store.selectProject(id: savedProject)
            }
            if let savedEpisode = navigationStore.currentStoryboardEpisodeID {
                store.selectEpisode(id: savedEpisode)
            }
            navigationStore.currentStoryboardProjectID = store.selectedProjectID
            navigationStore.currentStoryboardEpisodeID = store.selectedEpisode?.id
            navigationStore.currentStoryboardSceneID = store.selectedSceneID
            syncSceneSnapshot()
            navigationStore.storyboardAutomationHandler = store
        }
        .onReceive(store.$selectedProjectID) { projectID in
            navigationStore.currentStoryboardProjectID = projectID
        }
        .onReceive(store.$selectedEpisode) { episode in
            navigationStore.currentStoryboardEpisodeID = episode?.id
        }
        .onReceive(store.$selectedSceneID) { sceneID in
            navigationStore.currentStoryboardSceneID = sceneID
            syncSceneSnapshot()
        }
        .onReceive(store.$scenes) { _ in
            syncSceneSnapshot()
        }
        .onDisappear {
            if navigationStore.storyboardAutomationHandler === store {
                navigationStore.storyboardAutomationHandler = nil
            }
        }
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Label(store.selectedProjectDisplay, systemImage: "square.grid.2x2")
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
                .fill(Color(nsColor: .windowBackgroundColor))
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
                            Text(scene.countDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button {
                                selectNextScene()
                            } label: {
                                Label("下一个场景", systemImage: "arrow.forward.circle")
                            }
                            .buttonStyle(.bordered)
                            .disabled(store.scenes.count <= 1)
                        }
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
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                )
            } else {
                placeholder("暂无场景。请先在“剧本”模块添加场景，再回到此处生成分镜。")
            }
        }
    }

    private func toolbarContent() -> some ToolbarContent {
        ToolbarItemGroup {
            Picker("项目", selection: projectSelectionBinding) {
                ForEach(store.projects) { project in
                    Text(project.title).tag(Optional(project.id))
                }
            }
            .labelsHidden()
            .frame(width: 200)
            .disabled(store.projects.isEmpty)

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

    private var projectSelectionBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedProjectID },
            set: { store.selectProject(id: $0) }
        )
    }

    private var sceneSelectionBinding: Binding<UUID?> {
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

    private func syncSceneSnapshot() {
        if let scene = store.currentScene {
            navigationStore.currentStoryboardSceneSnapshot = StoryboardSceneContextSnapshot(
                id: scene.id,
                title: scene.title,
                order: scene.order,
                summary: scene.summary,
                body: scene.body
            )
        } else {
            navigationStore.currentStoryboardSceneSnapshot = nil
        }
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
                .fill(Color(nsColor: .windowBackgroundColor))
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
            infoRow(title: "画面描述", value: entry.fields.visualSummary.isEmpty ? entry.fields.aiPrompt : entry.fields.visualSummary)
            infoRow(title: "台词 / OS", value: entry.fields.dialogueOrOS)
            infoRow(title: "声音 / 音效", value: entry.fields.soundDesign)
            infoRow(title: "提示词", value: entry.fields.aiPrompt)

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
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .windowBackgroundColor))
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
                .textSelection(.enabled)
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
