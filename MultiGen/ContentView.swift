//
//  ContentView.swift
//  MultiGen
//
//  Created by Joe on 2025/11/12.
//

import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject private var configuration: AppConfiguration
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var scriptStore: ScriptStore
    @EnvironmentObject private var storyboardStore: StoryboardStore
    @EnvironmentObject private var promptLibraryStore: PromptLibraryStore
    @EnvironmentObject private var navigationStore: NavigationStore

    var body: some View {
        NavigationSplitView(columnVisibility: $navigationStore.columnVisibility) {
            VStack(spacing: 12) {
                Picker("", selection: $navigationStore.sidebarMode) {
                    Image(systemName: "square.grid.2x2")
                        .tag(SidebarMode.projects)
                    Image(systemName: "bubble.left.and.bubble.right")
                        .tag(SidebarMode.ai)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if navigationStore.sidebarMode == .projects {
                    SidebarProjectList(selection: $navigationStore.selection)
                } else {
                    AIChatSidebarView()
                        .environmentObject(dependencies)
                        .environmentObject(promptLibraryStore)
                }
            }
            .padding(12)
        } detail: {
            detailView(for: navigationStore.selection)
                .toolbar {
                    if navigationStore.selection == .home {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                navigationStore.showPainPointSheet.toggle()
                            } label: {
                                Label("痛点说明", systemImage: "lightbulb")
                            }
                            .help("查看 AIGC 场景创作现状与解决策略")
                        }
                        ToolbarItem(placement: .status) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label("文本：\(configuration.textModel.displayName)", systemImage: "text.book.closed")
                                Label("图像：\(configuration.imageModel.displayName)", systemImage: "photo.on.rectangle")
                            }
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                navigationStore.showSettingsSheet.toggle()
                            } label: {
                                Label("设置", systemImage: "slider.horizontal.3")
                            }
                            .help("打开 Gemini 设置与密钥管理")
                        }
                    }
                }
                .sheet(isPresented: $navigationStore.showPainPointSheet) {
                    PainPointSheetView(painPoints: PainPointCatalog.corePainPoints)
                        .frame(minWidth: 520, minHeight: 420)
                }
                .sheet(isPresented: $navigationStore.showSettingsSheet) {
                    SettingsView()
                        .frame(minWidth: 520, minHeight: 500)
                }
        }
        .toolbarBackground(.hidden, for: .automatic)
        .task { }
    }

    @ViewBuilder
    private func detailView(for item: SidebarItem) -> some View {
        switch item {
        case .home:
            ScenarioOverviewView(
                painPoints: PainPointCatalog.corePainPoints,
                actions: SceneAction.workflowActions
            )
            .navigationTitle("MultiGen 控制台")
        case .script:
            ScriptView()
                .navigationTitle("剧本")
        case .storyboard:
            StoryboardScreen {
                StoryboardDialogueStore(
                    scriptStore: scriptStore,
                    storyboardStore: storyboardStore
                )
            }
                .navigationTitle("分镜")
        case .image:
            ImagingPlaceholderView()
                .navigationTitle("影像")
        case .libraryCharacters, .libraryScenes, .libraryPrompts:
            if item == .libraryPrompts {
                PromptLibraryView()
                    .environmentObject(promptLibraryStore)
                    .navigationTitle("指令资料库")
            } else {
                LibraryPlaceholderView(title: item.title)
            }
        }
    }

}

enum SidebarItem: String, Identifiable {
    case home
    case script
    case storyboard
    case image
    case libraryCharacters
    case libraryScenes
    case libraryPrompts

    static let primaryItems: [SidebarItem] = [.home, .script, .storyboard, .image]
    static let libraryItems: [SidebarItem] = [.libraryCharacters, .libraryScenes, .libraryPrompts]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "主页"
        case .script: return "剧本"
        case .storyboard: return "分镜"
        case .image: return "影像"
        case .libraryCharacters: return "角色"
        case .libraryScenes: return "场景"
        case .libraryPrompts: return "指令"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .script: return "book.pages"
        case .storyboard: return "rectangle.3.offgrid"
        case .image: return "sparkles"
        case .libraryCharacters: return "person.crop.square"
        case .libraryScenes: return "square.grid.3x3"
        case .libraryPrompts: return "text.quote"
        }
    }
}

enum SidebarMode: String, CaseIterable {
    case projects
    case ai
}

@MainActor
final class NavigationStore: ObservableObject {
    @Published var sidebarMode: SidebarMode = .projects
    @Published var selection: SidebarItem = .home
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var showPainPointSheet = false
    @Published var showSettingsSheet = false
    @Published var currentScriptEpisodeID: UUID?
    @Published var currentStoryboardEpisodeID: UUID?
    weak var storyboardAutomationHandler: (any StoryboardAutomationHandling)?
}

private struct PainPointSheetView: View {
    let painPoints: [PainPoint]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AIGC 场景创作痛点")
                        .font(.system(.title, weight: .semibold))
                    Text("遵循 macOS 26 设计指南，痛点说明作为随时可调用的辅助视图，帮助用户在开始配置前理解 MultiGen 的价值。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(painPoints) { point in
                        PainPointRow(painPoint: point)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(nsColor: NSColor.controlBackgroundColor))
                            )
                    }
                }
            }
        }
        .padding(24)
    }
}

