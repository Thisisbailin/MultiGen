import Foundation
import Combine
import AppKit

@MainActor
final class AIChatViewModel: ObservableObject {
    @Published var messages: [AIChatMessage] = []
    @Published var inputText: String = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published private(set) var attachments: [ImageAttachment] = []
    @Published private(set) var historyEntries: [ChatHistoryEntry] = []
    @Published private(set) var currentModule: AIChatModule = .general
    @Published private(set) var contextStatusDescription: String = ""
    @Published private(set) var contextModeDescription: String = ""
    @Published private(set) var storyboardAssistantState: StoryboardAssistantDisplay = .init()

    private let projectSummaryPromptText = "请基于 projectContext 中提供的资料生成一段 250-350 字的专业项目简介，强调核心卖点、主冲突以及视听/类型特色，并指出潜在受众。"
    private let attachmentController = ChatAttachmentController()

    private var dependencies: AppDependencies?
    private var actionCenter: AIActionCenter?
    private var promptLibraryStore: PromptLibraryStore?
    private var scriptStore: ScriptStore?
    private var storyboardStore: StoryboardStore?
    private var imagingStore: ImagingStore?
    private var navigationStore: NavigationStore?
    private var contextCoordinator: ChatContextCoordinator?
    private var storyboardCoordinator: StoryboardGenerationCoordinator?
    private var currentContext: ChatContext = .general
    private let moduleOverride: AIChatModule?
    private var pendingSummaryMessageID: UUID?
    private var currentThreadKey: ChatThreadKey?
    private var isApplyingPendingThread = false
    private var isApplyingStoryboardAutomation = false
    private var cancellables: Set<AnyCancellable> = []

    init(moduleOverride: AIChatModule?) {
        self.moduleOverride = moduleOverride
    }

    var attachmentCount: Int { attachments.count }
    var canAddAttachments: Bool {
        guard currentModule.allowsAttachments else { return false }
        return attachmentController.remainingCapacity > 0
    }

    var activeThreadKey: ChatThreadKey {
        currentThreadKey ?? currentThreadIdentifier
    }

    var scriptProjectTitle: String? {
        contextCoordinator?.scriptProject(for: currentContext)?.title
    }

    var routeDescription: String {
        guard let dependencies else { return "" }
        return "\(dependencies.currentTextRoute().displayName) · \(dependencies.currentTextModelLabel())"
    }

    var isMemoryEnabled: Bool {
        dependencies?.configuration.memoryEnabled ?? false
    }

    func configure(
        dependencies: AppDependencies,
        actionCenter: AIActionCenter,
        promptLibraryStore: PromptLibraryStore,
        navigationStore: NavigationStore,
        scriptStore: ScriptStore,
        storyboardStore: StoryboardStore,
        imagingStore: ImagingStore
    ) {
        guard self.dependencies == nil else { return }
        self.dependencies = dependencies
        self.actionCenter = actionCenter
        self.promptLibraryStore = promptLibraryStore
        self.navigationStore = navigationStore
        self.scriptStore = scriptStore
        self.storyboardStore = storyboardStore
        self.imagingStore = imagingStore
        self.contextCoordinator = ChatContextCoordinator(
            navigationStore: navigationStore,
            scriptStore: scriptStore,
            storyboardStore: storyboardStore
        )
        self.storyboardCoordinator = StoryboardGenerationCoordinator(
            promptLibraryStore: promptLibraryStore,
            actionCenter: actionCenter,
            navigationStore: navigationStore
        )
        setupBindings()
        refreshModuleAndContext()
        switchThread(to: currentThreadIdentifier)
        processPendingProjectSummary()
        rebuildHistoryEntries()
        refreshStoryboardAssistantState()
    }

    func requestProjectSummaryFromPanel() {
        guard let project = contextCoordinator?.scriptProject(for: currentContext) else {
            errorMessage = "请在剧本模块选择项目"
            return
        }
        let context = ChatContext.scriptProject(project: project)
        sendProjectSummary(project, context: context, module: .scriptProjectSummary)
    }

