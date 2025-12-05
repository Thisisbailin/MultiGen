import SwiftUI

struct WritingView: View {
    @EnvironmentObject private var store: ScriptStore
    @EnvironmentObject private var navigationStore: NavigationStore

    @State private var showOverview = false
    @State private var selectedChapterID: UUID?

    private var containers: [ProjectContainer] {
        store.containers.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var activeProjectID: UUID? {
        navigationStore.currentScriptProjectID ?? containers.first?.id
    }

    var body: some View {
        ScrollView {
            writingDetail
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .onAppear(perform: ensureSelection)
        .onChange(of: navigationStore.currentScriptProjectID) { _, _ in
            ensureSelection()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: showOverview)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedChapterID)
        .toolbar {
            if let containerID = activeProjectID,
               let writing = store.ensureWriting(projectID: containerID) {
                let chapters = writing.chapters.sorted { $0.order < $1.order }
                ToolbarItemGroup {
                    Button {
                        showOverview.toggle()
                    } label: {
                        Image(systemName: showOverview ? "doc.text.fill" : "doc.text.magnifyingglass")
                    }
                    .help(showOverview ? "收起概览" : "展开概览")

                    Menu {
                        if chapters.isEmpty {
                            Text("暂无章节")
                        } else {
                            ForEach(chapters) { chapter in
                                Button(chapter.title.isEmpty ? "第\(chapter.order)章" : chapter.title) {
                                    selectedChapterID = chapter.id
                                }
                            }
                        }
                    } label: {
                        Label("章节", systemImage: "list.bullet.rectangle")
                    }

                    Button {
                        addChapter(to: containerID, type: writing.type)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("新增章节")

                    Button(role: .destructive) {
                        deleteCurrentChapter(projectID: containerID)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedChapterID == nil)
                    .help("删除当前章节")
                }
            }
        }
        .toolbarBackground(.hidden, for: .automatic)
        .toolbarBackground(.hidden, for: .windowToolbar)
    }

    private var writingDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let containerID = activeProjectID,
               let writing = store.ensureWriting(projectID: containerID) {
                let chapters = writing.chapters.sorted { $0.order < $1.order }
                let resolvedChapterID = selectedChapterID ?? chapters.first?.id
                let currentChapter = chapters.first { $0.id == resolvedChapterID }
                let container = containers.first { $0.id == containerID }

                if showOverview {
                    WritingOverviewCard(
                        writing: writing,
                        chapters: chapters,
                        onCollapse: { showOverview = false }
                    )
                }

                if let chapter = currentChapter {
                    WritingChapterCard(
                        chapter: chapter,
                        writing: writing,
                        isOverviewVisible: showOverview,
                        lastUpdated: container?.updatedAt,
                        onTitleChange: { newTitle in
                            updateChapter(containerID: containerID, chapterID: chapter.id) { $0.title = newTitle }
                        },
                        onBodyChange: { newBody in
                            updateChapter(containerID: containerID, chapterID: chapter.id) { $0.body = newBody }
                        }
                    )
                } else {
                    Text("暂无章节，请新增后开始创作。")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("请选择或创建项目后再编辑写作文本。")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func ensureSelection() {
        if navigationStore.currentScriptProjectID == nil, let first = containers.first {
            navigationStore.currentScriptProjectID = first.id
            navigationStore.currentScriptEpisodeID = store.project(id: first.id)?.orderedEpisodes.first?.id
        }
        // 当切换项目时重置视图状态，保持与主页选中的容器一致
        showOverview = false
        selectedChapterID = nil
    }

    private func addChapter(to projectID: UUID, type: WritingWork.WritingType) {
        let order = (store.ensureWriting(projectID: projectID)?.chapters.map { $0.order }.max() ?? 0) + 1
        let chapter = WritingChapter(order: order, title: "第\(order)章")
        store.updateWriting(projectID: projectID) { editable in
            editable.chapters.append(chapter)
        }
        selectedChapterID = chapter.id
    }

    private func updateChapter(containerID: UUID, chapterID: UUID, update: (inout WritingChapter) -> Void) {
        store.updateWriting(projectID: containerID) { editable in
            guard let idx = editable.chapters.firstIndex(where: { $0.id == chapterID }) else { return }
            update(&editable.chapters[idx])
        }
    }

    private func deleteCurrentChapter(projectID: UUID) {
        guard let chapterID = selectedChapterID else { return }
        store.updateWriting(projectID: projectID) { editable in
            editable.chapters.removeAll { $0.id == chapterID }
        }
        let remaining = store.ensureWriting(projectID: projectID)?.chapters.sorted { $0.order < $1.order }
        selectedChapterID = remaining?.first?.id
    }
}

private struct WritingOverviewCard: View {
    let writing: WritingWork
    let chapters: [WritingChapter]
    let onCollapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("文本概览")
                        .font(.headline)
                    Text(writing.synopsis.isEmpty ? "暂无简介" : writing.synopsis)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
                Button {
                    onCollapse()
                } label: {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("收起概览")
            }

            HStack(spacing: 12) {
                metric(label: "章节数", value: "\(chapters.count)")
                metric(label: "正文字数", value: "\(totalWordCount())")
                metric(label: "类型", value: writing.type.displayName)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 8)
    }

    private func totalWordCount() -> Int {
        let bodyText = writing.body + chapters.map { $0.body }.joined()
        return bodyText.count
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }
}

private struct WritingChapterCard: View {
    let chapter: WritingChapter
    let writing: WritingWork
    let isOverviewVisible: Bool
    let lastUpdated: Date?
    let onTitleChange: (String) -> Void
    let onBodyChange: (String) -> Void

    @State private var localTitle: String = ""
    @State private var localBody: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("未命名章节", text: $localTitle)
                .textFieldStyle(.plain)
                .font(.system(.title, weight: .semibold))
                .padding(.bottom, 4)
                .onSubmit { onTitleChange(localTitle) }

            if let lastUpdated {
                Text("更新 \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $localBody)
                .frame(minHeight: 320)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 2)

            HStack {
                Spacer()
                Text("字数 \(localBody.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .shadow(color: Color.black.opacity(isOverviewVisible ? 0.04 : 0.08), radius: 16, y: 10)
        .onChange(of: localTitle) { _, newValue in onTitleChange(newValue) }
        .onChange(of: localBody) { _, newValue in onBodyChange(newValue) }
        .onAppear {
            syncLocal()
        }
        .onChange(of: chapter.id) { _, _ in syncLocal() }
    }

    private func syncLocal() {
        localTitle = chapter.title
        localBody = chapter.body
    }
}
