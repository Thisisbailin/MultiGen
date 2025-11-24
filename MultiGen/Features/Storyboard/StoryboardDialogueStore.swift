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
    @Published private(set) var projects: [ScriptProject] = []
    @Published private(set) var episodes: [ScriptEpisode] = []
    @Published private(set) var selectedEpisode: ScriptEpisode?
    @Published var selectedProjectID: UUID?
    @Published private(set) var workspace: StoryboardWorkspace?
    @Published private(set) var entries: [StoryboardEntry] = []
    @Published private(set) var turns: [StoryboardDialogueTurn] = []
    @Published private(set) var scenes: [StoryboardSceneViewModel] = []
    @Published var selectedSceneID: UUID?
    @Published var focusedEntryID: UUID?
    @Published var selectedEntryID: UUID?
    @Published var errorMessage: String?
    @Published private(set) var infoBanner: String?
    @Published private(set) var parserWarning: String?
    @Published private(set) var lastSavedAt: Date?

    private let scriptStore: ScriptStore
    private let storyboardStore: StoryboardStore
    private let parser = StoryboardResponseParser()
    private var cancellables: Set<AnyCancellable> = []
    private var episodeSelectionNonce: UInt = 0

    init(
        scriptStore: ScriptStore,
        storyboardStore: StoryboardStore,
        defaultProjectID: UUID? = nil,
        defaultEpisodeID: UUID? = nil
    ) {
        self.scriptStore = scriptStore
        self.storyboardStore = storyboardStore

        projects = scriptStore.projects
        if let defaultProjectID,
           projects.contains(where: { $0.id == defaultProjectID }) {
            selectedProjectID = defaultProjectID
        } else {
            selectedProjectID = projects.first?.id
        }
        if let projectID = selectedProjectID,
           let project = projects.first(where: { $0.id == projectID }) {
            episodes = project.orderedEpisodes
        } else {
            episodes = projects.first?.orderedEpisodes ?? []
        }
        observeStores()
        if let defaultEpisodeID,
           episodes.contains(where: { $0.id == defaultEpisodeID }) {
            applyEpisodeSelection(id: defaultEpisodeID)
        } else if let firstEpisode = episodes.first {
            applyEpisodeSelection(id: firstEpisode.id)
        } else {
            applyEpisodeSelection(id: nil)
        }
    }

    var selectedEpisodeID: UUID? {
        selectedEpisode?.id
    }

    var selectedProject: ScriptProject? {
        guard let id = selectedProjectID else { return nil }
        return projects.first(where: { $0.id == id })
    }

    var focusedEntry: StoryboardEntry? {
        if let id = selectedEntryID ?? focusedEntryID {
            return entries.first(where: { $0.id == id })
        }
        return nil
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

    var selectedProjectDisplay: String {
        selectedProject?.title ?? "请选择项目"
    }

    var selectedSceneDisplay: String {
        currentScene?.displayTitle ?? "未选择场景"
    }

    var selectedShotDisplay: String {
        guard let entry = selectedEntry else { return "未选择镜头" }
        return "镜 \(entry.fields.shotNumber)"
    }

    func applyShotPrompts(sceneID: UUID?, prompts: [Int: String]) {
        let targetSceneID = sceneID
        let targetEntries = entries.filter { entry in
            if let targetSceneID {
                return entry.sceneID == targetSceneID
            }
            return true
        }
        for entry in targetEntries {
            if let prompt = prompts[entry.fields.shotNumber] {
                updateEntry(entry.id, userSummary: "写入提示词") { mutable in
                    mutable.fields.aiPrompt = prompt
                }
            }
        }
        infoBanner = "已写入 \(prompts.count) 个镜头提示词"
    }

    func selectProject(id: UUID?) {
        if selectedProjectID == id, let id { 
            if let project = projects.first(where: { $0.id == id }) {
                episodes = project.orderedEpisodes
            }
            return
        }
        selectedProjectID = id
        guard let id, let project = projects.first(where: { $0.id == id }) else {
            episodes = []
            selectEpisode(id: nil)
            return
        }
        episodes = project.orderedEpisodes
        if let current = selectedEpisode,
           project.episodes.contains(where: { $0.id == current.id }) == false {
            selectEpisode(id: project.orderedEpisodes.first?.id)
        }
    }

    func selectEpisode(id: UUID?) {
        episodeSelectionNonce &+= 1
        let nonce = episodeSelectionNonce
        Task { @MainActor [weak self] in
            guard let self, nonce == self.episodeSelectionNonce else { return }
            self.applyEpisodeSelection(id: id)
        }
    }

    private func applyEpisodeSelection(id: UUID?) {
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

        guard
            let project = projects.first(where: { $0.episodes.contains(where: { $0.id == id }) }),
            let episode = project.episodes.first(where: { $0.id == id })
        else { return }
        if selectedProjectID != project.id {
            selectedProjectID = project.id
            episodes = project.orderedEpisodes
        }
        if selectedEpisode?.id == id {
            return
        }
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

    func selectScene(id: UUID?) {
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

    func createManualEntry() {
        guard let episode = selectedEpisode else {
            errorMessage = "请选择剧集后再新增分镜。"
            return
        }
        guard let sceneDetails = targetSceneDetails() else {
            errorMessage = "请先在剧本模块创建至少一个场景。"
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
        entry.sceneTitle = sceneDetails.title
        entry.sceneSummary = sceneDetails.summary
        entry.sceneID = sceneDetails.id
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
        scriptStore.$projects
            .receive(on: RunLoop.main)
            .sink { [weak self] projects in
                self?.handleProjectListUpdate(projects)
            }
            .store(in: &cancellables)

        storyboardStore.$workspaces
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshWorkspaceSnapshot()
            }
            .store(in: &cancellables)
    }

    private func handleProjectListUpdate(_ projects: [ScriptProject]) {
        self.projects = projects
        guard projects.isEmpty == false else {
            selectedProjectID = nil
            episodes = []
            selectEpisode(id: nil)
            return
        }
        if let projectID = selectedProjectID,
           let project = projects.first(where: { $0.id == projectID }) {
            episodes = project.orderedEpisodes
            if let selected = selectedEpisode,
               let updated = project.episodes.first(where: { $0.id == selected.id }) {
                selectedEpisode = updated
                rebuildScenes()
            } else {
                selectEpisode(id: project.orderedEpisodes.first?.id)
            }
        } else {
            selectedProjectID = projects.first?.id
            episodes = projects.first?.orderedEpisodes ?? []
            selectEpisode(id: episodes.first?.id)
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

    @discardableResult
    private func mergeEntries(
        assistantText: String,
        episode: ScriptEpisode,
        sourceTurnID: UUID
    ) -> [UUID] {
        let parsed = parser.parseEntries(from: assistantText, nextShotNumber: 1)
        guard parsed.isEmpty == false else { return [] }

        var updatedEntries = entries
        var touchedIDs: [UUID] = []
        var nextShotCache: [UUID: Int] = [:]

        for parsedEntry in parsed {
            guard let sceneDetails = sceneDetails(for: parsedEntry, episode: episode) ?? targetSceneDetails() else {
                parserWarning = "未找到可用场景。请在剧本模块新增场景后再试。"
                continue
            }

            var fields = parsedEntry.fields
            if fields.shotNumber <= 0 {
                fields.shotNumber = nextShotNumber(for: sceneDetails.id, cache: &nextShotCache)
            }
            fields.aiPrompt = ""

            if let index = updatedEntries.firstIndex(where: { $0.sceneID == sceneDetails.id && $0.fields.shotNumber == fields.shotNumber }) {
                var entry = updatedEntries[index]
                entry.version += 1
                entry.fields = fields
                entry.status = .pendingReview
                entry.lastTurnID = sourceTurnID
                entry.updatedAt = .now
                entry.sceneID = sceneDetails.id
                entry.sceneTitle = sceneDetails.title
                entry.sceneSummary = sceneDetails.summary
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
                    sceneTitle: sceneDetails.title,
                    sceneSummary: sceneDetails.summary
                )
                entry.sceneID = sceneDetails.id
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

    private func sceneDetails(for parsed: StoryboardResponseParser.ParsedStoryboardEntry, episode: ScriptEpisode) -> (id: UUID, title: String, summary: String)? {
        if let id = parsed.sceneID,
           let scene = episode.scenes.first(where: { $0.id == id }) {
            return (scene.id, scene.title, scene.summary)
        }
        if let title = parsed.sceneTitle,
           let scene = episode.scenes.first(where: { normalizedSceneTitle($0.title) == normalizedSceneTitle(title) }) {
            return (scene.id, scene.title, scene.summary)
        }
        return nil
    }

    private func nextShotNumber(for sceneID: UUID, cache: inout [UUID: Int]) -> Int {
        if let cached = cache[sceneID] {
            cache[sceneID] = cached + 1
            return cached
        }
        let existingMax = entries
            .filter { $0.sceneID == sceneID }
            .map { $0.fields.shotNumber }
            .max() ?? 0
        let next = existingMax + 1
        cache[sceneID] = next + 1
        return next
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
        guard let episode = selectedEpisode else {
            scenes = []
            return
        }
        let scriptScenes = episode.scenes.sorted { $0.order < $1.order }
        var mutatedEntries = entries
        var didMutate = false
        let fallbackScene = scriptScenes.first
        for idx in mutatedEntries.indices {
            if
                let sceneID = mutatedEntries[idx].sceneID,
                let scriptScene = scriptScenes.first(where: { $0.id == sceneID })
            {
                if mutatedEntries[idx].sceneTitle != scriptScene.title {
                    mutatedEntries[idx].sceneTitle = scriptScene.title
                    didMutate = true
                }
                if mutatedEntries[idx].sceneSummary != scriptScene.summary {
                    mutatedEntries[idx].sceneSummary = scriptScene.summary
                    didMutate = true
                }
            } else if let scriptMatch = scriptScenes.first(where: {
                normalizedSceneTitle($0.title) == normalizedSceneTitle(mutatedEntries[idx].sceneTitle)
            }) {
                mutatedEntries[idx].sceneID = scriptMatch.id
                mutatedEntries[idx].sceneTitle = scriptMatch.title
                mutatedEntries[idx].sceneSummary = scriptMatch.summary
                didMutate = true
            } else if let fallback = fallbackScene {
                mutatedEntries[idx].sceneID = fallback.id
                mutatedEntries[idx].sceneTitle = fallback.title
                mutatedEntries[idx].sceneSummary = fallback.summary
                didMutate = true
            }
        }
        if didMutate {
            entries = mutatedEntries
            persistEntries()
            return
        }
        scenes = scriptScenes.map { scriptScene in
            let filtered = entries.filter { $0.sceneID == scriptScene.id }
            return StoryboardSceneViewModel(
                id: scriptScene.id,
                title: scriptScene.title,
                summary: scriptScene.summary,
                body: scriptScene.body,
                order: scriptScene.order,
                locationHint: scriptScene.locationHint,
                timeHint: scriptScene.timeHint,
                entries: filtered
            )
        }
        if let currentSceneID = selectedSceneID,
           scenes.contains(where: { $0.id == currentSceneID }) == false {
            selectedSceneID = scenes.first?.id
        }
        if let entryID = selectedEntryID,
           scenes.contains(where: { $0.entries.contains(where: { $0.id == entryID }) }) == false {
            selectedEntryID = scenes.first?.entries.first?.id
            focusedEntryID = selectedEntryID
        }
        if selectedEntryID == nil {
            selectedEntryID = scenes.first?.entries.first?.id
            focusedEntryID = selectedEntryID
        }
    }

    private func normalizedSceneTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func currentSceneDetails() -> (id: UUID, title: String, summary: String)? {
        guard let scene = currentScene else { return nil }
        return (scene.id, scene.title, scene.summary)
    }

    private func fallbackSceneDetails() -> (id: UUID, title: String, summary: String)? {
        guard
            let episode = selectedEpisode,
            let first = episode.scenes.sorted(by: { $0.order < $1.order }).first
        else { return nil }
        return (first.id, first.title, first.summary)
    }

    private func targetSceneDetails() -> (id: UUID, title: String, summary: String)? {
        currentSceneDetails() ?? fallbackSceneDetails()
    }

}

extension StoryboardDialogueStore: StoryboardAutomationHandling {
    func recordSidebarInstruction(_ text: String) {
        guard let episode = selectedEpisode else { return }
        let userTurn = StoryboardDialogueTurn(
            episodeID: episode.id,
            role: .user,
            message: text,
            referencedEntryIDs: focusedEntryID.map { [$0] } ?? []
        )
        turns.append(userTurn)
        storyboardStore.appendDialogueTurn(userTurn)
        infoBanner = nil
        parserWarning = nil
    }

    func applySidebarAIResponse(_ response: String) -> StoryboardAICommandResult? {
        guard let episode = selectedEpisode else { return nil }
        let assistantTurnID = UUID()
        let touchedEntryIDs = mergeEntries(
            assistantText: response,
            episode: episode,
            sourceTurnID: assistantTurnID
        )
        let assistantTurn = StoryboardDialogueTurn(
            id: assistantTurnID,
            episodeID: episode.id,
            role: .assistant,
            message: response,
            referencedEntryIDs: touchedEntryIDs
        )
        turns.append(assistantTurn)
        storyboardStore.appendDialogueTurn(assistantTurn)

        if touchedEntryIDs.isEmpty {
            parserWarning = "AI 回复已保存，但未解析出有效的分镜结构，请检查提示词或重新生成。"
        } else {
            parserWarning = nil
        }

        return StoryboardAICommandResult(
            touchedEntries: touchedEntryIDs.count,
            warning: parserWarning
        )
    }
}

struct StoryboardAICommandResult {
    let touchedEntries: Int
    let warning: String?
}

@MainActor
protocol StoryboardAutomationHandling: AnyObject {
    func recordSidebarInstruction(_ text: String)
    func applySidebarAIResponse(_ response: String) -> StoryboardAICommandResult?
}

struct StoryboardSceneViewModel: Identifiable {
    let id: UUID
    let title: String
    let summary: String
    let body: String
    let order: Int
    let locationHint: String
    let timeHint: String
    let entries: [StoryboardEntry]

    var countDescription: String {
        "\(entries.count) 个分镜"
    }

    var displayTitle: String {
        let extras = [locationHint, timeHint].filter { $0.isEmpty == false }
        guard extras.isEmpty == false else { return title }
        return ([title] + extras).joined(separator: " · ")
    }
}
