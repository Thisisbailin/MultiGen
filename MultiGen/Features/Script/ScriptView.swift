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
    @EnvironmentObject private var actionCenter: AIActionCenter
    @EnvironmentObject private var promptLibraryStore: PromptLibraryStore
    @EnvironmentObject private var storyboardStore: StoryboardStore
    @EnvironmentObject private var navigationStore: NavigationStore

    @State private var selectedProjectID: UUID?
    @State private var selectedEpisodeID: UUID?
    @State private var isEpisodeView = false
    @State private var isOverviewEditing = false

    @State private var projectPendingDeletion: ScriptProject?
    @State private var episodePendingDeletion: (projectID: UUID, episode: ScriptEpisode)?

    @State private var exportErrorMessage: String?
    @State private var importErrorMessage: String?

    @State private var newSceneName: String = ""
    @State private var newSceneLocation: String = ""
    @State private var newSceneTime: String = ""
    @State private var showingSceneCreationSheet = false

    @State private var isImportingProject = false
    @State private var importInProgress = false
    @State private var importProgressMessage = "正在准备导入…"
    @State private var showingBatchStoryboardWizard = false
    @State private var batchFlow: BatchStoryboardFlowStore?
    @State private var showingImportOverwriteConfirm = false
    @State private var pendingImportPayload: ScriptImportPayload?

    private let docxContentTypes: [UTType] = {
        var types: [UTType] = []
        if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
        if let doc = UTType(filenameExtension: "doc") { types.append(doc) }
        if let pages = UTType(filenameExtension: "pages") { types.append(pages) }
        if let txt = UTType(filenameExtension: "txt") { types.append(txt) }
        if let mw = UTType("com.microsoft.word.doc") {
            types.append(mw)
        }
        if let mwx = UTType("org.openxmlformats.wordprocessingml.document") {
            types.append(mwx)
        }
        return types
    }()

    private var projects: [ScriptProject] {
        store.containers
            .compactMap { container in
                if let script = container.script {
                    return script
                }
                return store.ensureScript(projectID: container.id, type: .standalone)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
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
        ScrollView {
            contentView
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .scrollIndicators(.automatic)
        .animation(.easeInOut(duration: 0.2), value: selectedProjectID)
        .onAppear(perform: hydrateSelectionFromNavigation)
        .onChange(of: selectedEpisodeID) { _, newValue in
            navigationStore.currentScriptEpisodeID = newValue
        }
        .onChange(of: selectedProjectID) { _, newValue in
            navigationStore.currentScriptProjectID = newValue
            if let id = newValue {
                _ = store.ensureScript(projectID: id, type: .standalone)
            }
            if newValue == nil {
                navigationStore.currentScriptEpisodeID = nil
            }
            isEpisodeView = false
            isOverviewEditing = false
        }
        .onChange(of: projects) { _, updatedProjects in
            guard let currentProjectID = selectedProjectID else {
                if let first = updatedProjects.first?.id {
                    selectedProjectID = first
                    selectedEpisodeID = updatedProjects.first?.orderedEpisodes.first?.id
                }
                isEpisodeView = false
                isOverviewEditing = false
                return
            }

            if updatedProjects.contains(where: { $0.id == currentProjectID }) == false {
                selectedProjectID = nil
                selectedEpisodeID = nil
                isEpisodeView = false
                isOverviewEditing = false
            } else if let project = updatedProjects.first(where: { $0.id == currentProjectID }) {
                if let currentEpisodeID = selectedEpisodeID,
                   project.episodes.contains(where: { $0.id == currentEpisodeID }) == false {
                    selectedEpisodeID = project.orderedEpisodes.first?.id
                } else if selectedEpisodeID == nil {
                    selectedEpisodeID = project.orderedEpisodes.first?.id
                }
            }
        }
        .onChange(of: navigationStore.currentScriptProjectID) { _, newValue in
            guard let newValue else { return }
            if selectedProjectID != newValue {
                selectedProjectID = newValue
                selectedEpisodeID = store.project(id: newValue)?.orderedEpisodes.first?.id
            }
        }
        .onChange(of: isEpisodeView) { _, newValue in
            if newValue {
                isOverviewEditing = false
            }
        }
    }

    private var sheetWrappedView: some View {
        animatedContent
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
        .sheet(isPresented: $importInProgress) {
            VStack(spacing: 16) {
                ProgressView()
                Text(importProgressMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(minWidth: 320, minHeight: 200)
        }
        .sheet(isPresented: $showingBatchStoryboardWizard, onDismiss: { batchFlow = nil }) {
            if let flow = ensureBatchFlow() {
                BatchStoryboardWizardView(flow: flow)
                    .frame(minWidth: 880, minHeight: 640)
            } else {
                Text("请选择项目后再使用批量分镜功能。")
                    .padding()
            }
        }
        .confirmationDialog(
            "覆盖当前剧本？",
            isPresented: $showingImportOverwriteConfirm,
            titleVisibility: .visible
        ) {
            Button("覆盖当前项目的剧本", role: .destructive) {
                if let payload = pendingImportPayload {
                    Task { await applyImportedScript(payload) }
                }
            }
            Button("取消", role: .cancel) {
                pendingImportPayload = nil
            }
        } message: {
            Text("该项目已存在剧本内容，导入将清空并覆盖当前剧本。")
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
            if isEpisodeView {
                ToolbarItem(placement: .navigation) {
                    Button {
                        isEpisodeView = false
                    } label: {
                        Label("返回概览", systemImage: "chevron.backward")
                    }
                }
            }
            ToolbarItemGroup {
                if let project = selectedProject {
                    if isEpisodeView == false {
                        Button {
                            withAnimation(.spring()) {
                                if isOverviewEditing {
                                    isOverviewEditing = false
                                } else {
                                    isOverviewEditing = true
                                }
                            }
                        } label: {
                            Image(systemName: isOverviewEditing ? "checkmark.circle.fill" : "pencil.circle")
                        }
                    }

                    if isEpisodeView, selectedEpisode != nil {
                        Button {
                            newSceneName = ""
                            newSceneLocation = ""
                            newSceneTime = ""
                            showingSceneCreationSheet = true
                        } label: {
                            Label("新增场景", systemImage: "square.split.1x2")
                        }
                    }

                    if isEpisodeView {
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
                        .disabled(selectedEpisode == nil)

                        Button {
                            startImportScriptIntoSelectedProject()
                        } label: {
                            Label("导入剧本", systemImage: "tray.and.arrow.down")
                        }

                        if let batchProject = selectedProject {
                            Button {
                                batchFlow = BatchStoryboardFlowStore(
                                    project: batchProject,
                                    promptLibraryStore: promptLibraryStore,
                                    actionCenter: actionCenter,
                                    storyboardStore: storyboardStore
                                )
                                showingBatchStoryboardWizard = true
                            } label: {
                                Label("批量转写分镜", systemImage: "film.stack")
                            }
                        }
                    }

                    if isEpisodeView {
                        Divider()
                        Menu {
                            Button("导出 Markdown") {
                                exportEpisode(project: project, episode: selectedEpisode, as: .markdown)
                            }
                            .disabled(selectedEpisode == nil)
                            Button("导出 PDF") {
                                exportEpisode(project: project, episode: selectedEpisode, as: .pdf)
                            }
                            .disabled(selectedEpisode == nil)
                            Divider()
                            Button("导出剧本（Word）") {
                                exportProjectAsWord(project)
                            }
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
                    }
                } else {
                    Button {
                        navigationStore.selection = .writing
                    } label: {
                        Label("前往写作创建项目", systemImage: "arrow.right.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if let project = selectedProject {
            VStack(alignment: .leading, spacing: 14) {
                if isEpisodeView == false {
                    ResumeHeader(
                        project: project,
                        episode: selectedEpisode,
                        onResume: {
                            if selectedEpisodeID == nil {
                                selectedEpisodeID = project.orderedEpisodes.first?.id
                            }
                            isOverviewEditing = false
                            isEpisodeView = true
                        }
                    )
                    ScriptProjectDetailPanel(
                        store: store,
                        project: project,
                        accentColor: Color(nsColor: .windowBackgroundColor),
                        isEditing: $isOverviewEditing
                    )
                } else {
                    ScriptEpisodeView(
                        store: store,
                        project: project,
                        selectedEpisode: selectedEpisode
                    )
                }
            }
        } else {
            ProjectSelectionPlaceholder(
                title: "暂无选中项目",
                description: "请在主页选择项目容器，或前往写作模块创建新项目。",
                buttonTitle: "前往主页",
                onCreate: { navigationStore.selection = .home }
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

    private func startImportScriptIntoSelectedProject() {
        guard selectedProjectID != nil else {
            importErrorMessage = "请先选择项目，再导入剧本。"
            return
        }
        isImportingProject = true
    }

    private func exportProjectAsWord(_ project: ScriptProject) {
        let panel = NSSavePanel()
        let docType = UTType(filenameExtension: "doc") ?? .rtf
        panel.allowedContentTypes = [docType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(project.title).doc"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let builder = ScriptProjectWordBuilder()
        do {
            let text = builder.makeDocument(for: project)
            let attributed = NSAttributedString(string: text)
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.docFormat]
            )
            try data.write(to: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            importErrorMessage = nil
            guard let targetProjectID = selectedProjectID else {
                importErrorMessage = "请先选择项目，再导入剧本。"
                return
            }
            guard let url = urls.first else {
                importErrorMessage = "未选择任何文件。"
                return
            }
            importInProgress = true
            importProgressMessage = "正在读取文档…"
            Task {
                do {
                    let importer = ScriptDocxImporter()
                    let payload = try importer.parseDocument(at: url)
                    await MainActor.run {
                        importProgressMessage = "校验当前剧本…"
                    }
                    let episodesOK = payload.episodes.isEmpty == false
                    guard episodesOK else {
                        await MainActor.run {
                            importErrorMessage = "未在文档中找到“第X集”标记，请检查格式。"
                            importInProgress = false
                        }
                        return
                    }
                    if scriptHasContent(projectID: targetProjectID) {
                        await MainActor.run {
                            pendingImportPayload = payload
                            importInProgress = false
                            showingImportOverwriteConfirm = true
                        }
                        return
                    }
                    await applyImportedScript(payload, projectID: targetProjectID)
                } catch {
                    await MainActor.run {
                        importErrorMessage = error.localizedDescription
                        importInProgress = false
                    }
                }
            }
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    private func scriptHasContent(projectID: UUID) -> Bool {
        guard let script = store.project(id: projectID) else { return false }
        let hasEpisodes = script.episodes.contains { episode in
            episode.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        return hasEpisodes || script.synopsis.isEmpty == false || script.mainCharacters.isEmpty == false || script.keyScenes.isEmpty == false
    }

    private func hydrateSelectionFromNavigation() {
        if let savedProject = navigationStore.currentScriptProjectID,
           projects.contains(where: { $0.id == savedProject }) {
            selectedProjectID = savedProject
        } else {
            selectedProjectID = projects.first?.id
        }

        if let savedEpisode = navigationStore.currentScriptEpisodeID,
           let project = projects.first(where: { $0.episodes.contains(where: { $0.id == savedEpisode }) }) {
            selectedProjectID = project.id
            selectedEpisodeID = savedEpisode
        } else if selectedEpisodeID == nil, let project = selectedProject {
            selectedEpisodeID = project.orderedEpisodes.first?.id
        }

        if let current = selectedProjectID {
            navigationStore.currentScriptProjectID = current
            if navigationStore.currentScriptEpisodeID == nil {
                navigationStore.currentScriptEpisodeID = store.project(id: current)?.orderedEpisodes.first?.id
            }
        }
    }

    private func applyImportedScript(_ payload: ScriptImportPayload, projectID: UUID? = nil) async {
        let targetID = projectID ?? selectedProjectID
        guard let targetProjectID = targetID else { return }
        await MainActor.run {
            importProgressMessage = "正在写入当前项目…"
            importInProgress = true
        }
        let synopsisOK = payload.synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let charactersOK = payload.characters.isEmpty == false
        let outlinesOK = payload.outlines.isEmpty == false

        await MainActor.run {
            store.ensureScript(projectID: targetProjectID, type: payload.episodes.count > 1 ? .episodic : .standalone)
            store.updateProject(id: targetProjectID) { editable in
                editable.synopsis = payload.synopsis
                editable.notes = payload.synopsis
                editable.mainCharacters = payload.characters
                editable.keyScenes = payload.episodes.flatMap { $0.scenes }.map {
                    ProjectSceneProfile(
                        id: UUID(),
                        name: $0.title,
                        description: $0.body
                    )
                }
                editable.episodeOutlines = payload.outlines
                editable.type = payload.episodes.count > 1 ? .episodic : .standalone
                editable.productionStartDate = editable.productionStartDate ?? Date()
                editable.productionTasks = []
                editable.episodes = []
            }
        }

        for (idx, item) in payload.episodes.enumerated() {
            await MainActor.run {
                importProgressMessage = "导入第 \(item.episodeNumber) 集（\(idx + 1)/\(payload.episodes.count)）…"
            }
            let episodeMarkdown: String
            if item.scenes.isEmpty {
                episodeMarkdown = item.body
            } else {
                episodeMarkdown = item.scenes
                    .map { $0.body }
                    .joined(separator: "\n\n")
            }

            if let episode = await MainActor.run(body: {
                store.addEpisode(to: targetProjectID, number: item.episodeNumber, title: item.title, markdown: episodeMarkdown)
            }) {
                let scenes: [ScriptScene]
                if item.scenes.isEmpty {
                    scenes = [
                        ScriptScene(
                            order: 1,
                            title: "未命名场景",
                            summary: "",
                            body: item.body
                        )
                    ]
                } else {
                    scenes = item.scenes.map { scene in
                        ScriptScene(
                            order: scene.index,
                            title: scene.title,
                            summary: "",
                            body: scene.body,
                            locationHint: scene.locationHint,
                            timeHint: scene.timeHint
                        )
                    }
                }
                await MainActor.run {
                    store.updateEpisode(projectID: targetProjectID, episodeID: episode.id) { editable in
                        editable.scenes = scenes
                    }
                }
            }
        }

        await MainActor.run {
            pendingImportPayload = nil
            selectedProjectID = targetProjectID
            selectedEpisodeID = store.project(id: targetProjectID)?.orderedEpisodes.first?.id
            importInProgress = false
            importProgressMessage = "导入完成：简介\(synopsisOK ? "成功" : "缺失")，人物\(charactersOK ? "成功" : "缺失")，大纲\(outlinesOK ? "成功" : "缺失")"
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

    private func ensureBatchFlow() -> BatchStoryboardFlowStore? {
        if let flow = batchFlow { return flow }
        guard let project = selectedProject else { return nil }
        let flow = BatchStoryboardFlowStore(
            project: project,
            promptLibraryStore: promptLibraryStore,
            actionCenter: actionCenter,
            storyboardStore: storyboardStore
        )
        batchFlow = flow
        return flow
    }
}

private struct ResumeHeader: View {
    let project: ScriptProject
    let episode: ScriptEpisode?
    let onResume: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("继续上次工作")
                    .font(.headline)
                Text("\(episodeLabel()) · 更新 \(updatedText())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onResume()
            } label: {
                HStack(spacing: 6) {
                    Text("继续")
                    Image(systemName: "arrow.right.circle.fill")
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    private func episodeLabel() -> String {
        episode?.displayLabel ?? "整片"
    }

    private func updatedText() -> String {
        let date = episode?.updatedAt ?? project.updatedAt
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct ScriptProjectWordBuilder {
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    func makeDocument(for project: ScriptProject) -> String {
        var lines: [String] = []
        lines.append(project.title)
        lines.append(String(repeating: "=", count: max(8, project.title.count)))
        lines.append("")
        lines.append("项目类型：\(project.type.displayName)")
        if let start = project.productionStartDate {
            let startText = dateFormatter.string(from: start)
            if let end = project.productionEndDate {
                lines.append("制作周期：\(startText) - \(dateFormatter.string(from: end))")
            } else {
                lines.append("制作周期：自 \(startText)")
            }
        } else if let end = project.productionEndDate {
            lines.append("制作周期：截至 \(dateFormatter.string(from: end))")
        }
        if project.tags.isEmpty == false {
            lines.append("标签：\(project.tags.joined(separator: "，"))")
        }
        if project.synopsis.isEmpty == false {
            lines.append("")
            lines.append("项目简介：")
            lines.append(project.synopsis)
        }
        if project.mainCharacters.isEmpty == false {
            lines.append("")
            lines.append("主要角色：")
            for character in project.mainCharacters {
                lines.append("• \(character.name.isEmpty ? "未命名角色" : character.name)：\(character.description)")
            }
        }
        if project.keyScenes.isEmpty == false {
            lines.append("")
            lines.append("主要场景：")
            for scene in project.keyScenes {
                lines.append("• \(scene.name.isEmpty ? "未命名场景" : scene.name)：\(scene.description)")
            }
        }
        if project.notes.isEmpty == false {
            lines.append("")
            lines.append("备注：")
            lines.append(project.notes)
        }

        for episode in project.orderedEpisodes {
            lines.append("")
            lines.append("第\(episode.displayLabel)")
            lines.append(String(repeating: "-", count: max(8, episode.displayLabel.count + 1)))
            if episode.title.isEmpty == false {
                lines.append("标题：\(episode.title)")
            }
            lines.append("更新时间：\(dateFormatter.string(from: episode.updatedAt))")
            lines.append("")
            if episode.scenes.isEmpty {
                lines.append(episode.markdown)
            } else {
                let sortedScenes = episode.scenes.sorted { $0.order < $1.order }
                for (index, scene) in sortedScenes.enumerated() {
                    lines.append("场景 \(index + 1)：\(scene.title.isEmpty ? "未命名场景" : scene.title)")
                    if scene.locationHint.isEmpty == false || scene.timeHint.isEmpty == false {
                        lines.append("• 环境：\(scene.locationHint) \(scene.timeHint)")
                    }
                    if scene.body.isEmpty == false {
                        lines.append(scene.body)
                    }
                    lines.append("")
                }
            }
        }

        return lines.joined(separator: "\n")
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
