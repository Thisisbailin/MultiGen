import Foundation

@MainActor
final class ChatContextCoordinator {
    private unowned let navigationStore: NavigationStore
    private unowned let scriptStore: ScriptStore
    private unowned let storyboardStore: StoryboardStore

    init(
        navigationStore: NavigationStore,
        scriptStore: ScriptStore,
        storyboardStore: StoryboardStore
    ) {
        self.navigationStore = navigationStore
        self.scriptStore = scriptStore
        self.storyboardStore = storyboardStore
    }

    func resolveContext() -> ChatContext {
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
                let scene = episode.scenes.first(where: { $0.id == navigationStore.currentStoryboardSceneID })
                let snapshot = navigationStore.currentStoryboardSceneSnapshot
                return .storyboard(project: project, episode: episode, scene: scene, snapshot: snapshot, workspace: workspace)
            }
        case .libraryStyles, .libraryCharacters, .libraryScenes, .libraryPrompts:
            if let projectID = navigationStore.currentScriptProjectID,
               let project = projectByID(projectID) {
                return .scriptProject(project: project)
            }
        default:
            break
        }
        return .general
    }

    func module(for context: ChatContext, override: AIChatModule?) -> AIChatModule {
        if let override { return override }
        return AIChatModule.resolve(selection: navigationStore.selection, context: context)
    }

    func promptModule(for context: ChatContext, override: AIChatModule? = nil) -> PromptDocument.Module {
        if let override {
            switch override {
            case .general:
                return .aiConsole
            case .script:
                return .script
            case .storyboard:
                return .storyboard
            case .promptHelper:
                return promptHelperModule()
            case .promptHelperStyle:
                return .promptHelperStyle
            }
        }
        switch context {
        case .general:
            return .aiConsole
        case .script:
            return .script
        case .storyboard:
            return .storyboard
        case .scriptProject:
            return .scriptProjectSummary
        }
    }

    private func promptHelperModule() -> PromptDocument.Module {
        switch navigationStore.selection {
        case .libraryStyles:
            return .promptHelperStyle
        case .libraryCharacters, .libraryScenes:
            return .promptHelperCharacterScene
        default:
            return .promptHelperCharacterScene
        }
    }

    func statusDescription(for context: ChatContext) -> String {
        switch context {
        case .general:
            switch navigationStore.selection {
            case .script:
                return "上下文：剧本 · 列表"
            case .storyboard:
                return "上下文：分镜 · 列表"
            case .libraryStyles:
                return "上下文：提示词助手 · 风格库"
            case .libraryCharacters:
                return "上下文：提示词助手 · 角色库"
            case .libraryScenes:
                return "上下文：提示词助手 · 场景库"
            case .libraryPrompts:
                return "上下文：提示词助手 · 指令库"
            default:
                return "上下文：主页聊天"
            }
        case .script(_, let episode):
            return "上下文：剧本 · \(episode.displayLabel)"
        case .storyboard(_, let episode, let scene, let snapshot, let workspace):
            let count = workspace?.entries.count ?? 0
            var base = "上下文：分镜 · \(episode.displayLabel)"
            if let title = scene?.title ?? snapshot?.title {
                base += " · \(title)"
            }
            base += " · \(count) 镜头"
            return base
        case .scriptProject(let project):
            let base = defaultedProjectTitle(project)
            switch navigationStore.selection {
            case .libraryCharacters:
                return "上下文：提示词助手 · 角色 · \(base)"
            case .libraryScenes:
                return "上下文：提示词助手 · 场景 · \(base)"
            default:
                return "上下文：项目 · \(project.title)"
            }
        }
    }

    func modeDescription(for context: ChatContext) -> String {
        switch context {
        case .general:
            return "模式：主页 · 对话建议"
        case .script(_, let episode):
            return "模式：剧本 · \(episode.displayLabel)"
        case .storyboard(_, let episode, let scene, let snapshot, _):
            var base = "模式：分镜 · \(episode.displayLabel)"
            if let title = scene?.title ?? snapshot?.title {
                base += " · \(title)"
            }
            return base
        case .scriptProject(let project):
            let base = defaultedProjectTitle(project)
            switch navigationStore.selection {
            case .libraryStyles:
                return "模式：提示词助手 · 风格库 · \(base)"
            case .libraryCharacters, .libraryScenes:
                return "模式：提示词助手 · \(base)"
            case .libraryPrompts:
                return "模式：提示词助手 · 指令库"
            default:
                return "模式：项目总结 · \(project.title)"
            }
        }
    }

    func scriptProject(for context: ChatContext) -> ScriptProject? {
        switch context {
        case .script(let project, _):
            return project
        case .scriptProject(let project):
            return project
        default:
            return nil
        }
    }

    func storyboardSceneTitle() -> String? {
        navigationStore.currentStoryboardSceneSnapshot?.title
    }

    func storyboardEpisodeDisplay() -> String? {
        guard let episodeID = navigationStore.currentStoryboardEpisodeID,
              let episode = scriptEpisode(for: episodeID) else {
            return nil
        }
        let projectTitle = defaultedProjectTitle(project(for: episode.id))
        return "\(projectTitle) · \(episode.displayLabel)"
    }

    func storyboardSceneCountDescription() -> String? {
        guard let episodeID = navigationStore.currentStoryboardEpisodeID,
              let episode = scriptEpisode(for: episodeID) else {
            return nil
        }
        let count = episode.scenes.count
        if count == 0 {
            return "尚未添加场景"
        }
        return "\(count) 个场景"
    }

    func threadIdentifier(for context: ChatContext) -> ChatThreadKey {
        switch context {
        case .general:
            return .general
        case .script(_, let episode):
            return .scriptEpisode(episode.id)
        case .storyboard(_, let episode, let scene, let snapshot, _):
            if let sceneID = scene?.id ?? snapshot?.id {
                return .storyboard(sceneID)
            }
            return .storyboard(episode.id)
        case .scriptProject(let project):
            switch navigationStore.selection {
            case .libraryCharacters:
                if let targetID = navigationStore.currentLibraryCharacterID {
                    return .promptHelper(projectID: project.id, targetID: targetID)
                }
            case .libraryScenes:
                if let targetID = navigationStore.currentLibrarySceneID {
                    return .promptHelper(projectID: project.id, targetID: targetID)
                }
            default:
                break
            }
            return .project(project.id)
        }
    }

    func historyEntries(chatThreads: [ChatThreadKey: [StoredChatMessage]]) -> [ChatHistoryEntry] {
        chatThreads
            .map { key, records in
                let module = module(for: key)
                let title = historyTitle(for: key) ?? module.displayName
                let subtitle = "\(module.displayName) · \(records.count) 条消息"
                let preview = records.last?.text ?? "（无消息）"
                return ChatHistoryEntry(
                    key: key,
                    module: module,
                    title: title,
                    subtitle: subtitle,
                    preview: preview,
                    messageCount: records.count
                )
            }
            .sorted { lhs, rhs in
                lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
    }

    // MARK: - Helpers

    private func historyTitle(for key: ChatThreadKey) -> String? {
        switch key {
        case .general:
            return "通用对话"
        case .scriptEpisode(let episodeID):
            if let episode = scriptEpisode(for: episodeID) {
                let projectTitle = defaultedProjectTitle(project(for: episode.id))
                return "\(projectTitle) · \(episode.displayLabel)"
            }
            return "剧本助手"
        case .storyboard(let targetID):
            if let sceneTitle = storyboardSceneTitle(for: targetID) {
                return sceneTitle
            }
            if let episode = scriptEpisode(for: targetID) {
                let projectTitle = defaultedProjectTitle(project(for: episode.id))
                return "\(projectTitle) · \(episode.displayLabel)"
            }
            return "分镜助手"
        case .project(let projectID):
            if let project = projectByID(projectID) {
                let title = project.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalTitle = title.isEmpty ? "未命名项目" : title
                return "\(finalTitle) · 项目总结"
            }
            return "项目总结"
        case .promptHelper(let projectID, let targetID):
            let projectTitle = defaultedProjectTitle(projectByID(projectID))
            if let character = projectByID(projectID)?.mainCharacters.first(where: { $0.id == targetID }) {
                return "\(projectTitle) · 角色 · \(character.name)"
            }
            if let scene = projectByID(projectID)?.keyScenes.first(where: { $0.id == targetID }) {
                return "\(projectTitle) · 场景 · \(scene.name)"
            }
            return "\(projectTitle) · 提示词助手"
        }
    }

    private func module(for key: ChatThreadKey) -> AIChatModule {
        switch key {
        case .general:
            return .general
        case .scriptEpisode, .project:
            return .script
        case .storyboard:
            return .storyboard
        case .promptHelper:
            return .promptHelper
        }
    }

    private func scriptEpisode(for id: UUID?) -> ScriptEpisode? {
        guard let id else { return nil }
        for project in scriptStore.projects {
            if let episode = project.episodes.first(where: { $0.id == id }) {
                return episode
            }
        }
        return nil
    }

    private func project(for episodeID: UUID) -> ScriptProject? {
        scriptStore.projects.first { project in
            project.episodes.contains(where: { $0.id == episodeID })
        }
    }

    private func projectByID(_ id: UUID) -> ScriptProject? {
        scriptStore.projects.first { $0.id == id }
    }

    private func defaultedProjectTitle(_ project: ScriptProject?) -> String {
        guard let project else { return "未命名项目" }
        let trimmed = project.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名项目" : trimmed
    }

    private func storyboardSceneTitle(for sceneID: UUID) -> String? {
        for project in scriptStore.projects {
            for episode in project.episodes {
                if let scene = episode.scenes.first(where: { $0.id == sceneID }) {
                    let projectTitle = defaultedProjectTitle(project)
                    return "\(projectTitle) · \(scene.title)"
                }
            }
        }
        if let snapshot = navigationStore.currentStoryboardSceneSnapshot,
           snapshot.id == sceneID {
            return snapshot.title
        }
        return nil
    }
}
