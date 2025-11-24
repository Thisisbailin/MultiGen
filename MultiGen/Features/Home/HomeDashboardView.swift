import SwiftUI

struct HomeDashboardView: View {
    let textModelLabel: String
    let textRouteLabel: String

    private let workflowStages: [HomeWorkflowStage] = [
        HomeWorkflowStage(
            title: "剧本构思 · Script",
            detail: "剧本模块负责剧集/分集创作、润色与结构化输出。",
            focus: "应用深入介入",
            isActive: true
        ),
        HomeWorkflowStage(
            title: "分镜拆解 · Storyboard",
            detail: "分镜模块将剧本转译为镜头表，智能协同可直接操作更新。",
            focus: "应用深入介入",
            isActive: true
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                overviewSection
                workflowSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MultiGen · macOS 专用 AIGC 创作台")
                .font(.title.bold())
            Text("当前聚焦剧本 → 分镜两段式流程，智能协同模块作为 AI 中枢负责统一路由、审计与回执。")
                .font(.callout)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    HomeMetricCard(title: "文本模型", value: textModelLabel)
                    HomeMetricCard(title: "文本路线", value: textRouteLabel)
                }
            }
        }
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("工作流程路线图")
                .font(.title3.bold())

            VStack(spacing: 0) {
                ForEach(Array(workflowStages.enumerated()), id: \.element.id) { index, stage in
                    workflowNode(for: stage)

                    if index < workflowStages.count - 1 {
                        HStack {
                            VStack {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.4))
                                    .frame(width: 2, height: 24)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.4))
                                    .frame(width: 2, height: 24)
                            }
                            .frame(width: 28)
                            Spacer()
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func workflowNode(for stage: HomeWorkflowStage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: stage.isActive ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(stage.isActive ? Color.accentColor : Color.secondary.opacity(0.5))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(stage.title)
                        .font(.headline)
                    Spacer()
                    Label(stage.focus, systemImage: "sparkles")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
                Text(stage.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.clear)
            .shadow(color: Color.black.opacity(0.12), radius: 10, y: 6)
        }
        .padding(.vertical, 6)
    }
}

private struct HomeWorkflowStage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let focus: String
    let isActive: Bool
}

private struct HomeMetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }
}

struct LibraryPlaceholderView: View {
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("\(title) 模块即将上线")
                .font(.title3.bold())
            Text("指令资料库正在与最新工作流对齐，敬请期待。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