    func sendMessage() {
        guard let navigationStore else { return }
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard isSending == false else { return }

        if navigationStore.selection == .image {
            messages.append(AIChatMessage(role: .user, text: trimmed))
            inputText = ""
            errorMessage = nil
            isSending = true
            Task { [weak self] in
                await self?.handleImagingRequest(prompt: trimmed)
            }
            return
        }

        guard let coordinator = contextCoordinator else { return }
        let context = currentContext
        let module = coordinator.promptModule(for: context)
        let origin = originLabel(for: context)
        if currentModule == .storyboard {
            navigationStore.storyboardAutomationHandler?.recordSidebarInstruction(trimmed)
        }
        guard let request = makeChatActionRequest(
            prompt: trimmed,
            context: context,
            module: module,
            kind: .conversation,
            origin: origin,
            includeMemory: true
        ) else { return }

        messages.append(AIChatMessage(role: .user, text: trimmed))
        inputText = ""
        errorMessage = nil
        isSending = true

        Task { [weak self] in
            await self?.performStream(request: request, context: context)
        }
    }

    func generateStoryboardShotsIfPossible() async {
        guard currentModule == .storyboard else { return }
        guard storyboardAssistantState.canGenerate else {
            await MainActor.run {
                errorMessage = storyboardAssistantState.warningMessage ?? "当前上下文不允许生成分镜"
            }
            return
        }
        guard await MainActor.run(body: { isSending == false }) else { return }
        guard let contextCoordinator = contextCoordinator else { return }
        guard let storyboardCoordinator = storyboardCoordinator else {
            await MainActor.run {
                errorMessage = "AI 中枢未就绪，暂无法生成分镜。"
            }
            return
        }
        guard case let .storyboard(project, episode, _, snapshot, workspace) = contextCoordinator.resolveContext(),
              let project else {
            await MainActor.run {
                errorMessage = "请在分镜模块选择有效的项目与剧集"
            }
            return
        }

        let context = ChatContext.storyboard(
            project: project,
            episode: episode,
            scene: nil,
            snapshot: snapshot,
            workspace: workspace
        )

        await MainActor.run {
            isSending = true
            messages.append(
                AIChatMessage(
                    role: .system,
                    text: "正在生成《\(episode.displayLabel)》的整集分镜…",
                    detail: nil
                )
            )
        }

        Task {
            defer { Task { @MainActor in isSending = false } }
            do {
                let outcome = try await storyboardCoordinator.generateStoryboard(
                    for: StoryboardGenerationContext(
                        project: project,
                        episode: episode,
                        snapshot: snapshot,
                        workspace: workspace
                    )
                )
                await MainActor.run {
                    handleStoryboardResult(
                        outcome.result,
                        context: context,
                        commandResult: outcome.commandResult
                    )
                }
            } catch {
                await MainActor.run {
                    if let localized = (error as? LocalizedError)?.errorDescription {
                        errorMessage = localized
                    } else {
                        errorMessage = "生成失败：\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func addAttachment() {
        guard currentModule.allowsAttachments else { return }
        attachmentController.presentAttachmentPicker { [weak self] error in
            self?.errorMessage = error
        }
    }

    func removeAttachment(_ id: UUID) {
        attachmentController.remove(id)
    }

    func selectHistoryThread(_ key: ChatThreadKey) {
        switchThread(to: key)
    }

    func presentHistory() {
        rebuildHistoryEntries()
    }

    func deleteHistoryThread(_ key: ChatThreadKey) {
        guard let navigationStore else { return }
        navigationStore.chatThreads.removeValue(forKey: key)
        if currentThreadKey == key {
            currentThreadKey = nil
            messages.removeAll()
        }
        rebuildHistoryEntries()
    }

    func clearCurrentConversation() {
        guard let coordinator = contextCoordinator else {
            messages.removeAll()
            return
        }
        let key = currentThreadKey ?? coordinator.threadIdentifier(for: currentContext)
        navigationStore?.chatThreads.removeValue(forKey: key)
        messages.removeAll()
        currentThreadKey = key
        rebuildHistoryEntries()
    }

    func consumeSystemMessageIfNeeded() {
        guard let navigationStore else { return }
        guard let message = navigationStore.pendingAIChatSystemMessage else { return }
        navigationStore.pendingAIChatSystemMessage = nil
        messages.append(AIChatMessage(role: .system, text: message))
    }

    func processPendingProjectSummary() {
        guard let navigationStore,
              let scriptStore else { return }
        guard let projectID = navigationStore.pendingProjectSummaryID else { return }
        navigationStore.pendingProjectSummaryID = nil
        guard let project = scriptStore.projects.first(where: { $0.id == projectID }) else { return }
        let context = ChatContext.scriptProject(project: project)
        sendProjectSummary(project, context: context, module: .scriptProjectSummary)
    }

    func handleMemoryToggle(enabled: Bool) {
        if enabled {
            switchThread(to: currentThreadIdentifier)
        } else {
            navigationStore?.chatThreads.removeAll()
            currentThreadKey = nil
        }
    }

    func persistThreadIfNeeded() {
        guard isMemoryEnabled, let key = currentThreadKey else { return }
        navigationStore?.chatThreads[key] = messages.map { $0.record }
    }

    func handleThreadChange() {
        if isApplyingPendingThread { return }
        let newKey = currentThreadIdentifier
        if newKey != currentThreadKey {
            switchThread(to: newKey)
        }
    }

    // MARK: - Private helpers

    private func setupBindings() {
        guard let navigationStore, let dependencies else { return }

        navigationStore.$selection
            .sink { [weak self] _ in self?.handleNavigationUpdate() }
            .store(in: &cancellables)

        navigationStore.$currentScriptEpisodeID
            .sink { [weak self] _ in self?.handleNavigationUpdate() }
            .store(in: &cancellables)

        navigationStore.$currentStoryboardEpisodeID
            .sink { [weak self] _ in self?.handleNavigationUpdate() }
            .store(in: &cancellables)

        navigationStore.$currentStoryboardSceneID
            .sink { [weak self] _ in self?.handleNavigationUpdate() }
            .store(in: &cancellables)

        navigationStore.$currentStoryboardSceneSnapshot
            .sink { [weak self] _ in self?.handleNavigationUpdate() }
            .store(in: &cancellables)

        navigationStore.$pendingProjectSummaryID
            .sink { [weak self] _ in self?.processPendingProjectSummary() }
            .store(in: &cancellables)

        navigationStore.$pendingAIChatSystemMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.consumeSystemMessageIfNeeded() }
            .store(in: &cancellables)

        navigationStore.$chatThreads
            .sink { [weak self] _ in self?.rebuildHistoryEntries() }
            .store(in: &cancellables)

        navigationStore.$pendingThreadRequest
            .compactMap { $0 }
            .sink { [weak self] key in
                guard let self else { return }
                guard key.module == self.currentModule else { return }
                self.isApplyingPendingThread = true
                self.switchThread(to: key.key)
                self.isApplyingPendingThread = false
                self.navigationStore?.pendingThreadRequest = nil
            }
            .store(in: &cancellables)

        dependencies.configuration.$memoryEnabled
            .sink { [weak self] enabled in self?.handleMemoryToggle(enabled: enabled) }
            .store(in: &cancellables)

        attachmentController.$attachments
            .sink { [weak self] value in
                self?.attachments = value
            }
            .store(in: &cancellables)

        $messages
            .dropFirst()
            .sink { [weak self] _ in self?.persistThreadIfNeeded() }
            .store(in: &cancellables)
    }

    private func handleNavigationUpdate() {
        refreshModuleAndContext()
        handleThreadChange()
        rebuildHistoryEntries()
        refreshStoryboardAssistantState()
    }

    private func refreshModuleAndContext() {
        guard let coordinator = contextCoordinator else { return }
        currentContext = coordinator.resolveContext()
        currentModule = coordinator.module(for: currentContext, override: moduleOverride)
        contextStatusDescription = coordinator.statusDescription(for: currentContext)
        contextModeDescription = coordinator.modeDescription(for: currentContext)
    }

    private func sendProjectSummary(_ project: ScriptProject, context: ChatContext, module: PromptDocument.Module) {
        guard isSending == false else { return }
        isSending = true
        errorMessage = nil
        let systemMessage = AIChatMessage(role: .system, text: "正在生成《\(project.title)》的项目总结...")
        messages.append(systemMessage)
        pendingSummaryMessageID = systemMessage.id

        Task { [weak self] in
            guard let self else { return }
            guard let request = self.makeChatActionRequest(
                prompt: self.projectSummaryPromptText,
                context: context,
                module: module,
                kind: .projectSummary,
                origin: self.originLabel(for: context)
            ) else { return }
            self.messages.append(AIChatMessage(role: .assistant, text: "（正在生成...）", detail: nil))
            let placeholderID = self.messages.last!.id
            do {
                let pipeline = AIChatStreamingPipeline(actionCenter: self.actionCenter!)
                let outcome = try await pipeline.run(request: request) { partial in
                    if let idx = self.messages.firstIndex(where: { $0.id == placeholderID }) {
                        self.messages[idx] = AIChatMessage(id: placeholderID, role: .assistant, text: partial)
                    }
                }
                if let result = outcome.result {
                    self.handleAIResponse(result: result, context: context, targetMessageID: placeholderID)
                    let finalText = (result.text ?? outcome.collectedText).trimmingCharacters(in: .whitespacesAndNewlines)
                    if finalText.isEmpty == false {
                        await self.persistProjectSummary(finalText, project: project)
                    }
                } else if let idx = self.messages.firstIndex(where: { $0.id == placeholderID }) {
                    self.messages[idx] = AIChatMessage(id: placeholderID, role: .assistant, text: outcome.collectedText)
                }
            } catch {
                self.errorMessage = "生成失败：\(error.localizedDescription)"
            }
            self.isSending = false
            self.pendingSummaryMessageID = nil
        }
    }

    private func performStream(request: AIActionRequest, context: ChatContext) async {
        guard let actionCenter else { return }
        messages.append(AIChatMessage(role: .assistant, text: "（正在生成...）", detail: nil))
        let placeholderID = messages.last!.id

        do {
            let pipeline = AIChatStreamingPipeline(actionCenter: actionCenter)
            let outcome = try await pipeline.run(request: request) { partial in
                if let index = self.messages.firstIndex(where: { $0.id == placeholderID }) {
                    self.messages[index] = AIChatMessage(id: placeholderID, role: .assistant, text: partial)
                }
            }
            if let result = outcome.result {
                handleAIResponse(result: result, context: context, targetMessageID: placeholderID)
                applyStoryboardAutomationIfNeeded(result: result, context: context)
            } else if let index = messages.firstIndex(where: { $0.id == placeholderID }) {
                messages[index] = AIChatMessage(id: placeholderID, role: .assistant, text: outcome.collectedText)
            }
        } catch {
            errorMessage = "请求失败：\(error.localizedDescription)"
            if let index = messages.firstIndex(where: { $0.id == placeholderID }) {
                messages.remove(at: index)
            }
        }
        attachmentController.reset()
        isSending = false
    }

    private func handleImagingRequest(prompt: String) async {
        guard let actionCenter,
              let dependencies,
              let navigationStore,
              let imagingStore else { return }
        let payloads = attachments.map { $0.payload }
        await imagingStore.generateImage(
            prompt: prompt,
            attachments: payloads,
            actionCenter: actionCenter,
            dependencies: dependencies,
            navigationStore: navigationStore,
            summary: "影像模块 · \(imagingStore.selectedSegment.title)"
        )
        attachmentController.reset()
        isSending = false
        persistThreadIfNeeded()
    }

    private var currentThreadIdentifier: ChatThreadKey {
        guard let coordinator = contextCoordinator else { return .general }
        return coordinator.threadIdentifier(for: currentContext)
    }

    private func switchThread(to newKey: ChatThreadKey) {
        guard let navigationStore else { return }
        if isMemoryEnabled == false {
            currentThreadKey = newKey
            messages.removeAll()
            return
        }
        persistThreadIfNeeded()
        currentThreadKey = newKey
        if let stored = navigationStore.chatThreads[newKey] {
            messages = stored.map { AIChatMessage(record: $0) }
        } else {
            navigationStore.chatThreads[newKey] = []
            messages.removeAll()
        }
    }

    private func rebuildHistoryEntries() {
        guard isMemoryEnabled, let navigationStore else {
            historyEntries = []
            return
        }
        guard let coordinator = contextCoordinator else {
            historyEntries = []
            return
        }
        historyEntries = coordinator.historyEntries(chatThreads: navigationStore.chatThreads)
    }

    private func handleAIResponse(result: AIActionResult, context: ChatContext, targetMessageID: UUID?) {
        let detail = """
        Route: \(result.route.displayName)
        Model: \(result.metadata.model)
        Duration: \(result.metadata.duration)s
        """
        if let targetMessageID,
           let index = messages.firstIndex(where: { $0.id == targetMessageID }) {
            messages[index] = AIChatMessage(
                id: targetMessageID,
                role: .assistant,
                text: result.text ?? "(无文本输出)",
                detail: detail
            )
        } else {
            messages.append(
                AIChatMessage(
                    role: .assistant,
                    text: result.text ?? "(无文本输出)",
                    detail: detail
                )
            )
        }
        if let summaryID = pendingSummaryMessageID,
           let index = messages.firstIndex(where: { $0.id == summaryID }) {
            messages.remove(at: index)
        }
    }

    private func persistProjectSummary(_ summary: String, project: ScriptProject) async {
        await MainActor.run {
            scriptStore?.updateProject(id: project.id) { editable in
                editable.synopsis = summary
            }
            navigationStore?.pendingAIChatSystemMessage = "项目《\(project.title)》简介已更新。"
        }
    }

    private func makeChatActionRequest(
        prompt: String,
        context: ChatContext,
        module: PromptDocument.Module,
        kind: AIActionKind,
        origin: String,
        includeMemory: Bool = false
    ) -> AIActionRequest? {
        guard let coordinator = contextCoordinator else { return nil }
        var fields = makeRequestFields(prompt: prompt, context: context, module: module)
        if includeMemory, let memoryContext = makeMemoryContext() {
            fields["memoryContext"] = memoryContext
        }
        let summary = coordinator.statusDescription(for: context)
        return AIActionRequest(
            kind: kind,
            action: .aiConsole,
            channel: .text,
            fields: fields,
            assetReferences: attachments.map(\.fileName),
            module: module,
            context: context,
            contextSummaryOverride: summary,
            origin: origin
        )
    }

    private func makeRequestFields(
        prompt: String,
        context: ChatContext,
        module: PromptDocument.Module
    ) -> [String: String] {
        guard let promptLibraryStore else { return [:] }
        let systemPrompt = promptLibraryStore.document(for: module)
            .content.trimmingCharacters(in: .whitespacesAndNewlines)
        var fields = AIChatRequestBuilder.makeFields(
            prompt: prompt,
            context: context,
            module: module,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
        )
        if attachments.isEmpty == false {
            fields["imageAttachmentCount"] = "\(attachments.count)"
            for (index, attachment) in attachments.enumerated() {
                let key = "imageAttachment\(index + 1)"
                fields["\(key)FileName"] = attachment.fileName
                fields["\(key)Base64"] = attachment.base64String
            }
        }
        return fields
    }

    private func makeMemoryContext(maxMessages: Int = 8) -> String? {
        guard dependencies?.configuration.aiMemoryEnabled == true else { return nil }
        guard currentModule.supportsMemory else { return nil }
        let key = currentThreadKey ?? currentThreadIdentifier
        let records = navigationStore?.chatThreads[key] ?? []
        guard records.isEmpty == false else { return nil }
        let recent = records.suffix(maxMessages)
        let lines = recent.map { record -> String in
            let speaker: String
            switch record.role {
            case .user: speaker = "用户"
            case .assistant: speaker = "助手"
            case .system: speaker = "系统"
            }
            return "\(speaker)：\(record.text)"
        }
        let combined = lines.joined(separator: "\n")
        if combined.count > 6000 {
            return String(combined.suffix(6000))
        }
        return combined
    }

    private func handleStoryboardResult(
        _ result: AIActionResult?,
        context: ChatContext,
        commandResult: StoryboardAICommandResult?
    ) {
        guard let text = result?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.isEmpty == false else {
            messages.append(AIChatMessage(role: .assistant, text: "分镜助手完成，但未收到有效数据。"))
            return
        }

        let parser = StoryboardResponseParser()
        let parsedEntries = parser.parseEntries(from: text, nextShotNumber: 1)
        let shotCount = parsedEntries.count

        let episodeLabel: String
        if case let .storyboard(_, episode, _, _, _) = context {
            episodeLabel = episode.displayLabel
        } else {
            episodeLabel = "当前剧集"
        }

        let touched = commandResult?.touchedEntries ?? shotCount
        let summary: String
        if touched > 0 {
            summary = "《\(episodeLabel)》分镜生成完成，更新 \(touched) 个镜头，可在分镜面板中查看。"
        } else {
            summary = "《\(episodeLabel)》分镜生成完成，但未解析出镜头，请检查详情。"
        }

        messages.append(
            AIChatMessage(
                role: .assistant,
                text: summary,
                detail: text
            )
        )
        if let warning = commandResult?.warning {
            messages.append(
                AIChatMessage(
                    role: .system,
                    text: warning
                )
            )
        }
        refreshStoryboardAssistantState()
    }

    private func originLabel(for context: ChatContext) -> String {
        switch context {
        case .general:
            return "智能协同"
        case .script:
            return "剧本助手"
        case .storyboard:
            return "分镜助手"
        case .scriptProject:
            return "项目总结"
        }
    }

    private func applyStoryboardAutomationIfNeeded(result: AIActionResult, context: ChatContext) {
        guard case .storyboard = context else { return }
        guard let responseText = result.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              responseText.isEmpty == false else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard isApplyingStoryboardAutomation == false else { return }
            guard let handler = self.navigationStore?.storyboardAutomationHandler else { return }
            isApplyingStoryboardAutomation = true
            let commandResult = handler.applySidebarAIResponse(responseText)
            self.handleStoryboardResult(result, context: context, commandResult: commandResult)
            isApplyingStoryboardAutomation = false
        }
    }

    private func refreshStoryboardAssistantState() {
        guard let coordinator = contextCoordinator else {
            storyboardAssistantState = .init(
                episodeLabel: nil,
                sceneCountLabel: nil,
                activeSceneTitle: nil,
                canGenerate: false,
                warningMessage: "尚未加载分镜上下文"
            )
            return
        }

        guard case let .storyboard(_, episode, _, _, workspace) = coordinator.resolveContext() else {
            storyboardAssistantState = .init(
                episodeLabel: nil,
                sceneCountLabel: nil,
                activeSceneTitle: nil,
                canGenerate: false,
                warningMessage: "请在分镜模块选择项目与剧集"
            )
            return
        }

        let sceneCount = episode.scenes.count
        let sceneCountLabel = sceneCount > 0 ? "\(sceneCount) 个场景" : "暂无场景"
        let activeScene = coordinator.storyboardSceneTitle()
        var warning: String?
        var canGenerate = true
        if sceneCount == 0 {
            warning = "当前剧集尚未添加场景"
            canGenerate = false
        }

        storyboardAssistantState = .init(
            episodeLabel: episode.displayLabel,
            sceneCountLabel: sceneCountLabel,
            activeSceneTitle: activeScene,
            canGenerate: canGenerate,
            warningMessage: warning,
            hasExistingShots: (workspace?.entries.isEmpty == false)
        )
    }
}

struct StoryboardAssistantDisplay: Equatable {
    var episodeLabel: String?
    var sceneCountLabel: String?
    var activeSceneTitle: String?
    var canGenerate: Bool
    var warningMessage: String?
    var hasExistingShots: Bool

    init(
        episodeLabel: String? = nil,
        sceneCountLabel: String? = nil,
        activeSceneTitle: String? = nil,
        canGenerate: Bool = false,
        warningMessage: String? = nil,
        hasExistingShots: Bool = false
    ) {
        self.episodeLabel = episodeLabel
        self.sceneCountLabel = sceneCountLabel
        self.activeSceneTitle = activeSceneTitle
        self.canGenerate = canGenerate
        self.warningMessage = warningMessage
        self.hasExistingShots = hasExistingShots
    }
}
