//
//  ContentView.swift
//  MultiGen
//
//  Created by Joe on 2025/11/12.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var configuration: AppConfiguration
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var scriptStore: ScriptStore
    @EnvironmentObject private var storyboardStore: StoryboardStore
    @EnvironmentObject private var promptLibraryStore: PromptLibraryStore
    @State private var selection: SidebarItem = .home
    @State private var showPainPointSheet = false
    @State private var showSettingsSheet = false
    @State private var sidebarMode: SidebarMode = .projects
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 12) {
                Picker("", selection: $sidebarMode) {
                    Image(systemName: "square.grid.2x2")
                        .tag(SidebarMode.projects)
                    Image(systemName: "bubble.left.and.bubble.right")
                        .tag(SidebarMode.ai)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if sidebarMode == .projects {
                    SidebarProjectList(selection: $selection)
                } else {
                    AIChatSidebarView()
                        .environmentObject(dependencies)
                        .environmentObject(promptLibraryStore)
                }
            }
            .padding(12)
        } detail: {
            detailView(for: selection)
                .toolbar {
                    if selection == .home {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                showPainPointSheet.toggle()
                            } label: {
                                Label("痛点说明", systemImage: "lightbulb")
                            }
                            .help("查看 AIGC 场景创作现状与解决策略")
                        }
                        ToolbarItem(placement: .status) {
                            Group {
                                if configuration.useMock {
                                    Label("Mock 模式", systemImage: "wand.and.stars")
                                        .foregroundStyle(.orange)
                                } else {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Label("文本：\(configuration.textModel.displayName)", systemImage: "text.book.closed")
                                        Label("图像：\(configuration.imageModel.displayName)", systemImage: "photo.on.rectangle")
                                    }
                                    .labelStyle(.titleAndIcon)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showSettingsSheet.toggle()
                            } label: {
                                Label("设置", systemImage: "slider.horizontal.3")
                            }
                            .help("打开 Gemini 设置与密钥管理")
                        }
                    }
                }
                .sheet(isPresented: $showPainPointSheet) {
                    PainPointSheetView(painPoints: PainPointCatalog.corePainPoints)
                        .frame(minWidth: 520, minHeight: 420)
                }
                .sheet(isPresented: $showSettingsSheet) {
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
                    storyboardStore: storyboardStore,
                    promptLibraryStore: promptLibraryStore,
                    dependencies: dependencies
                )
            }
                .navigationTitle("分镜")
        case .image:
            CreateScreen {
                CreateStore(
                    storyboardStore: storyboardStore,
                    dependencies: dependencies
                )
            }
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
    @State private var messages: [AIChatMessage] = [
        AIChatMessage(role: .assistant, text: "你好，我是 MultiGen 的智能协作者。告诉我你想要讨论的内容吧！")
    ]
    @State private var inputText: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isTextFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Label("智能协作", systemImage: "sparkles")
                .font(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
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
                    Text("当前模型：\(dependencies.configuration.textModel.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

        let userMessage = AIChatMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        inputText = ""
        errorMessage = nil
        isSending = true

        Task {
            defer { isSending = false }
            do {
                var fields: [String: String] = ["prompt": trimmed]
                let systemPrompt = promptLibraryStore.document(for: .aiConsole).content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if systemPrompt.isEmpty == false {
                    fields["systemPrompt"] = systemPrompt
                }
                let request = SceneJobRequest(
                    action: .aiConsole,
                    fields: fields,
                    channel: .text
                )
                let result = try await dependencies.textService().submit(job: request)
                let reply = AIChatMessage(role: .assistant, text: result.metadata.prompt)
                await MainActor.run {
                    messages.append(reply)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct ChatBubble: View {
    let message: AIChatMessage

    var body: some View {
        HStack {
            if message.role == .assistant { Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 4) {
                Text(message.role.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .font(.body)
            .foregroundStyle(message.role == .assistant ? .primary : Color.white)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(message.role == .assistant ? Color(nsColor: .controlBackgroundColor) : Color.accentColor)
            )
            if message.role == .user { Spacer(minLength: 0) }
        }
    }
}

private struct AIChatMessage: Identifiable {
    enum Role {
        case user
        case assistant

        var displayName: String {
            switch self {
            case .user: return "我"
            case .assistant: return "Gemini"
            }
        }
    }

    let id = UUID()
    let role: Role
    let text: String
}
