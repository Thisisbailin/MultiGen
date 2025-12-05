import SwiftUI

struct HomeWorkspaceView: View {
    let textModelLabel: String
    let textRouteLabel: String
    @EnvironmentObject private var scriptStore: ScriptStore
    @EnvironmentObject private var navigationStore: NavigationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HomeDashboardView(textModelLabel: textModelLabel, textRouteLabel: textRouteLabel)
                containerList
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var containerList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("项目容器")
                .font(.headline)
            if scriptStore.containers.isEmpty {
                Text("暂无项目，请通过右上角“新建项目”创建。")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(scriptStore.containers) { container in
                        Button {
                            navigationStore.currentScriptProjectID = container.id
                            navigationStore.selection = .writing
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(container.title.isEmpty ? "未命名项目" : container.title)
                                        .font(.headline)
                                    Text("更新 \(container.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(nsColor: .windowBackgroundColor))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
