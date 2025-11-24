import SwiftUI
import AppKit

struct AIChatSidebarView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var actionCenter: AIActionCenter
    @EnvironmentObject private var promptLibraryStore: PromptLibraryStore
    @EnvironmentObject private var navigationStore: NavigationStore
    @EnvironmentObject private var scriptStore: ScriptStore
    @EnvironmentObject private var storyboardStore: StoryboardStore

    @StateObject private var viewModel: AIChatViewModel
    @State private var expandedMessageIDs: Set<UUID> = []

    init(moduleOverride: AIChatModule? = nil) {
        _viewModel = StateObject(wrappedValue: AIChatViewModel(moduleOverride: moduleOverride))
    }

    var body: some View {
        VStack(spacing: 12) {
            ModuleAssistantSwitcher(
                module: viewModel.currentModule,
                scriptProjectTitle: viewModel.scriptProjectTitle,
                storyboardState: viewModel.storyboardAssistantState,
                onRequestSummary: viewModel.scriptProjectTitle == nil ? nil : { viewModel.requestProjectSummaryFromPanel() },
                onShowHistory: {
                    navigationStore.sidebarMode = .ai
                    navigationStore.isShowingConversationHistory = true
                },
                onStoryboardGenerate: {
                    Task { await viewModel.generateStoryboardShotsIfPossible() }
                }
            )

            ChatMessageList(
                messages: viewModel.messages,
                expandedIDs: $expandedMessageIDs
            )

            VStack(alignment: .leading, spacing: 6) {
                if viewModel.currentModule.allowsAttachments, viewModel.attachments.isEmpty == false {
                    attachmentStrip
                }
                modelStatusView
                inputComposer
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .onAppear {
            viewModel.configure(
                dependencies: dependencies,
                actionCenter: actionCenter,
                promptLibraryStore: promptLibraryStore,
                navigationStore: navigationStore,
                scriptStore: scriptStore,
                storyboardStore: storyboardStore
            )
        }
        .sheet(isPresented: historySheetBinding) {
            ChatHistorySheet(
                entries: viewModel.historyEntries,
                initialSelection: viewModel.activeThreadKey,
                memoryEnabled: viewModel.isMemoryEnabled,
                onClose: { navigationStore.isShowingConversationHistory = false },
                onSelect: { entry in
                    navigationStore.pendingThreadRequest = PendingThreadRequest(key: entry.key, module: entry.module)
                    applyNavigationContext(for: entry)
                    navigationStore.sidebarMode = .ai
                    navigationStore.isShowingConversationHistory = false
                },
                onDelete: { entry in
                    viewModel.deleteHistoryThread(entry.key)
                },
                onResetCurrent: {
                    viewModel.clearCurrentConversation()
                }
            )
            .onAppear { viewModel.presentHistory() }
        }
    }

    private var historySheetBinding: Binding<Bool> {
        Binding(
            get: { navigationStore.isShowingConversationHistory },
            set: { navigationStore.isShowingConversationHistory = $0 }
        )
    }

    private func applyNavigationContext(for entry: ChatHistoryEntry) {
        switch entry.key {
        case .general:
            navigationStore.selection = .home
            navigationStore.currentScriptEpisodeID = nil
            navigationStore.currentStoryboardEpisodeID = nil
            navigationStore.currentStoryboardSceneID = nil
            navigationStore.currentStoryboardSceneSnapshot = nil
        case .scriptEpisode(let episodeID):
            navigationStore.currentScriptEpisodeID = episodeID
            navigationStore.selection = .script
            navigationStore.currentStoryboardEpisodeID = nil
            navigationStore.currentStoryboardSceneID = nil
            navigationStore.currentStoryboardSceneSnapshot = nil
        case .project(let projectID):
            if let project = scriptStore.projects.first(where: { $0.id == projectID }),
               let episode = project.episodes.first {
                navigationStore.currentScriptEpisodeID = episode.id
            } else {
                navigationStore.currentScriptEpisodeID = nil
            }
            navigationStore.selection = .script
            navigationStore.currentStoryboardEpisodeID = nil
            navigationStore.currentStoryboardSceneID = nil
            navigationStore.currentStoryboardSceneSnapshot = nil
        case .promptHelper(let projectID, let targetID):
            navigationStore.currentScriptProjectID = projectID
            navigationStore.currentStoryboardEpisodeID = nil
            navigationStore.currentStoryboardSceneID = nil
            navigationStore.currentStoryboardSceneSnapshot = nil
            if let project = scriptStore.projects.first(where: { $0.id == projectID }) {
                navigationStore.currentScriptEpisodeID = project.episodes.first?.id
                if project.mainCharacters.contains(where: { $0.id == targetID }) {
                    navigationStore.selection = .libraryCharacters
                    navigationStore.currentLibraryCharacterID = targetID
                    navigationStore.currentLibrarySceneID = nil
                } else if project.keyScenes.contains(where: { $0.id == targetID }) {
                    navigationStore.selection = .libraryScenes
                    navigationStore.currentLibrarySceneID = targetID
                    navigationStore.currentLibraryCharacterID = nil
                } else {
                    navigationStore.selection = .libraryPrompts
                    navigationStore.currentLibraryCharacterID = nil
                    navigationStore.currentLibrarySceneID = nil
                }
            } else {
                navigationStore.selection = .libraryPrompts
                navigationStore.currentScriptEpisodeID = nil
                navigationStore.currentLibraryCharacterID = nil
                navigationStore.currentLibrarySceneID = nil
            }
        case .storyboard(let targetID):
            if let match = findStoryboardContext(for: targetID) {
                navigationStore.currentStoryboardEpisodeID = match.episodeID
                navigationStore.currentStoryboardSceneID = match.sceneID
                navigationStore.currentStoryboardSceneSnapshot = nil
            } else {
                navigationStore.currentStoryboardEpisodeID = targetID
                navigationStore.currentStoryboardSceneID = nil
                navigationStore.currentStoryboardSceneSnapshot = nil
            }
            navigationStore.currentScriptEpisodeID = nil
            navigationStore.selection = .storyboard
        }
    }

    private func findStoryboardContext(for id: UUID) -> (episodeID: UUID, sceneID: UUID?)? {
        for project in scriptStore.projects {
            for episode in project.episodes {
                if let scene = episode.scenes.first(where: { $0.id == id }) {
                    return (episode.id, scene.id)
                }
            }
        }
        for workspace in storyboardStore.workspaces {
            if workspace.episodeID == id {
                return (workspace.episodeID, nil)
            }
            if let entry = workspace.entries.first(where: { $0.id == id || $0.sceneID == id }) {
                return (workspace.episodeID, entry.sceneID ?? entry.id)
            }
        }
        return nil
    }

    private var modelStatusView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("当前路线：\(viewModel.routeDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.currentModule != .general {
                    Text(viewModel.contextStatusDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(viewModel.contextModeDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var inputComposer: some View {
            ChatInputBar(
                inputText: Binding(
                    get: { viewModel.inputText },
                    set: { viewModel.inputText = $0 }
                ),
                isSending: viewModel.isSending,
                allowsAttachments: viewModel.currentModule.allowsAttachments,
                canAddAttachments: viewModel.canAddAttachments,
                onAddAttachment: viewModel.addAttachment,
                onHistory: {
                    navigationStore.sidebarMode = .ai
                    navigationStore.isShowingConversationHistory = true
            },
            onSend: viewModel.sendMessage
        )
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: attachment.preview)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.2))
                            )
                        Button {
                            viewModel.removeAttachment(attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
        }
    }
}

enum ChatContext: Equatable {
    case general
    case script(project: ScriptProject?, episode: ScriptEpisode)
    case storyboard(project: ScriptProject?, episode: ScriptEpisode, scene: ScriptScene?, snapshot: StoryboardSceneContextSnapshot?, workspace: StoryboardWorkspace?)
    case scriptProject(project: ScriptProject)
}

private struct ChatHistorySheet: View {
    let entries: [ChatHistoryEntry]
    let memoryEnabled: Bool
    let onClose: () -> Void
    let onSelect: (ChatHistoryEntry) -> Void
    let onDelete: (ChatHistoryEntry) -> Void
    let onResetCurrent: () -> Void
    @State private var selection: ChatThreadKey?
    @State private var filter: AIChatModule? = nil

    init(
        entries: [ChatHistoryEntry],
        initialSelection: ChatThreadKey?,
        memoryEnabled: Bool,
        onClose: @escaping () -> Void,
        onSelect: @escaping (ChatHistoryEntry) -> Void,
        onDelete: @escaping (ChatHistoryEntry) -> Void,
        onResetCurrent: @escaping () -> Void
    ) {
        self.entries = entries
        self.memoryEnabled = memoryEnabled
        self.onClose = onClose
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onResetCurrent = onResetCurrent
        _selection = State(initialValue: initialSelection)
    }

    private var filteredEntries: [ChatHistoryEntry] {
        guard let filter else { return entries }
        return entries.filter { $0.module == filter }
    }

    private var selectionEntry: ChatHistoryEntry? {
        guard let selection else { return nil }
        return entries.first { $0.key == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("对话历史中心")
                    .font(.title3.bold())
                Spacer()
                Picker("筛选模块", selection: $filter) {
                    Text("全部模块").tag(AIChatModule?.none)
                    ForEach(AIChatModule.allCases, id: \.self) { module in
                        Text(module.displayName).tag(AIChatModule?.some(module))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }

            if memoryEnabled == false {
                PlaceholderBlock(title: "尚未开启对话历史") {
                    Text("请在设置的“对话历史”中打开“保存对话历史”，以记录与各模块的协同过程。")
                }
            } else if filteredEntries.isEmpty {
                PlaceholderBlock(title: "暂无符合筛选条件的历史") {
                    Text(filter == nil ? "完成首次对话后，我们会在此显示记录。" : "当前模块还没有历史记录。")
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredEntries) { entry in
                            let isSelected = selection == entry.key
                            Button {
                                selection = entry.key
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .font(.headline)
                                    Text(entry.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(entry.preview)
                                        .font(.body)
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor))
                                )
                            }
                            .buttonStyle(.plain)
                            .tag(entry.key)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(minHeight: 220)
            }

            HStack {
                Button("关闭", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("清空当前对话", role: .destructive, action: onResetCurrent)
                    .disabled(entries.isEmpty)
                Button("删除选中", role: .destructive) {
                    guard let entry = selectionEntry else { return }
                    onDelete(entry)
                    self.selection = nil
                }
                .disabled(selectionEntry == nil)
                Button("切换到此对话") {
                    guard let entry = selectionEntry else { return }
                    onSelect(entry)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectionEntry == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct PlaceholderBlock<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
                .foregroundStyle(.secondary)
        }
        Spacer()
    }
}

extension StoredChatMessage.Role {
    init(role: AIChatMessage.Role) {
        switch role {
        case .user: self = .user
        case .assistant: self = .assistant
        case .system: self = .system
        }
    }

    var asChatRole: AIChatMessage.Role {
        switch self {
        case .user: return .user
        case .assistant: return .assistant
        case .system: return .system
        }
    }
}
