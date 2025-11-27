import Foundation

enum StoryboardGenerationError: LocalizedError {
    case missingScenes
    case invalidContext

    var errorDescription: String? {
        switch self {
        case .missingScenes:
            return "当前剧集尚无场景，无法生成分镜。请先在剧本模块补充完整。"
        case .invalidContext:
            return "分镜上下文不完整，无法发起生成。"
        }
    }
}

struct StoryboardGenerationContext {
    let project: ScriptProject
    let episode: ScriptEpisode
    let snapshot: StoryboardSceneContextSnapshot?
    let workspace: StoryboardWorkspace?
}

struct StoryboardGenerationOutcome {
    let result: AIActionResult
    let commandResult: StoryboardAICommandResult?

    var touchedEntries: Int {
        commandResult?.touchedEntries ?? 0
    }

    var warning: String? {
        commandResult?.warning
    }
}

@MainActor
final class StoryboardGenerationCoordinator {
    private unowned let promptLibraryStore: PromptLibraryStore
    private unowned let actionCenter: AIActionCenter
    private unowned let navigationStore: NavigationStore

    init(
        promptLibraryStore: PromptLibraryStore,
        actionCenter: AIActionCenter,
        navigationStore: NavigationStore
    ) {
        self.promptLibraryStore = promptLibraryStore
        self.actionCenter = actionCenter
        self.navigationStore = navigationStore
    }

    func generateStoryboard(for context: StoryboardGenerationContext) async throws -> StoryboardGenerationOutcome {
        guard context.episode.scenes.isEmpty == false else {
            throw StoryboardGenerationError.missingScenes
        }

        let chatContext = ChatContext.storyboard(
            project: context.project,
            episode: context.episode,
            scene: nil,
            snapshot: context.snapshot,
            workspace: context.workspace
        )
        let systemPrompt = promptLibraryStore.document(for: .storyboard).content

        let fields = StoryboardPromptBuilder(
            project: context.project,
            episode: context.episode,
            scenes: context.episode.scenes,
            workspace: context.workspace,
            systemPrompt: systemPrompt
        ).makeFields()

        let request = AIActionRequest(
            kind: .storyboardOperation,
            action: .generateScene,
            channel: .text,
            fields: fields,
            assetReferences: [],
            module: .storyboard,
            context: chatContext,
            contextSummaryOverride: "分镜 · \(context.episode.displayLabel) · 整集生成",
            origin: "分镜助手"
        )

        let result = try await actionCenter.perform(request)
        var commandResult: StoryboardAICommandResult?
        if let response = result.text {
            commandResult = await MainActor.run {
                navigationStore.storyboardAutomationHandler?.applySidebarAIResponse(response)
            }
        }
        return StoryboardGenerationOutcome(result: result, commandResult: commandResult)
    }
}
