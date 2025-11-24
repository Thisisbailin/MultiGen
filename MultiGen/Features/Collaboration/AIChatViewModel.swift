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

    private let projectSummaryPromptText = """
请阅读 projectContext 中提供的剧本全文（按集与场景顺序，仅包含项目名与剧本文本），返回 JSON 结构：
{
  "overview": "项目简介，100-300字，概括题材/类型、主冲突、叙事或视听特色、目标受众",
  "tags": ["类型/风格标签，用简短词语，如科幻","都市","悬疑"],
  "characters": [
    {"name": "角色名", "role": "角色标签，如男主/女主/反派/配角", "profile": "人物设定（动机/人设/矛盾点等，简洁）"}
  ],
  "scenes": [
    {"name": "场景名称", "description": "场景描述（含氛围/功能）", "episodes": [1,2]}
  ]
}
要求：严格按上述字段输出有效 JSON；只列核心人物与关键场景；不要包含额外说明文字或 Markdown 代码块围栏。
"""
    private let attachmentController = ChatAttachmentController()

    private var dependencies: AppDependencies?
    private var actionCenter: AIActionCenter?
    private var promptLibraryStore: PromptLibraryStore?
    private var scriptStore: ScriptStore?
    private var storyboardStore: StoryboardStore?
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
        storyboardStore: StoryboardStore
    ) {
        guard self.dependencies == nil else { return }
        self.dependencies = dependencies
        self.actionCenter = actionCenter
        self.promptLibraryStore = promptLibraryStore
        self.navigationStore = navigationStore
        self.scriptStore = scriptStore
        self.storyboardStore = storyboardStore
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
        processPendingPromptHelper()
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

        guard let coordinator = contextCoordinator else { return }
        let context = currentContext
        let module = coordinator.promptModule(for: context, override: currentModule)
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

        let userImages = attachments.map(\.preview)
        messages.append(AIChatMessage(role: .user, text: trimmed, images: userImages))
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

    func processPendingPromptHelper() {
        guard let navigationStore,
              let scriptStore else { return }
        guard let request = navigationStore.pendingPromptHelper else { return }
        navigationStore.pendingPromptHelper = nil
        guard let project = scriptStore.projects.first(where: { $0.id == request.projectID }) else {
            errorMessage = "未找到项目，无法生成提示词"
            return
        }
        let context: ChatContext = .general
        let prompt = promptHelperPrompt(for: request, project: project)
        guard prompt.isEmpty == false else {
            errorMessage = "缺少必要信息，无法生成提示词"
            return
        }
        let module: PromptDocument.Module = .promptHelperCharacterScene
        sendPromptHelper(prompt: prompt, context: context, project: project, request: request, module: module)
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

        navigationStore.$currentScriptProjectID
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

        navigationStore.$currentLibraryCharacterID
            .sink { [weak self] _ in self?.handleNavigationUpdate() }
            .store(in: &cancellables)

        navigationStore.$currentLibrarySceneID
            .sink { [weak self] _ in self?.handleNavigationUpdate() }
            .store(in: &cancellables)

        navigationStore.$pendingProjectSummaryID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.processPendingProjectSummary()
                }
            }
            .store(in: &cancellables)

        navigationStore.$pendingPromptHelper
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.processPendingPromptHelper()
                }
            }
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
            guard let actionCenter = self.actionCenter else {
                await MainActor.run {
                    self.errorMessage = "AI 中枢尚未就绪，稍后再试。"
                }
                return
            }
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
                let pipeline = AIChatStreamingPipeline(actionCenter: actionCenter)
                let outcome = try await pipeline.run(request: request) { partial in
                    if let idx = self.messages.firstIndex(where: { $0.id == placeholderID }) {
                        self.messages[idx] = AIChatMessage(id: placeholderID, role: .assistant, text: partial)
                    }
                }
                if let result = outcome.result {
                    self.handleAIResponse(result: result, context: context, targetMessageID: placeholderID)
                    let finalText = (result.text ?? outcome.collectedText).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let payload = self.parseProjectPayload(from: finalText) {
                        await self.applyProjectPayload(payload, project: project)
                    } else if finalText.isEmpty == false {
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

    private func sendPromptHelper(
        prompt: String,
        context: ChatContext,
        project: ScriptProject,
        request: PromptHelperRequest,
        module: PromptDocument.Module
    ) {
        guard isSending == false else { return }
        isSending = true
        errorMessage = nil
        let targetLabel = request.target == .character ? "角色" : "场景"
        messages.append(AIChatMessage(role: .system, text: "正在生成\(targetLabel)提示词…"))

        Task { [weak self] in
            guard let self else { return }
            guard let actionCenter = self.actionCenter else {
                await MainActor.run {
                    self.errorMessage = "AI 中枢尚未就绪，稍后再试。"
                    self.isSending = false
                }
                return
            }
            guard let chatRequest = self.makeChatActionRequest(
                prompt: prompt,
                context: context,
                module: module,
                kind: .diagnostics,
                origin: "提示词助手"
            ) else {
                await MainActor.run { self.isSending = false }
                return
            }
            self.messages.append(AIChatMessage(role: .assistant, text: "（正在生成...）", detail: nil))
            let placeholderID = self.messages.last?.id
            do {
                let pipeline = AIChatStreamingPipeline(actionCenter: actionCenter)
                let outcome = try await pipeline.run(request: chatRequest) { partial in
                    if let id = placeholderID,
                       let index = self.messages.firstIndex(where: { $0.id == id }) {
                        self.messages[index] = AIChatMessage(id: id, role: .assistant, text: partial)
                    }
                }
                if let result = outcome.result {
                    self.handleAIResponse(result: result, context: context, targetMessageID: placeholderID)
                    let finalText = (result.text ?? outcome.collectedText).trimmingCharacters(in: .whitespacesAndNewlines)
                    if finalText.isEmpty == false {
                        await self.applyPromptHelperResult(finalText, request: request)
                    }
                } else if let id = placeholderID,
                          let index = self.messages.firstIndex(where: { $0.id == id }) {
                    self.messages[index] = AIChatMessage(id: id, role: .assistant, text: outcome.collectedText)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "生成失败：\(error.localizedDescription)"
                }
            }
            await MainActor.run { self.isSending = false }
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
        var images: [NSImage] = []
        if let image = result.image {
            images.append(image)
        } else if let base64 = result.imageBase64,
                  let data = Data(base64Encoded: base64),
                  let img = NSImage(data: data) {
            images.append(img)
        }

        var cleanedText = result.text ?? "(无文本输出)"
        if images.isEmpty {
            if let inline = extractInlineImage(from: cleanedText) {
                images.append(inline.image)
                cleanedText = inline.cleanedText
            }
        }
        if let targetMessageID,
           let index = messages.firstIndex(where: { $0.id == targetMessageID }) {
            messages[index] = AIChatMessage(
                id: targetMessageID,
                role: .assistant,
                text: cleanedText,
                detail: detail,
                images: images
            )
        } else {
            messages.append(
                AIChatMessage(
                    role: .assistant,
                    text: cleanedText,
                    detail: detail,
                    images: images
                )
            )
        }
        if let summaryID = pendingSummaryMessageID,
           let index = messages.firstIndex(where: { $0.id == summaryID }) {
            messages.remove(at: index)
        }
    }

    private func extractInlineImage(from text: String) -> (image: NSImage, cleanedText: String)? {
        guard let range = text.range(of: "data:image") else { return nil }
        let substring = String(text[range.lowerBound...])
        guard let comma = substring.firstIndex(of: ",") else { return nil }
        let base64Part = String(substring[substring.index(after: comma)...])
        guard let data = Data(base64Encoded: base64Part),
              let img = NSImage(data: data) else { return nil }
        let cleaned = text.replacingOccurrences(of: substring, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (img, cleaned.isEmpty ? "(见图片)" : cleaned)
    }

    private func persistProjectSummary(_ summary: String, project: ScriptProject) async {
        await MainActor.run {
            scriptStore?.updateProject(id: project.id) { editable in
                if editable.synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    editable.synopsis = summary
                }
            }
            navigationStore?.pendingAIChatSystemMessage = "项目《\(project.title)》简介已更新。"
        }
    }

    private func applyProjectPayload(_ payload: ProjectSummaryPayload, project: ScriptProject) async {
        await MainActor.run {
            scriptStore?.updateProject(id: project.id) { editable in
                let cleanedOverview = payload.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                editable.synopsis = cleanedOverview.isEmpty ? editable.synopsis : cleanedOverview

                if let tags = payload.tags {
                    let cleaned = tags
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { $0.isEmpty == false }
                    editable.tags = Array(Set(cleaned))
                }

                if let characters = payload.characters {
                    let mapped = characters.compactMap { item -> ProjectCharacterProfile? in
                        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard name.isEmpty == false else { return nil }
                        let role = item.role?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let profile = item.profile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let description = [role, profile].filter { $0.isEmpty == false }.joined(separator: "｜")
                        return ProjectCharacterProfile(name: name, description: description)
                    }
                    editable.mainCharacters = mapped
                }

                if let scenes = payload.scenes {
                    let mapped = scenes.compactMap { item -> ProjectSceneProfile? in
                        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard name.isEmpty == false else { return nil }
                        var descriptionParts: [String] = []
                        if let desc = item.description?.trimmingCharacters(in: .whitespacesAndNewlines), desc.isEmpty == false {
                            descriptionParts.append(desc)
                        }
                        if let episodes = item.episodes, episodes.isEmpty == false {
                            let epText = episodes.map(String.init).joined(separator: ", ")
                            descriptionParts.append("出现集数：\(epText)")
                        }
                        let description = descriptionParts.isEmpty ? "AI 生成" : descriptionParts.joined(separator: "｜")
                        return ProjectSceneProfile(name: name, description: description)
                    }
                    editable.keyScenes = mapped
                }
            }

            guard let project = scriptStore?.projects.first(where: { $0.id == project.id }) else { return }
            let overviewApplied = project.synopsis.isEmpty == false
            navigationStore?.pendingAIChatSystemMessage = "项目《\(project.title)》AI 元信息已写入：简介\(overviewApplied ? "√" : "未写入")，标签\(project.tags.count)个，人物\(project.mainCharacters.count)个，场景\(project.keyScenes.count)个。"
        }
    }

    private func parseProjectPayload(from text: String) -> ProjectSummaryPayload? {
        guard let jsonText = extractJSON(from: text),
              let data = jsonText.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(ProjectSummaryPayload.self, from: data)
    }

    private func promptHelperPrompt(for request: PromptHelperRequest, project: ScriptProject) -> String {
        switch request.target {
        case .character:
            guard let character = project.mainCharacters.first(where: { $0.id == request.targetID }) else { return "" }
            let name = character.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = character.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = character.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            var lines: [String] = [
                "根据以下角色信息生成一条中文文生图提示词，便于在专业生图平台直接使用。",
                "仅输出提示词正文，不要附加解释、列表或代码块。",
                "",
                "角色：\(name.isEmpty ? "未命名角色" : name)"
            ]
            if description.isEmpty == false {
                lines.append("设定：\(description)")
            }
            if existing.isEmpty == false {
                lines.append("已有提示词（可在此基础上优化）：\(existing)")
            }
            lines.append("请突出外观、服饰、材质、气质、姿态、光线与镜头感，保持戏剧张力。")
            return lines.joined(separator: "\n")
        case .scene:
            guard let scene = project.keyScenes.first(where: { $0.id == request.targetID }) else { return "" }
            let name = scene.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = scene.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = scene.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            var lines: [String] = [
                "根据下述场景信息生成一条中文文生图提示词，便于在专业生图平台直接使用。",
                "仅输出提示词正文，不要附加解释、列表或代码块。",
                "",
                "场景：\(name.isEmpty ? "未命名场景" : name)"
            ]
            if description.isEmpty == false {
                lines.append("设定：\(description)")
            }
            if existing.isEmpty == false {
                lines.append("已有提示词（可在此基础上优化）：\(existing)")
            }
            lines.append("请描述空间/景别/光线/时间/色调/氛围与关键道具，保持戏剧张力。")
            return lines.joined(separator: "\n")
        }
    }

    private func applyPromptHelperResult(_ text: String, request: PromptHelperRequest) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        await MainActor.run {
            scriptStore?.updateProject(id: request.projectID) { editable in
                switch request.target {
                case .character:
                    if let idx = editable.mainCharacters.firstIndex(where: { $0.id == request.targetID }) {
                        if editable.mainCharacters[idx].variants.isEmpty {
                            editable.mainCharacters[idx].variants = [CharacterVariant(label: "默认形态", promptOverride: trimmed, images: [])]
                        } else {
                            editable.mainCharacters[idx].variants[0].promptOverride = trimmed
                        }
                        editable.mainCharacters[idx].prompt = trimmed
                    }
                case .scene:
                    if let idx = editable.keyScenes.firstIndex(where: { $0.id == request.targetID }) {
                            if editable.keyScenes[idx].variants.isEmpty {
                                editable.keyScenes[idx].variants = [SceneVariant(label: "默认视角", promptOverride: trimmed, images: [])]
                            } else {
                                editable.keyScenes[idx].variants[0].promptOverride = trimmed
                            }
                            editable.keyScenes[idx].prompt = trimmed
                    }
                }
            }

            if let project = scriptStore?.projects.first(where: { $0.id == request.projectID }) {
                let label = targetName(for: request, in: project)
                navigationStore?.pendingAIChatSystemMessage = "提示词已写入：\(label)"
            }
        }
    }

    private func targetName(for request: PromptHelperRequest, in project: ScriptProject) -> String {
        switch request.target {
        case .character:
            if let character = project.mainCharacters.first(where: { $0.id == request.targetID }) {
                let name = character.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? "角色" : "角色「\(name)」"
            }
            return "角色"
        case .scene:
            if let scene = project.keyScenes.first(where: { $0.id == request.targetID }) {
                let name = scene.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? "场景" : "场景「\(name)」"
            }
            return "场景"
        }
    }

    private func extractJSON(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        return String(text[start...end])
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
                let plain = attachment.base64String
                let uri = dataURI(for: attachment)
                fields["\(key)FileName"] = attachment.fileName
                fields["\(key)Base64"] = plain
                fields["\(key)DataURI"] = uri
            }
            // 为兼容多模态模型，附加首图的通用字段
            if let first = attachments.first {
                let plain = first.base64String
                let uri = dataURI(for: first)
                fields["imageBase64"] = plain
                fields["image_base64"] = plain
                fields["image_url"] = uri
                fields["image_mime"] = mimeType(for: first.fileName)
            }
            // 通用 JSON 载荷，兼容常见多模态接口（OpenAI/Google/Baidu 等）
            let attachmentPayload = attachments.map { attachment in
                [
                    "fileName": attachment.fileName,
                    "mime": mimeType(for: attachment.fileName),
                    "base64": attachment.base64String,
                    "dataURI": dataURI(for: attachment)
                ]
            }
            if let json = try? JSONSerialization.data(withJSONObject: attachmentPayload, options: []),
               let jsonString = String(data: json, encoding: .utf8) {
                fields["images_json"] = jsonString
            }
            // OpenAI 样式 content 字段（messages[0]）
            if let first = attachments.first {
                let openAIContent: [[String: Any]] = [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": dataURI(for: first)]]
                ]
                if let data = try? JSONSerialization.data(withJSONObject: openAIContent, options: []),
                   let text = String(data: data, encoding: .utf8) {
                    fields["openai_content"] = text
                }
            }
        }
        return fields
    }

    private func dataURI(for attachment: ImageAttachment) -> String {
        let mime = mimeType(for: attachment.fileName)
        return "data:\(mime);base64,\(attachment.base64String)"
    }

    private func mimeType(for filename: String) -> String {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "tiff", "tif": return "image/tiff"
        case "bmp": return "image/bmp"
        case "heic": return "image/heic"
        default: return "application/octet-stream"
        }
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
        if currentModule == .promptHelper {
            return "提示词助手"
        }
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
