//
//  ContentView.swift
//  MultiGen
//
//  Created by Joe on 2025/11/12.
//

import SwiftUI
import Combine
import AppKit

struct ContentView: View {
    @EnvironmentObject private var configuration: AppConfiguration
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var actionCenter: AIActionCenter
    @EnvironmentObject private var scriptStore: ScriptStore
    @EnvironmentObject private var storyboardStore: StoryboardStore
    @EnvironmentObject private var promptLibraryStore: PromptLibraryStore
    @EnvironmentObject private var navigationStore: NavigationStore

    var body: some View {
        NavigationSplitView(columnVisibility: $navigationStore.columnVisibility) {
            VStack(spacing: 12) {
                if navigationStore.sidebarMode == .projects {
                    SidebarProjectList(selection: $navigationStore.selection)
                } else {
                    AICollaborationModule()
                        .environmentObject(dependencies)
                        .environmentObject(promptLibraryStore)
                        .environmentObject(actionCenter)
                        .environmentObject(scriptStore)
                        .environmentObject(storyboardStore)
                        .environmentObject(navigationStore)
                }
            }
            .padding(12)
            .navigationSplitViewColumnWidth(
                min: navigationStore.sidebarMode == .ai ? 360 : 180,
                ideal: navigationStore.sidebarMode == .ai ? 480 : 200
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction)  {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            navigationStore.sidebarMode = navigationStore.sidebarMode == .ai ? .projects : .ai
                        }
                    } label: {
                        Image(systemName: "sparkle")
                            .imageScale(.large)
                            .symbolVariant(.fill)
                            .foregroundStyle(
                                navigationStore.sidebarMode == .ai
                                ? Color.accentColor
                                : Color.secondary.opacity(0.7)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("切换智能协同模式")
                    .help(
                        navigationStore.sidebarMode == .ai
                        ? "点击返回项目模式"
                        : "激活智能协同模式"
                    )
                }
            }
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
                        ToolbarItem(placement: .primaryAction) {
                            SettingsLink {
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
        }
        .toolbarBackground(.hidden, for: .automatic)
        .task { }
        .preferredColorScheme(configuration.appearance.colorScheme)
    }

    @ViewBuilder
    private func detailView(for item: SidebarItem) -> some View {
        switch item {
        case .home:
            HomeDashboardView(
                textModelLabel: dependencies.currentTextModelLabel(),
                imageModelLabel: dependencies.currentImageModelLabel(),
                textRouteLabel: dependencies.currentTextRoute().displayName,
                imageRouteLabel: dependencies.currentImageRoute().displayName
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
                    defaultProjectID: navigationStore.currentStoryboardProjectID,
                    defaultEpisodeID: navigationStore.currentStoryboardEpisodeID
                )
            }
                .navigationTitle("分镜")
        case .image:
            ImagingView()
                .navigationTitle("影像")
        case .libraryCharacters, .libraryScenes, .libraryPrompts:
            if item == .libraryPrompts {
                PromptLibraryView()
                    .environmentObject(promptLibraryStore)
                    .environmentObject(scriptStore)
                    .environmentObject(navigationStore)
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

enum ChatThreadKey: Hashable {
    case general
    case scriptEpisode(UUID)
    case storyboard(UUID)
    case project(UUID)
    case image
}

struct PendingThreadRequest: Equatable {
    let key: ChatThreadKey
    let module: AIChatModule
}

struct StoredChatMessage: Equatable {
    enum Role: String {
        case user
        case assistant
        case system
    }

    let id: UUID
    let role: Role
    let text: String
    let detail: String?
}


@MainActor
final class NavigationStore: ObservableObject {
    private enum Keys {
        static let scriptProjectID = "navigation.script.project"
        static let scriptEpisodeID = "navigation.script.episode"
        static let storyboardProjectID = "navigation.storyboard.project"
        static let storyboardEpisodeID = "navigation.storyboard.episode"
        static let storyboardSceneID = "navigation.storyboard.scene"
    }

    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    @Published var sidebarMode: SidebarMode = .projects
    @Published var selection: SidebarItem = .home
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var showPainPointSheet = false
    @Published var currentScriptProjectID: UUID?
    @Published var currentScriptEpisodeID: UUID?
    @Published var currentStoryboardProjectID: UUID?
    @Published var currentStoryboardEpisodeID: UUID?
    @Published var currentStoryboardSceneID: UUID?
    @Published var currentStoryboardSceneSnapshot: StoryboardSceneContextSnapshot?
    @Published var pendingProjectSummaryID: UUID?
    @Published var pendingAIChatSystemMessage: String?
    @Published var chatThreads: [ChatThreadKey: [StoredChatMessage]] = [:]
    @Published var isShowingConversationHistory = false
    @Published var pendingThreadRequest: PendingThreadRequest?
    weak var storyboardAutomationHandler: (any StoryboardAutomationHandling)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currentScriptProjectID = NavigationStore.readUUID(forKey: Keys.scriptProjectID, defaults: defaults)
        currentScriptEpisodeID = NavigationStore.readUUID(forKey: Keys.scriptEpisodeID, defaults: defaults)
        currentStoryboardProjectID = NavigationStore.readUUID(forKey: Keys.storyboardProjectID, defaults: defaults)
        currentStoryboardEpisodeID = NavigationStore.readUUID(forKey: Keys.storyboardEpisodeID, defaults: defaults)
        currentStoryboardSceneID = NavigationStore.readUUID(forKey: Keys.storyboardSceneID, defaults: defaults)
        setupPersistence()
    }

    private func setupPersistence() {
        $currentScriptProjectID
            .sink { [weak self] in self?.persist($0, key: Keys.scriptProjectID) }
            .store(in: &cancellables)
        $currentScriptEpisodeID
            .sink { [weak self] in self?.persist($0, key: Keys.scriptEpisodeID) }
            .store(in: &cancellables)
        $currentStoryboardProjectID
            .sink { [weak self] in self?.persist($0, key: Keys.storyboardProjectID) }
            .store(in: &cancellables)
        $currentStoryboardEpisodeID
            .sink { [weak self] in self?.persist($0, key: Keys.storyboardEpisodeID) }
            .store(in: &cancellables)
        $currentStoryboardSceneID
            .sink { [weak self] in self?.persist($0, key: Keys.storyboardSceneID) }
            .store(in: &cancellables)
    }

    private func persist(_ id: UUID?, key: String) {
        if let id {
            defaults.set(id.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func readUUID(forKey key: String, defaults: UserDefaults) -> UUID? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return UUID(uuidString: raw)
    }
}

struct StoryboardSceneContextSnapshot: Equatable {
    var id: UUID?
    var title: String
    var order: Int?
    var summary: String
    var body: String
}

private struct PainPointSheetView: View {
    let painPoints: [PainPoint]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("AIGC 剧本/分镜创作痛点")
                        .font(.title2.bold())
                    Text("以下痛点来自一线创作需求，MultiGen 通过剧本、分镜与影像模块逐步解决。")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    ForEach(painPoints) { painPoint in
                        PainPointRow(painPoint: painPoint)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(nsColor: .underPageBackgroundColor))
                            )
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 500, minHeight: 420)
            .navigationTitle("痛点说明")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
