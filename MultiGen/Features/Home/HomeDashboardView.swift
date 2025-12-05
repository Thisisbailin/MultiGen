import SwiftUI

struct HomeDashboardView: View {
    let textModelLabel: String
    let textRouteLabel: String
    let showEmptyGuide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            heroSection
            statusRow
            if showEmptyGuide {
                actionPlaceholder
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("总工作台 · 以项目为中心")
                .font(.title.bold())
            Text("""
在写作、剧本、分镜、影像这些环节中精雕细琢，但更高一层需要跨环节的行动：同一项目的文本与影像相互转化（小说→剧本→脚本→提示词等），由 Agent 统筹。主页只关注“项目”这一容器，具体创作请进入对应模块。
""")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            HomeMetricCard(title: "文本模型", value: textModelLabel)
            HomeMetricCard(title: "文本路线", value: textRouteLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择一个项目以开始")
                .font(.headline)
            Text("""
在左侧列表或顶部“新建项目”创建容器。写作/剧本/分镜三形态平行存在：写作用于文学文本，剧本/分镜保持紧耦合。后续将在此编排跨模态动作。
""")
                .font(.callout)
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [8]))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .frame(minHeight: 180)
                .overlay(
                    VStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("项目容器")
                            .font(.headline)
                        Text("当前暂无项目，请点击右上角“新建项目”或在侧边栏添加；创建后再去写作/剧本/分镜模块继续创作。")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    .padding()
                )
        }
    }
}

struct HomeMetricCard: View {
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
