import SwiftUI

struct ModuleAssistantSwitcher: View {
    let module: AIChatModule
    let scriptProjectTitle: String?
    let storyboardState: StoryboardAssistantDisplay?
    let onRequestSummary: (() -> Void)?
    let onShowHistory: () -> Void
    let onStoryboardGenerate: (() -> Void)?

    var body: some View {
        switch module {
        case .general:
            assistantPanel(title: "智能协同助手", message: "与 AI 聊天以获取灵感、提问或继续项目流程。")
        case .script:
            VStack(alignment: .leading, spacing: 8) {
                Text("剧本助手")
                    .font(.headline)
                Text(scriptProjectTitle.map { "当前项目：\($0)" } ?? "请在剧本模块选择项目")
                    .foregroundStyle(.secondary)
                if let onRequestSummary {
                    HStack(spacing: 12) {
                        Button {
                            onRequestSummary()
                        } label: {
                            Label("生成项目总结", systemImage: "text.alignleft")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            onShowHistory()
                        } label: {
                            Label("查看历史", systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .assistantBackground()
        case .promptHelper, .promptHelperStyle:
            VStack(alignment: .leading, spacing: 8) {
                Text(module == .promptHelperStyle ? "风格助手" : "提示词助手")
                    .font(.headline)
                if module == .promptHelperStyle {
                    Text("上传风格参考图，生成可复用的风格提示词。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(scriptProjectTitle.map { "当前项目：\($0)" } ?? "请在角色/场景模块选择项目")
                        .foregroundStyle(.secondary)
                    Text("根据角色/场景描述生成中文提示词。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button {
                        onShowHistory()
                    } label: {
                        Label("查看历史", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .assistantBackground()
        case .storyboard:
            StoryboardAssistantCard(
                state: storyboardState,
                onGenerate: onStoryboardGenerate
            )
        }
    }

    @ViewBuilder
    private func assistantPanel(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .assistantBackground()
    }
}

private extension View {
    func assistantBackground() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
    }
}

private struct StoryboardAssistantCard: View {
    let state: StoryboardAssistantDisplay?
    let onGenerate: (() -> Void)?

    var body: some View {
        let display = state ?? .init()
        VStack(alignment: .leading, spacing: 10) {
            Label("分镜助手", systemImage: "sparkles.rectangle.stack")
                .font(.headline)
            Group {
                Text(display.episodeLabel ?? "请在分镜模块选择项目与剧集")
                Text(display.sceneCountLabel ?? "暂无场景")
                if let active = display.activeSceneTitle {
                    Text("当前聚焦：\(active)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text("点击下方按钮即可请求整集分镜。结果会注入分镜列表，并在智能协同中留存操作通知。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if display.hasExistingShots {
                Text("当前分镜板已有内容，AI 生成会追加并标记为待审核。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let warning = display.warningMessage {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                onGenerate?()
            } label: {
                Label("整集生成分镜", systemImage: "play.rectangle.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(onGenerate == nil || display.canGenerate == false)
        }
        .assistantBackground()
    }
}

struct ModuleCollaborationHint: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 10)
        )
    }
}
