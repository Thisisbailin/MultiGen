import SwiftUI

struct HomeWorkspaceView: View {
    let textModelLabel: String
    let textRouteLabel: String
    @EnvironmentObject private var scriptStore: ScriptStore
    @EnvironmentObject private var navigationStore: NavigationStore
    @State private var highlightedProjectID: UUID?

    private var scriptProjects: [ScriptProject] {
        scriptStore.containers
            .compactMap { container in
                if let script = container.script {
                    return script
                }
                return scriptStore.ensureScript(projectID: container.id, type: .standalone)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HomeDashboardView(
                    textModelLabel: textModelLabel,
                    textRouteLabel: textRouteLabel,
                    showEmptyGuide: scriptStore.containers.isEmpty
                )
                containerList
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: syncHighlightFromNavigation)
        .onChange(of: scriptProjects) { _, _ in
            syncHighlightFromNavigation()
        }
    }

    @ViewBuilder
    private var containerList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if scriptProjects.isEmpty {
                Text("暂无项目，请通过右上角“新建项目”创建。")
                    .foregroundStyle(.secondary)
            } else {
                Text("项目容器")
                    .font(.headline)
                ProjectGalleryList(
                    projects: scriptProjects,
                    highlightedProjectID: Binding(
                        get: { highlightedProjectID ?? navigationStore.currentScriptProjectID },
                        set: { newValue in
                            highlightedProjectID = newValue
                            if let id = newValue {
                                navigationStore.currentScriptProjectID = id
                                navigationStore.currentScriptEpisodeID = scriptProjects.first(where: { $0.id == id })?.orderedEpisodes.first?.id
                            }
                        }
                    ),
                    onOpen: { project in
                        navigationStore.currentScriptProjectID = project.id
                        navigationStore.currentScriptEpisodeID = project.orderedEpisodes.first?.id
                        navigationStore.selection = .script
                    }
                )
            }
        }
    }

    private func syncHighlightFromNavigation() {
        if let current = navigationStore.currentScriptProjectID,
           scriptProjects.contains(where: { $0.id == current }) {
            highlightedProjectID = current
        } else {
            highlightedProjectID = scriptProjects.first?.id
            if let first = highlightedProjectID {
                navigationStore.currentScriptProjectID = first
                navigationStore.currentScriptEpisodeID = scriptProjects.first?.orderedEpisodes.first?.id
            }
        }
    }
}