private struct LibraryPlaceholderView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.largeTitle.bold())
            Text("资料库模块敬请期待：未来将在此管理 \(title) 资产，并与影像创作流程联动。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AIChatSidebarView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var promptLibraryStore: PromptLibraryStore
    @EnvironmentObject private var navigationStore: NavigationStore
    @EnvironmentObject private var scriptStore: ScriptStore
    @EnvironmentObject private var storyboardStore: StoryboardStore
    @State private var messages: [AIChatMessage] = [
        AIChatMessage(role: .assistant, text: "你好，我是 MultiGen 的智能协作者。告诉我你想要讨论的内容吧！")
    ]
    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isTextFocused: Bool
    @State private var expandedMessageIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 8) {
            Label("智能协作", systemImage: "sparkles")
                .font(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            ChatBubble(
                                message: message,
                                isExpanded: expandedMessageIDs.contains(message.id),
                                onToggleDetail: {
                                    guard message.detail != nil else { return }
                                    if expandedMessageIDs.contains(message.id) {
                                        expandedMessageIDs.remove(message.id)
                                    } else {
                                        expandedMessageIDs.insert(message.id)
                                    }
                                }
                            )
                                .id(message.id)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前模型：\(dependencies.configuration.textModel.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(contextStatusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(contextModeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    TextField("向 Gemini 描述你的需求…", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTextFocused)
                        .disabled(isSending)

                    Button {
                        sendMessage()
                    } label: {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .underPageBackgroundColor))
            )
        }
        .padding(10)
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        let contextSnapshot = activeContext
        if case .storyboard = contextSnapshot {
            navigationStore.storyboardAutomationHandler?.recordSidebarInstruction(trimmed)
        }

        let userMessage = AIChatMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        inputText = ""
        errorMessage = nil
        isSending = true

        Task {
            defer { isSending = false }
            do {
                let fields = makeRequestFields(for: trimmed)
                let request = SceneJobRequest(
                    action: .aiConsole,
                    fields: fields,
                    channel: .text
                )
                let result = try await dependencies.textService().submit(job: request)
                let replyText = result.metadata.prompt
                await MainActor.run {
                    handleAIResponse(text: replyText, context: contextSnapshot)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleAIResponse(text: String, context: ChatContext) {
        switch context {
        case .storyboard:
            if let outcome = navigationStore.storyboardAutomationHandler?.applySidebarAIResponse(text) {
                let summary: String
                if outcome.touchedEntries > 0 {
                    summary = "分镜更新完成：\(outcome.touchedEntries) 个镜头已写入当前剧集。"
                } else {
                    summary = outcome.warning ?? "AI 回复未包含可解析的分镜结构，请调整提示后重试。"
                }
                messages.append(
                    AIChatMessage(
                        role: .system,
                        text: summary,
                        detail: text
                    )
                )
            } else {
                messages.append(AIChatMessage(role: .assistant, text: text))
            }
        default:
            messages.append(AIChatMessage(role: .assistant, text: text))
        }
    }

    private var activeContext: ChatContext {
        switch navigationStore.selection {
        case .script:
            if let episode = scriptEpisode(for: navigationStore.currentScriptEpisodeID) {
                return .script(project: project(for: episode.id), episode: episode)
            }
        case .storyboard:
            if let episodeID = navigationStore.currentStoryboardEpisodeID,
               let episode = scriptEpisode(for: episodeID) {
                let project = project(for: episode.id)
                let workspace = storyboardStore.workspace(for: episodeID)
                return .storyboard(project: project, episode: episode, workspace: workspace)
            }
        default:
            break
        }
        return .general
    }

    private var activePromptModule: PromptDocument.Module {
        switch activeContext {
        case .general:
            return .aiConsole
        case .script:
            return .script
        case .storyboard:
            return .storyboard
        }
    }

    private var contextStatusText: String {
        switch activeContext {
        case .general:
            switch navigationStore.selection {
            case .script:
                return "上下文：剧本 · 未选择剧集"
            case .storyboard:
                return "上下文：分镜 · 未选择剧集"
            default:
                return "上下文：主页聊天"
            }
        case .script(_, let episode):
            return "上下文：剧本 · \(episode.displayLabel)"
        case .storyboard(_, let episode, let workspace):
            let count = workspace?.entries.count ?? 0
            return "上下文：分镜 · \(episode.displayLabel) · \(count) 镜头"
        }
    }
    
    private var contextModeText: String {
        switch activeContext {
        case .general:
            return "模式：自由聊天"
        case .script:
            return "模式：文本建议（不自动写入）"
        case .storyboard:
            return "模式：分镜操作 · AI 结果会写入分镜表"
        }
    }

    private func makeRequestFields(for prompt: String) -> [String: String] {
        var fields: [String: String] = [
            "prompt": prompt,
            "contextSummary": contextStatusText
        ]
        let systemPrompt = promptLibraryStore.document(for: activePromptModule)
            .content.trimmingCharacters(in: .whitespacesAndNewlines)
        if systemPrompt.isEmpty == false {
            fields["systemPrompt"] = systemPrompt
        }
        let extras = contextFields(for: activeContext)
        extras.forEach { key, value in
            guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
            fields[key] = value
        }
        if case .storyboard = activeContext {
            fields["responseFormat"] = StoryboardResponseParser.responseFormatHint
        }
        return fields
    }

    private func contextFields(for context: ChatContext) -> [String: String] {
        switch context {
        case .general:
            return [:]
        case .script(let project, let episode):
            return [
                "scriptContext": makeScriptContext(episode: episode, project: project)
            ]
        case .storyboard(let project, let episode, let workspace):
            var payload: [String: String] = [
                "scriptContext": makeScriptContext(episode: episode, project: project)
            ]
            if let storyboardSummary = makeStoryboardContext(workspace: workspace) {
                payload["storyboardContext"] = storyboardSummary
            }
            return payload
        }
    }

    private func makeScriptContext(episode: ScriptEpisode, project: ScriptProject?) -> String {
        var lines: [String] = []
        if let project {
            lines.append("项目：\(project.title)")
        }
        lines.append("剧集：\(episode.displayLabel)")
        if episode.synopsis.isEmpty == false {
            lines.append("简介：\(episode.synopsis)")
        }
        let body = sanitizedBody(episode.markdown, limit: 6000)
        lines.append("正文：\n\(body)")
        return lines.joined(separator: "\n")
    }

    private func makeStoryboardContext(workspace: StoryboardWorkspace?) -> String? {
        guard let workspace else { return nil }
        let entries = workspace.orderedEntries
        guard entries.isEmpty == false else { return nil }
        let maxShots = 12
        var blocks: [String] = []
        for entry in entries.prefix(maxShots) {
            var segment: [String] = []
            segment.append("镜\(entry.fields.shotNumber) · \(entry.sceneTitle)")
            let tags = [
                entry.fields.shotScale.isEmpty ? nil : "景别：\(entry.fields.shotScale)",
                entry.fields.cameraMovement.isEmpty ? nil : "运镜：\(entry.fields.cameraMovement)",
                entry.fields.duration.isEmpty ? nil : "时长：\(entry.fields.duration)"
            ].compactMap { $0 }.joined(separator: "｜")
            if tags.isEmpty == false {
                segment.append(tags)
            }
            if entry.sceneSummary.isEmpty == false {
                segment.append("画面：\(entry.sceneSummary)")
            }
            if entry.fields.dialogueOrOS.isEmpty == false {
                segment.append("台词/OS：\(entry.fields.dialogueOrOS)")
            }
            if entry.fields.aiPrompt.isEmpty == false {
                segment.append("提示词：\(entry.fields.aiPrompt)")
            }
            if entry.notes.isEmpty == false {
                segment.append("备注：\(entry.notes)")
            }
            blocks.append(segment.joined(separator: "\n"))
        }
        if entries.count > maxShots {
            blocks.append("……其余 \(entries.count - maxShots) 个镜头已省略。")
        }
        return blocks.joined(separator: "\n\n")
    }

    private func scriptEpisode(for id: UUID?) -> ScriptEpisode? {
        guard let id else { return nil }
        return scriptStore.episodes.first(where: { $0.id == id })
    }

    private func project(for episodeID: UUID) -> ScriptProject? {
        scriptStore.projects.first { project in
            project.episodes.contains(where: { $0.id == episodeID })
        }
    }

    private func sanitizedBody(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return "（尚未提供剧本文本）"
        }
        if trimmed.count <= limit {
            return trimmed
        }
        let prefixText = trimmed.prefix(limit)
        return "\(prefixText)…（已截断）"
    }

    private enum ChatContext {
        case general
        case script(project: ScriptProject?, episode: ScriptEpisode)
        case storyboard(project: ScriptProject?, episode: ScriptEpisode, workspace: StoryboardWorkspace?)
    }
}

private struct ChatBubble: View {
    let message: AIChatMessage
    var isExpanded: Bool = false
    var onToggleDetail: () -> Void = {}

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.role.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(foregroundColor)
                }
                if let detail = message.detail {
                    Button {
                        onToggleDetail()
                    } label: {
                        Label(isExpanded ? "收起操作详情" : "查看操作详情", systemImage: isExpanded ? "chevron.up.circle" : "chevron.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    if isExpanded {
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(detail)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 140)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.05))
                        )
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(backgroundColor)
            )
            if message.role != .user { Spacer(minLength: 0) }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor
        case .assistant:
            return Color(nsColor: .controlBackgroundColor)
        case .system:
            return Color.orange.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch message.role {
        case .user:
            return Color.white
        case .assistant:
            return .primary
        case .system:
            return .primary
        }
    }
}

private struct AIChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
        case system

        var displayName: String {
            switch self {
            case .user: return "我"
            case .assistant: return "Gemini"
            case .system: return "系统"
            }
        }
    }

    let id = UUID()
    let role: Role
    let text: String
    let detail: String?

    init(role: Role, text: String, detail: String? = nil) {
        self.role = role
        self.text = text
        self.detail = detail
    }
}
