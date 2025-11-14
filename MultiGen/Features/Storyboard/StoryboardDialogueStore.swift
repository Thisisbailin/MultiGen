//
//  StoryboardDialogueStore.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class StoryboardDialogueStore: ObservableObject {
    @Published private(set) var episodes: [ScriptEpisode] = []
    @Published private(set) var selectedEpisode: ScriptEpisode?
    @Published private(set) var workspace: StoryboardWorkspace?
    @Published private(set) var entries: [StoryboardEntry] = []
    @Published private(set) var turns: [StoryboardDialogueTurn] = []
    @Published private(set) var scenes: [StoryboardSceneViewModel] = []
    @Published var selectedSceneID: String?
    @Published var messageText: String = ""
    @Published var focusedEntryID: UUID?
    @Published var selectedEntryID: UUID?
    @Published private(set) var isGenerating: Bool = false
    @Published var errorMessage: String?
    @Published private(set) var infoBanner: String?
    @Published private(set) var parserWarning: String?
    @Published private(set) var lastSavedAt: Date?
    @Published var includePromptHint: Bool = true
    @Published var includeScriptContext: Bool = true
    @Published var includeStoryboardContext: Bool = true

    private let scriptStore: ScriptStore
    private let storyboardStore: StoryboardStore
    private let promptLibraryStore: PromptLibraryStore
    private let dependencies: AppDependencies
    private let parser = StoryboardResponseParser()
    private var cancellables: Set<AnyCancellable> = []

    init(
        scriptStore: ScriptStore,
        storyboardStore: StoryboardStore,
        promptLibraryStore: PromptLibraryStore,
        dependencies: AppDependencies
    ) {
        self.scriptStore = scriptStore
        self.storyboardStore = storyboardStore
        self.promptLibraryStore = promptLibraryStore
        self.dependencies = dependencies

        episodes = scriptStore.episodes
        observeStores()
        refreshWorkspaceSnapshot()
    }

    var selectedEpisodeID: UUID? {
        selectedEpisode?.id
    }

    var focusedEntry: StoryboardEntry? {
        if let id = selectedEntryID ?? focusedEntryID {
            return entries.first(where: { $0.id == id })
        }
        return nil
    }

    var canSend: Bool {
        guard selectedEpisode != nil else { return false }
        return messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && isGenerating == false
    }

    var bannerMessage: String? {
        if let warning = parserWarning { return warning }
        if let infoBanner { return infoBanner }
        return nil
    }

    var currentScene: StoryboardSceneViewModel? {
        guard let id = selectedSceneID else { return scenes.first }
        return scenes.first(where: { $0.id == id }) ?? scenes.first
    }

    var entriesForSelectedScene: [StoryboardEntry] {
        currentScene?.entries ?? []
    }

    var selectedEntry: StoryboardEntry? {
        guard let id = selectedEntryID else { return nil }
        return entries.first(where: { $0.id == id })
    }

    var selectedEpisodeDisplay: String {
        selectedEpisode?.displayLabel ?? "请选择剧集"
    }

    var selectedSceneDisplay: String {
        currentScene?.title ?? "未选择场景"
    }

    var selectedShotDisplay: String {
        guard let entry = selectedEntry else { return "未选择镜头" }
        return "镜 \(entry.fields.shotNumber)"
    }

    var currentModelDisplayName: String {
        dependencies.configuration.textModel.displayName
    }

    var currentRouteDescription: String {
        let configuration = dependencies.configuration
        if configuration.useMock {
            return "Mock · 本地模拟"
        }
        if configuration.relayEnabled {
            let provider = configuration.relayProviderName.isEmpty ? "中转" : configuration.relayProviderName
            let model = configuration.relaySelectedModel ?? "未选模型"
            return "\(provider) · \(model)"
        }
        return "Gemini · 官方线路"
    }

    private var storyboardSystemPrompt: String {
        promptLibraryStore.document(for: .storyboard).content
    }

    func selectEpisode(id: UUID?) {
        guard let id else {
            selectedEpisode = nil
            workspace = nil
            entries = []
            turns = []
            focusedEntryID = nil
            selectedEntryID = nil
            selectedSceneID = nil
            scenes = []
            return
        }

        guard let episode = scriptStore.episodes.first(where: { $0.id == id }) else { return }
        selectedEpisode = episode
        workspace = storyboardStore.ensureWorkspace(for: episode)
        entries = workspace?.orderedEntries ?? []
        turns = workspace?.dialogueTurns.sorted(by: { $0.createdAt < $1.createdAt }) ?? []
        rebuildScenes()
        if let firstScene = scenes.first {
            selectedSceneID = firstScene.id
            selectedEntryID = firstScene.entries.first?.id
            focusedEntryID = selectedEntryID
        } else {
            selectedSceneID = nil
            selectedEntryID = nil
            focusedEntryID = nil
        }
    }

    func selectScene(id: String?) {
        let target = id ?? scenes.first?.id
        selectedSceneID = target
        if let target,
           let scene = scenes.first(where: { $0.id == target }),
           let firstEntry = scene.entries.first {
            selectedEntryID = firstEntry.id
            focusedEntryID = firstEntry.id
        } else {
            selectedEntryID = nil
            focusedEntryID = nil
        }
    }

    func selectEntry(id: UUID?) {
        selectedEntryID = id
        focusedEntryID = id
        if let id,
           let scene = scenes.first(where: { $0.entries.contains(where: { $0.id == id }) }) {
            selectedSceneID = scene.id
        }
    }

    func focus(entryID: UUID?) {
        selectEntry(id: entryID)
    }

    func sendMessage() {
        guard isGenerating == false else { return }

        guard let episode = selectedEpisode else {
            errorMessage = "请先选择需要处理的剧集。"
            return
        }
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        let userTurn = StoryboardDialogueTurn(
            episodeID: episode.id,
            role: .user,
            message: trimmed,
            referencedEntryIDs: focusedEntryID.map { [$0] } ?? []
        )

        turns.append(userTurn)
        storyboardStore.appendDialogueTurn(userTurn)
        messageText = ""
        infoBanner = nil
        parserWarning = nil

        Task { await generateAssistantResponse(for: episode, userMessage: trimmed) }
    }

    func createManualEntry() {
        guard let episode = selectedEpisode else {
            errorMessage = "请选择剧集后再新增分镜。"
            return
        }
        let nextShot = (entries.map(\.fields.shotNumber).max() ?? 0) + 1
        var entry = StoryboardEntry(
            episodeID: episode.id,
            fields: StoryboardEntryFields(shotNumber: nextShot),
            status: .draft,
            version: 1,
            notes: ""
        )
        entry.createdAt = .now
        entry.updatedAt = .now
        entry.sceneTitle = currentScene?.title ?? "未命名场景"
        entry.sceneSummary = currentScene?.summary ?? ""
        entries.append(entry)
        entries.sort { $0.fields.shotNumber < $1.fields.shotNumber }
        selectedEntryID = entry.id
        focusedEntryID = entry.id
        persistEntries()
    }

    func publishInfoBanner(_ message: String) {
        infoBanner = message
    }

    func updateSceneInfo(entryID: UUID, title: String, summary: String) {
        updateEntry(entryID, userSummary: "更新场景信息") { entry in
            entry.sceneTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名场景" : title
            entry.sceneSummary = summary
        }
        rebuildScenes()
        selectEntry(id: entryID)
    }

    func bindingForField(_ keyPath: WritableKeyPath<StoryboardEntryFields, String>, entryID: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.entries.first(where: { $0.id == entryID })?.fields[keyPath: keyPath] ?? ""
            },
            set: { [weak self] newValue in
                self?.updateEntry(entryID, userSummary: "编辑字段") { entry in
                    entry.fields[keyPath: keyPath] = newValue
                }
            }
        )
    }

    func bindingForShotNumber(entryID: UUID) -> Binding<Int> {
        Binding(
            get: { [weak self] in
                self?.entries.first(where: { $0.id == entryID })?.fields.shotNumber ?? 1
            },
            set: { [weak self] newValue in
                self?.updateEntry(entryID, userSummary: "调整镜号") { entry in
                    entry.fields.shotNumber = max(newValue, 1)
                }
                self?.sortEntriesByShot()
                self?.persistEntries()
            }
        )
    }

    func deleteEntry(_ entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries.remove(at: index)
        if focusedEntryID == entryID {
            focusedEntryID = entries.first?.id
        }
        persistEntries()
    }

    func markEntry(_ entryID: UUID, status: StoryboardEntryStatus) {
        updateEntry(entryID, userSummary: "状态更新为 \(status.displayName)") { entry in
            entry.status = status
        }
    }

    private func observeStores() {
        scriptStore.$episodes
            .receive(on: RunLoop.main)
            .sink { [weak self] episodes in
                self?.episodes = episodes
                self?.handleEpisodeListUpdate()
            }
            .store(in: &cancellables)

        storyboardStore.$workspaces
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshWorkspaceSnapshot()
            }
            .store(in: &cancellables)
    }

    private func handleEpisodeListUpdate() {
        guard let selected = selectedEpisode else { return }
        if episodes.contains(where: { $0.id == selected.id }) == false {
            selectEpisode(id: nil)
        }
    }

    private func refreshWorkspaceSnapshot() {
        guard let episode = selectedEpisode else { return }
        workspace = storyboardStore.workspace(for: episode.id)
        entries = workspace?.orderedEntries ?? []
        turns = workspace?.dialogueTurns.sorted(by: { $0.createdAt < $1.createdAt }) ?? []
        rebuildScenes()
        if selectedSceneID == nil {
            selectedSceneID = scenes.first?.id
        }
        if selectedEntryID == nil {
            selectedEntryID = scenes.first?.entries.first?.id
            focusedEntryID = selectedEntryID
        }

        if let entryID = selectedEntryID,
           let containingScene = scenes.first(where: { $0.entries.contains(where: { $0.id == entryID }) }) {
            selectedSceneID = containingScene.id
        }
    }

    private func generateAssistantResponse(for episode: ScriptEpisode, userMessage: String) async {
        isGenerating = true
        defer { isGenerating = false }

        let existingEntries = entries
        let synopsis = makeSynopsis(from: episode)
        let entriesSummary = includeStoryboardContext ? summarize(entries: existingEntries) : nil
        let focusSummary = focusedEntryID.flatMap { id in
            existingEntries.first(where: { $0.id == id }).map { entry in
                """
                镜\(entry.fields.shotNumber)：\(entry.fields.shotScale)，运镜 \(entry.fields.cameraMovement)，台词：\(entry.fields.dialogueOrOS)
                """
            }
        } ?? ""

        var fields: [String: String] = [
            "episodeNumber": "\(episode.episodeNumber)",
            "userInstruction": userMessage,
        ]

        if includeScriptContext {
            fields["episodeSynopsis"] = synopsis
        }
        if let entriesSummary {
            fields["existingEntries"] = entriesSummary
        }
        if includePromptHint {
            fields["responseFormat"] = StoryboardResponseParser.responseFormatHint
        }
        if focusSummary.isEmpty == false {
            fields["focusEntry"] = focusSummary
        }
        if let scene = currentScene {
            fields["sceneTitle"] = scene.title
            if scene.summary.isEmpty == false {
                fields["sceneSummary"] = scene.summary
            }
        }
        let prompt = storyboardSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty == false {
            fields["systemPrompt"] = prompt
        }

        let request = SceneJobRequest(
            action: .generateScene,
            fields: fields,
            channel: .text
        )

        do {
            let result = try await dependencies.textService().submit(job: request)
            let assistantText = result.metadata.prompt
            let assistantTurnID = UUID()
            let touchedEntryIDs = mergeEntries(
                assistantText: assistantText,
                episode: episode,
                sourceTurnID: assistantTurnID
            )

            let assistantTurn = StoryboardDialogueTurn(
                id: assistantTurnID,
                episodeID: episode.id,
                role: .assistant,
                message: assistantText,
                referencedEntryIDs: touchedEntryIDs
            )

            turns.append(assistantTurn)
            storyboardStore.appendDialogueTurn(assistantTurn)

            if touchedEntryIDs.isEmpty {
                parserWarning = "AI 回复已保存，但未解析出有效的分镜结构，请手动整理或调整指令。"
            } else {
                parserWarning = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func mergeEntries(
        assistantText: String,
        episode: ScriptEpisode,
        sourceTurnID: UUID
    ) -> [UUID] {
        let currentEntries = entries
        let nextShot = (currentEntries.map(\.fields.shotNumber).max() ?? 0) + 1
        let parsed = parser.parseEntries(from: assistantText, nextShotNumber: nextShot)

        guard parsed.isEmpty == false else { return [] }

        var updatedEntries = currentEntries
        var touchedIDs: [UUID] = []

        for fields in parsed {
            if let index = updatedEntries.firstIndex(where: { $0.fields.shotNumber == fields.shotNumber }) {
                var entry = updatedEntries[index]
                entry.version += 1
                entry.fields = fields
                entry.status = .pendingReview
                entry.lastTurnID = sourceTurnID
                entry.updatedAt = .now
                let revision = StoryboardRevision(
                    version: entry.version,
                    authorRole: .assistant,
                    summary: "AI 更新镜 \(fields.shotNumber)",
                    fields: fields,
                    sourceTurnID: sourceTurnID
                )
                entry.revisions.append(revision)
                updatedEntries[index] = entry
                touchedIDs.append(entry.id)
            } else {
                let sceneTitle = currentScene?.title ?? "未命名场景"
                var entry = StoryboardEntry(
                    episodeID: episode.id,
                    fields: fields,
                    status: .pendingReview,
                    version: 1,
                    notes: "",
                    revisions: [
                        StoryboardRevision(
                            version: 1,
                            authorRole: .assistant,
                            summary: "AI 初稿镜 \(fields.shotNumber)",
                            fields: fields,
                            sourceTurnID: sourceTurnID
                        )
                    ],
                    lastTurnID: sourceTurnID,
                    sceneTitle: sceneTitle,
                    sceneSummary: currentScene?.summary ?? ""
                )
                entry.createdAt = .now
                entry.updatedAt = .now
                updatedEntries.append(entry)
                touchedIDs.append(entry.id)
            }
        }

        updatedEntries.sort { $0.fields.shotNumber < $1.fields.shotNumber }
        entries = updatedEntries
        storyboardStore.saveEntries(updatedEntries, for: episode.id)
        refreshWorkspaceSnapshot()
        return touchedIDs
    }

    private func updateEntry(
        _ entryID: UUID,
        userSummary: String,
        transform: (inout StoryboardEntry) -> Void
    ) {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return }
        var target = entries[idx]
        transform(&target)
        target.version += 1
        target.updatedAt = .now
        let revision = StoryboardRevision(
            version: target.version,
            authorRole: .user,
            summary: userSummary,
            fields: target.fields,
            sourceTurnID: nil
        )
        target.revisions.append(revision)
        entries[idx] = target
        persistEntries()
    }

    private func persistEntries() {
        guard let episodeID = selectedEpisode?.id else { return }
        sortEntriesByShot()
        storyboardStore.saveEntries(entries, for: episodeID)
        lastSavedAt = .now
        rebuildScenes()
    }

    private func sortEntriesByShot() {
        entries.sort { lhs, rhs in
            if lhs.fields.shotNumber == rhs.fields.shotNumber {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.fields.shotNumber < rhs.fields.shotNumber
        }
    }

    private func rebuildScenes() {
        let previousScenes = scenes
        let previousSelectionID = selectedSceneID
        let previousSelectionTitle = previousScenes.first(where: { $0.id == previousSelectionID })?.title

        let grouped = Dictionary(grouping: entries) { entry -> String in
            let title = entry.sceneTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "未命名场景" : title
        }

        scenes = grouped.map { title, entries in
            let sortedEntries = entries.sorted {
                if $0.fields.shotNumber == $1.fields.shotNumber {
                    return $0.createdAt < $1.createdAt
                }
                return $0.fields.shotNumber < $1.fields.shotNumber
            }
            let summary = sortedEntries.first?.sceneSummary ?? ""
            return StoryboardSceneViewModel(
                title: title,
                summary: summary,
                entries: sortedEntries
            )
        }
        .sorted { $0.anchorShotNumber < $1.anchorShotNumber }

        if let previousSelectionID,
           scenes.contains(where: { $0.id == previousSelectionID }) {
            selectedSceneID = previousSelectionID
        } else if let previousSelectionTitle,
                  let replacement = scenes.first(where: { $0.title == previousSelectionTitle }) {
            selectedSceneID = replacement.id
        } else {
            selectedSceneID = scenes.first?.id
        }

        if let entryID = selectedEntryID,
           scenes.contains(where: { $0.entries.contains(where: { $0.id == entryID }) }) == false {
            // fallback to the first entry under selected scene
            selectedEntryID = currentScene?.entries.first?.id
            focusedEntryID = selectedEntryID
        }

        if selectedEntryID == nil {
            selectedEntryID = scenes.first?.entries.first?.id
            focusedEntryID = selectedEntryID
        }
    }

    private func makeSynopsis(from episode: ScriptEpisode) -> String {
        let trimmed = episode.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "尚未提供剧本正文。" }
        return String(trimmed.prefix(800))
    }

private func summarize(entries: [StoryboardEntry]) -> String {
        guard entries.isEmpty == false else { return "无分镜初稿。" }
        return entries
            .sorted { $0.fields.shotNumber < $1.fields.shotNumber }
            .map { entry in
                "镜\(entry.fields.shotNumber)：\(entry.fields.shotScale)，\(entry.fields.cameraMovement)，\(entry.fields.duration)，\(entry.fields.dialogueOrOS.prefix(40))…"
            }
            .joined(separator: "\n")
    }
}

struct StoryboardSceneViewModel: Identifiable {
    let id: String
    let title: String
    let summary: String
    let entries: [StoryboardEntry]

    init(title: String, summary: String, entries: [StoryboardEntry]) {
        self.title = title
        self.summary = summary
        self.entries = entries
        let anchorID = entries.first?.id.uuidString ?? UUID().uuidString
        self.id = "\(title)#\(anchorID)"
    }

    var countDescription: String {
        "\(entries.count) 个分镜"
    }

    var anchorShotNumber: Int {
        entries.first?.fields.shotNumber ?? Int.max
    }
}
