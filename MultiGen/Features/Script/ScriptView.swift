//
//  ScriptView.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ScriptView: View {
    @EnvironmentObject private var store: ScriptStore
    @EnvironmentObject private var navigationStore: NavigationStore
    @State private var selectedProjectID: UUID?
    @State private var selectedEpisodeID: UUID?
    @State private var showingNewProjectSheet = false
    @State private var projectPendingDeletion: ScriptProject?
    @State private var episodePendingDeletion: (projectID: UUID, episode: ScriptEpisode)?
    @State private var exportErrorMessage: String?

    private var projects: [ScriptProject] {
        store.projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var selectedProject: ScriptProject? {
        guard let id = selectedProjectID else { return nil }
        return projects.first(where: { $0.id == id })
    }

    private var selectedEpisode: ScriptEpisode? {
        guard let project = selectedProject else { return nil }
        if let id = selectedEpisodeID,
           let found = project.orderedEpisodes.first(where: { $0.id == id }) {
            return found
        }
        return project.orderedEpisodes.first
    }

    var body: some View {
        Group {
            if let project = selectedProject {
                ProjectDetailStage(
                    store: store,
                    project: project,
                    selectedEpisode: selectedEpisode
                )
                .transition(.opacity)
            } else {
                ProjectLibraryStage(
                    projects: projects,
                    onCreate: { showingNewProjectSheet = true },
                    onImport: { /* TODO: 导入项目 */ },
                    onSelect: { project in
                        selectedProjectID = project.id
                        selectedEpisodeID = project.orderedEpisodes.first?.id
                    }
                )
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .animation(.easeInOut(duration: 0.2), value: selectedProjectID)
        .onAppear {
            navigationStore.currentScriptEpisodeID = selectedEpisodeID
        }
        .onChange(of: selectedEpisodeID) { _, newValue in
            navigationStore.currentScriptEpisodeID = newValue
        }
        .onChange(of: selectedProjectID) { _, newValue in
            if newValue == nil {
                navigationStore.currentScriptEpisodeID = nil
            }
        }
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectSheet { title, synopsis, type in
                let project = store.addProject(title: title, synopsis: synopsis, type: type)
                selectedProjectID = project.id
                selectedEpisodeID = project.orderedEpisodes.first?.id
            }
            .frame(minWidth: 540, minHeight: 420)
        }
        .alert("删除项目？", isPresented: Binding(
            get: { projectPendingDeletion != nil },
            set: { _ in projectPendingDeletion = nil }
        )) {
            Button("删除", role: .destructive) {
                if let target = projectPendingDeletion {
                    store.removeProject(id: target.id)
                    if selectedProjectID == target.id {
                        selectedProjectID = projects.first(where: { $0.id != target.id })?.id
                        selectedEpisodeID = nil
                    }
                }
                projectPendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                projectPendingDeletion = nil
            }
        } message: {
            Text("此操作会移除项目及其全部剧集。")
        }
        .alert("删除剧集？", isPresented: Binding(
            get: { episodePendingDeletion != nil },
            set: { _ in episodePendingDeletion = nil }
        )) {
            Button("删除", role: .destructive) {
                if let target = episodePendingDeletion {
                    store.removeEpisode(projectID: target.projectID, episodeID: target.episode.id)
                    if selectedEpisodeID == target.episode.id {
                        selectedEpisodeID = store.project(id: target.projectID)?.orderedEpisodes.first?.id
                    }
                }
                episodePendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                episodePendingDeletion = nil
            }
        } message: {
            Text("该剧集的内容将被移动到废纸篓。")
        }
        .alert("导出失败", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { _ in exportErrorMessage = nil }
        )) {
            Button("确定", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .onChange(of: projects) { _, value in
            if let id = selectedProjectID,
               value.contains(where: { $0.id == id }) == false {
                selectedProjectID = nil
                selectedEpisodeID = nil
            } else if let project = selectedProject {
                if let episodeID = selectedEpisodeID,
                   project.episodes.contains(where: { $0.id == episodeID }) == false {
                    selectedEpisodeID = project.orderedEpisodes.first?.id
                } else if selectedEpisodeID == nil {
                    selectedEpisodeID = project.orderedEpisodes.first?.id
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if let project = selectedProject {
                    Button {
                        selectedProjectID = nil
                        selectedEpisodeID = nil
                    } label: {
                        Label("项目库", systemImage: "chevron.backward")
                    }

                    Menu {
                        if project.orderedEpisodes.isEmpty {
                            Text("暂无剧集")
                        } else {
                            ForEach(project.orderedEpisodes) { episode in
                                Button(episode.displayLabel) {
                                    selectedEpisodeID = episode.id
                                }
                            }
                        }
                    } label: {
                        Label(selectedEpisode?.displayLabel ?? "选择剧集", systemImage: "list.bullet.rectangle")
                    }

                    Button {
                        addEpisode(to: project)
                    } label: {
                        Label("新增剧集", systemImage: "plus")
                    }

                    Menu {
                        Button("导出 Markdown") {
                            exportEpisode(project: project, episode: selectedEpisode, as: .markdown)
                        }
                        .disabled(selectedEpisode == nil)
                        Button("导出 PDF") {
                            exportEpisode(project: project, episode: selectedEpisode, as: .pdf)
                        }
                        .disabled(selectedEpisode == nil)
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.down")
                    }

                    Button(role: .destructive) {
                        if let episode = selectedEpisode {
                            episodePendingDeletion = (project.id, episode)
                        }
                    } label: {
                        Label("删除剧集", systemImage: "trash")
                    }
                    .disabled(selectedEpisode == nil)
                } else {
                    Button {
                        showingNewProjectSheet = true
                    } label: {
                        Label("新建项目", systemImage: "square.and.pencil")
                    }

                    Menu {
                        ForEach(projects) { project in
                            Button(project.title, role: .destructive) {
                                projectPendingDeletion = project
                            }
                        }
                    } label: {
                        Label("删除项目", systemImage: "trash")
                    }
                    .disabled(projects.isEmpty)
                }
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .automatic)
    }

    private func exportEpisode(project: ScriptProject, episode: ScriptEpisode?, as type: ScriptExportType) {
        guard let episode else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(project.title)-\(episode.displayLabel).\(type.fileExtension)"
        panel.allowedContentTypes = [type.contentType]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try type.data(for: episode)
                try data.write(to: url)
            } catch {
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    private func addEpisode(to project: ScriptProject) {
        if let episode = store.addEpisode(to: project.id, number: nil, title: "", markdown: "") {
            selectedEpisodeID = episode.id
        }
    }
}

private struct ProjectLibraryStage: View {
    let projects: [ScriptProject]
    let onCreate: () -> Void
    let onImport: () -> Void
    let onSelect: (ScriptProject) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 18)], spacing: 18) {
                        ForEach(projects) { project in
                            ProjectCard(project: project) {
                                onSelect(project)
                            }
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("剧本项目库")
                    .font(.largeTitle.bold())
                Text("按项目管理短片与多集剧本，可随时进入项目详情。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    onCreate()
                } label: {
                    Label("新建项目", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onImport()
                } label: {
                    Label("导入项目", systemImage: "tray.and.arrow.down")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("当前没有剧本项目")
                .font(.title3.bold())
            Text("点击“新建项目”开始导入剧本。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

private struct ProjectDetailStage: View {
    @ObservedObject var store: ScriptStore
    let project: ScriptProject
    let selectedEpisode: ScriptEpisode?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let episode = selectedEpisode {
                VStack(alignment: .leading, spacing: 6) {
                    Text(episode.displayLabel)
                        .font(.system(.title, weight: .semibold))
                    Text("更新 \(episode.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                EpisodeEditorView(
                    markdown: bindingForMarkdown(of: episode),
                    placeholder: "在此编写 \(episode.displayLabel) 的剧本正文（Markdown）…"
                )
                scenesBlock(for: episode)
            } else {
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
    }

    private func bindingForMarkdown(of episode: ScriptEpisode) -> Binding<String> {
        Binding(
            get: {
                store.project(id: project.id)?
                    .episodes.first(where: { $0.id == episode.id })?.markdown ?? ""
            },
            set: { newValue in
                store.updateEpisode(projectID: project.id, episodeID: episode.id) { editable in
                    editable.markdown = newValue
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    editable.synopsis = trimmed.isEmpty ? "" : String(trimmed.prefix(240))
                }
            }
        )
    }

    @ViewBuilder
    private func scenesBlock(for episode: ScriptEpisode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("场景概览")
                .font(.headline)
            if episode.scenes.isEmpty {
                Text("尚未拆分场景，后续可通过 AI 自动生成。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(episode.scenes) { scene in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(scene.order). \(scene.title)")
                                    .font(.subheadline.weight(.semibold))
                                if scene.summary.isEmpty == false {
                                    Text(scene.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(.top, 12)
    }
}

private struct EpisodeEditorView: View {
    @Binding var markdown: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $markdown)
                .font(.body.monospaced())
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            if markdown.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}



private struct ProjectCard: View {
    let project: ScriptProject
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(project.title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "arrow.forward.circle.fill")
                        .foregroundStyle(.secondary)
                }
                Text("\(project.type.displayName) · \(project.episodes.count) 集 · 更新 \(project.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(project.synopsis.isEmpty ? "暂无简介" : project.synopsis)
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
                if project.tags.isEmpty == false {
                    HStack(spacing: 6) {
                        ForEach(project.tags.prefix(3), id: \.self) { tag in
                            Tag(tag)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct Tag: View {
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

private struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var synopsis: String = ""
    @State private var projectType: ScriptProject.ProjectType = .standalone
    var onSave: (String, String, ScriptProject.ProjectType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建项目")
                .font(.title2.bold())
            TextField("项目名称", text: $title)
                .textFieldStyle(.roundedBorder)
            Picker("项目类型", selection: $projectType) {
                ForEach(ScriptProject.ProjectType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            TextEditor(text: $synopsis)
                .frame(minHeight: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2))
                )
                .overlay(alignment: .topLeading) {
                    if synopsis.isEmpty {
                        Text("项目简介（可选）")
                            .font(.caption)
                            .padding(8)
                            .foregroundStyle(.secondary)
                    }
                }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("创建") {
                    onSave(title, synopsis, projectType)
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
    }
}

private enum ScriptExportType {
    case markdown
    case pdf

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .pdf: return "pdf"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown: return .plainText
        case .pdf: return .pdf
        }
    }

    func data(for episode: ScriptEpisode) throws -> Data {
        switch self {
        case .markdown:
            guard let data = episode.markdown.data(using: .utf8) else {
                throw NSError(domain: "ScriptExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法编码为 UTF-8"])
            }
            return data
        case .pdf:
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
            textView.string = episode.markdown
            return textView.dataWithPDF(inside: textView.bounds)
        }
    }
}
