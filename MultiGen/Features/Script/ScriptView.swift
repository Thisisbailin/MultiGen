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

    @State private var highlightedProjectID: UUID?
    @State private var selectedProjectID: UUID?
    @State private var selectedEpisodeID: UUID?

    @State private var showingNewProjectSheet = false
    @State private var projectPendingDeletion: ScriptProject?
    @State private var episodePendingDeletion: (projectID: UUID, episode: ScriptEpisode)?

    @State private var exportErrorMessage: String?
    @State private var importErrorMessage: String?

    @State private var newSceneName: String = ""
    @State private var newSceneLocation: String = ""
    @State private var newSceneTime: String = ""
    @State private var showingSceneCreationSheet = false

    @State private var isImportingProject = false

    private let docxContentTypes: [UTType] = {
        if let docx = UTType(filenameExtension: "docx") {
            return [docx]
        }
        return [.data]
    }()

    private var projects: [ScriptProject] {
        store.projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var highlightedProject: ScriptProject? {
        guard let id = highlightedProjectID else { return projects.first }
        return projects.first(where: { $0.id == id }) ?? projects.first
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
        toolbarWrappedView
    }

    private var animatedContent: some View {
        contentView
        .animation(.easeInOut(duration: 0.2), value: selectedProjectID)
        .onAppear {
            navigationStore.currentScriptEpisodeID = selectedEpisodeID
            if highlightedProjectID == nil {
                highlightedProjectID = projects.first?.id
            }
        }
        .onChange(of: selectedEpisodeID) { _, newValue in
            navigationStore.currentScriptEpisodeID = newValue
        }
        .onChange(of: selectedProjectID) { _, newValue in
            if newValue == nil {
                navigationStore.currentScriptEpisodeID = nil
            }
        }
        .onChange(of: highlightedProjectID) { _, newValue in
            if newValue == nil {
                highlightedProjectID = projects.first?.id
            }
        }
        .onChange(of: projects) { _, updatedProjects in
            guard let currentProjectID = selectedProjectID else {
                highlightedProjectID = highlightedProjectID ?? updatedProjects.first?.id
                return
            }

            if updatedProjects.contains(where: { $0.id == currentProjectID }) == false {
                selectedProjectID = nil
                selectedEpisodeID = nil
            } else if let project = updatedProjects.first(where: { $0.id == currentProjectID }) {
                if let currentEpisodeID = selectedEpisodeID,
                   project.episodes.contains(where: { $0.id == currentEpisodeID }) == false {
                    selectedEpisodeID = project.orderedEpisodes.first?.id
                } else if selectedEpisodeID == nil {
                    selectedEpisodeID = project.orderedEpisodes.first?.id
                }
            }

            if let highlight = highlightedProjectID,
               updatedProjects.contains(where: { $0.id == highlight }) == false {
                highlightedProjectID = updatedProjects.first?.id
            } else if highlightedProjectID == nil {
                highlightedProjectID = updatedProjects.first?.id
            }
        }
    }

    private var sheetWrappedView: some View {
        animatedContent
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectSheet { title, synopsis, type in
                let project = store.addProject(title: title, synopsis: synopsis, type: type)
                highlightedProjectID = project.id
                selectedProjectID = project.id
                selectedEpisodeID = project.orderedEpisodes.first?.id
            }
            .frame(minWidth: 540, minHeight: 420)
        }
        .sheet(isPresented: $showingSceneCreationSheet) {
            SceneNameSheet(
                name: $newSceneName,
                location: $newSceneLocation,
                time: $newSceneTime
            ) { name, location, time in
                addScene(name: name, location: location, time: time)
            } onCancel: {
                showingSceneCreationSheet = false
            }
            .frame(minWidth: 360, minHeight: 200)
        }
        .fileImporter(
            isPresented: $isImportingProject,
            allowedContentTypes: docxContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
    }

    private var alertWrappedView: some View {
        sheetWrappedView
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
        .alert("导入失败", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { _ in importErrorMessage = nil }
        )) {
            Button("确定", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private var toolbarWrappedView: some View {
        alertWrappedView
        .toolbar {
            ToolbarItemGroup {
                if let project = selectedProject {
                    Button {
                        selectedProjectID = nil
                        selectedEpisodeID = nil
                    } label: {
                        Label("返回项目库", systemImage: "chevron.backward")
                    }

                    if selectedEpisode != nil {
                        Button {
                            newSceneName = ""
                            newSceneLocation = ""
                            newSceneTime = ""
                            showingSceneCreationSheet = true
                        } label: {
                            Label("新增场景", systemImage: "square.split.1x2")
                        }
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

                    Button(action: startImportProject) {
                        Label("导入项目", systemImage: "tray.and.arrow.down")
                    }
                }
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .automatic)
    }

    @ViewBuilder
    private var contentView: some View {
        if let project = selectedProject {
            ScriptEpisodeView(
                store: store,
                project: project,
                selectedEpisode: selectedEpisode
            )
        } else {
            ScriptOverviewView(
                store: store,
                projects: projects,
                highlightedProject: highlightedProject,
                highlightedProjectID: $highlightedProjectID,
                onOpenProject: { project in
                    selectedProjectID = project.id
                    selectedEpisodeID = project.orderedEpisodes.first?.id
                },
                onCreateProject: { showingNewProjectSheet = true },
                onImportProject: startImportProject
            )
        }
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

    private func startImportProject() {
        isImportingProject = true
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importErrorMessage = "未选择任何文件。"
                return
            }
            do {
                let importer = ScriptDocxImporter()
                let items = try importer.parseDocument(at: url)
                guard items.isEmpty == false else {
                    importErrorMessage = "未在文档中找到“第X集”标记，请检查格式。"
                    return
                }
                let projectName = url.deletingPathExtension().lastPathComponent
                let project = store.addProject(title: projectName, synopsis: "", type: items.count > 1 ? .episodic : .standalone)
                for item in items {
                    if let episode = store.addEpisode(to: project.id, number: item.episodeNumber, title: item.title, markdown: item.body) {
                        store.updateEpisode(projectID: project.id, episodeID: episode.id) { editable in
                            editable.scenes = [
                                ScriptScene(
                                    order: 1,
                                    title: "未命名场景",
                                    summary: "",
                                    body: item.body
                                )
                            ]
                        }
                    }
                }
                highlightedProjectID = project.id
                selectedProjectID = project.id
                selectedEpisodeID = store.project(id: project.id)?.orderedEpisodes.first?.id
            } catch {
                importErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    private func addScene(name: String, location: String, time: String) {
        guard let projectID = selectedProjectID, let episodeID = selectedEpisodeID else { return }
        _ = store.addScene(
            to: projectID,
            episodeID: episodeID,
            title: name,
            locationHint: location,
            timeHint: time
        )
        showingSceneCreationSheet = false
        newSceneName = ""
        newSceneLocation = ""
        newSceneTime = ""
    }
}

private struct SceneNameSheet: View {
    @Binding var name: String
    @Binding var location: String
    @Binding var time: String
    let onSubmit: (String, String, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新增场景")
                .font(.title3.bold())
            Text("输入场景名称（可选添加内/外信息及时间），将作为剧本中的场景分隔。")
                .foregroundStyle(.secondary)
            TextField("例如：咖啡馆·夜", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }
            TextField("可选：地点/内外信息（例：内景/酒吧）", text: $location)
                .textFieldStyle(.roundedBorder)
            TextField("可选：时间/氛围（例：黄昏）", text: $time)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("添加") { submit() }
            }
        }
        .padding(24)
        .frame(minWidth: 320)
    }

    private func submit() {
        onSubmit(
            name.trimmingCharacters(in: .whitespacesAndNewlines),
            location.trimmingCharacters(in: .whitespacesAndNewlines),
            time.trimmingCharacters(in: .whitespacesAndNewlines)
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
