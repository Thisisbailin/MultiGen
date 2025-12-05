import SwiftUI

struct WritingView: View {
    @EnvironmentObject private var store: ScriptStore
    @EnvironmentObject private var navigationStore: NavigationStore

    @State private var highlightedProjectID: UUID?
    private var containers: [ProjectContainer] {
        store.containers.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusRow
            projectPicker
            writingDetail
        }
        .padding(16)
        .onAppear {
            highlightedProjectID = navigationStore.currentScriptProjectID ?? containers.first?.id
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("写作 · 文学文本起点")
                .font(.title2.bold())
            Text("""
项目在此诞生：先有自由的文学文本，再向下转写为剧本，再进一步拆解为分镜。Agent 将在这里串联跨模态转化。
""")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            HomeMetricCard(title: "项目总数", value: "\(containers.count)")
            HomeMetricCard(title: "最近更新", value: containers.first?.updatedAt.formatted(date: .abbreviated, time: .shortened) ?? "暂无")
        }
    }

    private var projectPicker: some View {
        HStack(spacing: 12) {
            Text("当前项目")
                .font(.headline)
            Picker("项目", selection: Binding(
                get: { highlightedProjectID ?? containers.first?.id },
                set: { newValue in
                    highlightedProjectID = newValue
                    navigationStore.currentScriptProjectID = newValue
                    navigationStore.currentScriptEpisodeID = store.project(id: newValue ?? UUID())?.orderedEpisodes.first?.id
                }
            )) {
                ForEach(containers) { container in
                    Text(container.title.isEmpty ? "未命名项目" : container.title)
                        .tag(Optional.some(container.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var writingDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let containerID = highlightedProjectID,
               let writing = store.ensureWriting(projectID: containerID) {
                WritingEditorView(
                    projectID: containerID,
                    writing: writing,
                    onUpdate: { updated in
                        store.updateWriting(projectID: containerID) { $0 = updated }
                    }
                )
            } else {
                Text("请选择项目以编辑写作文本。")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
    }

}
