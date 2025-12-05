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
    @EnvironmentObject private var styleLibraryStore: StyleLibraryStore
    @EnvironmentObject private var navigationStore: NavigationStore
    @State private var showingNewProjectSheet = false
    @State private var projectName: String = ""
    @State private var writingTitle: String = ""
    @State private var scriptTitle: String = ""
    @State private var scriptType: ScriptProject.ProjectType = .standalone

    
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
                            Button {
                                showingNewProjectSheet = true
                            } label: {
                                Label("新建项目", systemImage: "plus")
                            }
                            .help("创建项目容器（写作+剧本&分镜）")
                        }
                        ToolbarItem(placement: .destructiveAction) {
                            if let projectID = navigationStore.currentScriptProjectID {
                                Button(role: .destructive) {
                                    scriptStore.removeProject(id: projectID)
                                    navigationStore.currentScriptProjectID = scriptStore.containers.first?.id
                                    navigationStore.currentScriptEpisodeID = nil
                                } label: {
                                    Label("删除项目", systemImage: "trash")
                                }
                                .help("删除当前选中的项目容器")
                            }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            SettingsLink {
                                Label("设置", systemImage: "slider.horizontal.3")
                            }
                            .help("打开中转线路设置与模型管理")
                        }
                    }
                }
                .sheet(isPresented: $navigationStore.showPainPointSheet) {
                    PainPointSheetView(painPoints: PainPointCatalog.corePainPoints)
                        .frame(minWidth: 520, minHeight: 420)
                }
                .sheet(isPresented: $showingNewProjectSheet) {
                    HomeNewProjectSheet(
                        projectName: $projectName,
                        writingTitle: $writingTitle,
                        scriptTitle: $scriptTitle,
                        scriptType: $scriptType,
                        onCreate: createProjectFromHome,
                        onCancel: {
                            resetProjectForm()
                            showingNewProjectSheet = false
                        }
                    )
                    .frame(minWidth: 520, minHeight: 420)
                }
        }
        .toolbarBackground(.visible, for: .automatic)
        .task { }
        .preferredColorScheme(configuration.appearance.colorScheme)
    }

    @ViewBuilder
    private func detailView(for item: SidebarItem) -> some View {
        switch item {
        case .home:
            HomeWorkspaceView(
                textModelLabel: dependencies.currentTextModelLabel(),
                textRouteLabel: dependencies.currentTextRoute().displayName
            )
            .environmentObject(scriptStore)
            .environmentObject(navigationStore)
            .navigationTitle("MultiGen 控制台")
        case .writing:
            WritingView()
                .navigationTitle("写作")
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
        case .libraryStyles, .libraryCharacters, .libraryScenes, .libraryPrompts:
            if item == .libraryPrompts {
                PromptLibraryView()
                    .environmentObject(promptLibraryStore)
                    .environmentObject(scriptStore)
                    .environmentObject(navigationStore)
                    .navigationTitle("指令资料库")
            } else if item == .libraryStyles {
                StyleLibraryView()
                    .environmentObject(styleLibraryStore)
                    .environmentObject(promptLibraryStore)
                    .environmentObject(actionCenter)
                    .navigationTitle("风格资料库")
            } else if item == .libraryCharacters {
                CharacterLibraryView()
                    .environmentObject(scriptStore)
                    .environmentObject(navigationStore)
                    .navigationTitle("角色资料库")
            } else if item == .imaging {
                ImagingConsoleView()
                    .environmentObject(actionCenter)
                    .environmentObject(promptLibraryStore)
                    .navigationTitle("影像生成")
            } else if item == .libraryScenes {
                SceneLibraryView()
                    .environmentObject(scriptStore)
                    .environmentObject(navigationStore)
                    .navigationTitle("场景资料库")
            } else {
                LibraryPlaceholderView(title: item.title)
            }
        case .imaging:
            ImagingConsoleView()
                .environmentObject(actionCenter)
                .environmentObject(promptLibraryStore)
                .navigationTitle("影像生成")
        }
    }

}

private extension ContentView {
    func createProjectFromHome() {
        let projectTitle = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalProjectTitle = projectTitle.isEmpty ? "未命名项目" : projectTitle
        let finalWritingTitle = writingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? finalProjectTitle : writingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalScriptTitle = scriptTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? finalProjectTitle : scriptTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        let container = scriptStore.addProject(
            title: finalProjectTitle,
            synopsis: "",
            type: scriptType,
            writingTitle: finalWritingTitle,
            scriptTitle: finalScriptTitle,
            addDefaultEpisode: true
        )
        navigationStore.currentScriptProjectID = container.id
        navigationStore.currentScriptEpisodeID = scriptStore.project(id: container.id)?.orderedEpisodes.first?.id
        navigationStore.selection = .home
        resetProjectForm()
        showingNewProjectSheet = false
    }

    func resetProjectForm() {
        projectName = ""
        writingTitle = ""
        scriptTitle = ""
        scriptType = .standalone
    }

}


struct HomeNewProjectSheet: View {
    @Binding var projectName: String
    @Binding var writingTitle: String
    @Binding var scriptTitle: String
    @Binding var scriptType: ScriptProject.ProjectType
        var onCreate: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建项目容器")
                .font(.title2.bold())
            TextField("项目名称", text: $projectName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("写作文本")
                    .font(.headline)
                TextField("写作文本标题（默认同项目名）", text: $writingTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("剧本 & 分镜")
                    .font(.headline)
                TextField("剧本名称（默认同项目名或导入文件名）", text: $scriptTitle)
                    .textFieldStyle(.roundedBorder)
                Picker("剧本类型", selection: $scriptType) {
                    ForEach(ScriptProject.ProjectType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                            }

            Spacer()
            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    onCancel()
                }
                Button("创建") {
                    onCreate()
                }
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && scriptTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && writingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}

enum SidebarItem: String, Identifiable {
    case home
    case writing
    case script
    case storyboard
    case imaging
    case libraryStyles
    case libraryCharacters
    case libraryScenes
    case libraryPrompts

    static let primaryItems: [SidebarItem] = [.home, .writing, .script, .storyboard, .imaging]
    static let libraryItems: [SidebarItem] = [.libraryStyles, .libraryCharacters, .libraryScenes, .libraryPrompts]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "主页"
        case .writing: return "写作"
        case .script: return "剧本"
        case .storyboard: return "分镜"
        case .imaging: return "影像"
        case .libraryStyles: return "风格"
        case .libraryCharacters: return "角色"
        case .libraryScenes: return "场景"
        case .libraryPrompts: return "指令"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .writing: return "pencil.and.outline"
        case .script: return "book.pages"
        case .storyboard: return "rectangle.3.offgrid"
        case .imaging: return "photo.stack"
        case .libraryStyles: return "paintpalette"
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
    case promptHelper(projectID: UUID, targetID: UUID)
}

struct PendingThreadRequest: Equatable {
    let key: ChatThreadKey
    let module: AIChatModule
}

struct PromptHelperRequest: Equatable {
    enum Target: String {
        case character
        case scene
    }

    let projectID: UUID
    let targetID: UUID
    let target: Target
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
    @Published var currentLibraryCharacterID: UUID?
    @Published var currentLibrarySceneID: UUID?
    @Published var pendingProjectSummaryID: UUID?
    @Published var pendingPromptHelper: PromptHelperRequest?
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
                    Text("以下痛点来自一线创作需求，MultiGen 通过剧本与分镜模块逐步解决。")
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
