import Foundation
import SwiftUI
import Combine

@MainActor
final class BatchStoryboardFlowStore: ObservableObject {
    enum Phase {
        case context
        case storyboard
        case sora
        case completed
        case cancelled
    }

    struct EpisodeState {
        var storyboardText: String?
        var storyboardWarning: String?
        var soraText: String?
        var soraWarning: String?
        var confirmedStoryboard: Bool = false
        var confirmedSora: Bool = false
    }

    @Published var phase: Phase = .context
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published var storyboardGuide: String = ""
    @Published var promptGuide: String = ""
    @Published var projectSummary: String = ""
    @Published var characterSummary: String = ""
    @Published var episodeOverview: String = ""
    @Published var contextPreview: String = ""
    @Published var currentEpisodeIndex: Int = 0

    let project: ScriptProject
    let episodes: [ScriptEpisode]

    private let promptLibraryStore: PromptLibraryStore
    private let actionCenter: AIActionCenter
    private let storyboardStore: StoryboardStore
    private let writer = BatchStoryboardWriter()
    private let builder = BatchStoryboardPromptBuilder()
    @Published private(set) var episodeStates: [UUID: EpisodeState] = [:]

    init(
        project: ScriptProject,
        promptLibraryStore: PromptLibraryStore,
        actionCenter: AIActionCenter,
        storyboardStore: StoryboardStore
    ) {
        self.project = project
        self.episodes = project.orderedEpisodes
        self.promptLibraryStore = promptLibraryStore
        self.actionCenter = actionCenter
        self.storyboardStore = storyboardStore
        for ep in episodes {
            episodeStates[ep.id] = EpisodeState()
        }
    }

    var currentEpisode: ScriptEpisode? {
        guard currentEpisodeIndex >= 0, currentEpisodeIndex < episodes.count else { return nil }
        return episodes[currentEpisodeIndex]
    }

    func generateContext() async {
        guard isWorking == false else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        let systemPrompt = promptLibraryStore.document(for: .scriptProjectSummary).content
        let inputs = BatchStoryboardPromptBuilder.ContextInputs(
            project: project,
            storyboardGuide: storyboardGuide
        )
        let prompt = builder.contextPrompt(inputs)
        var fields = AIChatRequestBuilder.makeFields(
            prompt: prompt,
            context: .scriptProject(project: project),
            module: .scriptProjectSummary,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt
        )
        fields["responseFormat"] = "纯文本，无列表，无代码块"

        let request = AIActionRequest(
            kind: .projectSummary,
            action: .aiConsole,
            channel: .text,
            fields: fields,
            assetReferences: [],
            module: .scriptProjectSummary,
            context: .scriptProject(project: project),
            contextSummaryOverride: "批量分镜 · 上下文构造",
            origin: "批量分镜"
        )
        do {
            let result = try await actionCenter.perform(request)
            let text = result.text ?? ""
            let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            contextPreview = trimmed
            let parsed = parseContextSections(from: trimmed)
            projectSummary = parsed.projectSummary
            characterSummary = parsed.characterSummary
            episodeOverview = parsed.episodeOverview
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generateStoryboardForCurrentEpisode() async {
        guard let episode = currentEpisode else { return }
        guard isWorking == false else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let inputs = BatchStoryboardPromptBuilder.EpisodeStoryboardInputs(
            project: project,
            episode: episode,
            accumulatedEpisodeOverview: episodeOverview,
            storyboardGuide: storyboardGuide,
            projectSummary: projectSummary,
            characterSummary: characterSummary
        )
        let fields = builder.storyboardPrompt(inputs)

        let request = AIActionRequest(
            kind: .storyboardOperation,
            action: .generateScene,
            channel: .text,
            fields: fields,
            assetReferences: [],
            module: .storyboard,
            context: .storyboard(project: project, episode: episode, scene: nil, snapshot: nil, workspace: nil),
            contextSummaryOverride: "批量分镜 · \(episode.displayLabel)",
            origin: "批量分镜"
        )
        do {
            let result = try await actionCenter.perform(request)
            var state = episodeStates[episode.id] ?? EpisodeState()
            state.storyboardText = (result.text ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            state.storyboardWarning = nil
            episodeStates[episode.id] = state
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmStoryboardForCurrentEpisode() {
        guard let episode = currentEpisode else { return }
        guard let draft = episodeStates[episode.id]?.storyboardText else {
            errorMessage = "暂无分镜结果，请先生成。"
            return
        }
        let outcome = writer.applyStoryboardResponse(
            draft,
            project: project,
            episode: episode,
            storyboardStore: storyboardStore
        )
        var state = episodeStates[episode.id] ?? EpisodeState()
        state.confirmedStoryboard = outcome.touchedCount > 0
        state.storyboardWarning = outcome.warning
        episodeStates[episode.id] = state
        if let warning = outcome.warning {
            errorMessage = warning
            return
        }
    }

    private func goToNextEpisodeOrSora() {
        if currentEpisodeIndex + 1 < episodes.count {
            currentEpisodeIndex += 1
        } else {
            currentEpisodeIndex = 0
            phase = .sora
        }
    }

    func generateSoraForCurrentEpisode() async {
        guard let episode = currentEpisode else { return }
        guard isWorking == false else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        guard let storyboardText = episodeStates[episode.id]?.storyboardText else {
            errorMessage = "请先生成并确认分镜。"
            return
        }

        let inputs = BatchStoryboardPromptBuilder.EpisodeSoraInputs(
            project: project,
            episode: episode,
            storyboardScript: storyboardText,
            promptGuide: promptGuide,
            projectSummary: projectSummary,
            characterSummary: characterSummary
        )
        let fields = builder.soraPrompt(inputs)
        let request = AIActionRequest(
            kind: .storyboardOperation,
            action: .aiConsole,
            channel: .text,
            fields: fields,
            assetReferences: [],
            module: .promptHelperStoryboard,
            context: .storyboard(project: project, episode: episode, scene: nil, snapshot: nil, workspace: nil),
            contextSummaryOverride: "批量提示词 · \(episode.displayLabel)",
            origin: "批量分镜"
        )
        do {
            let result = try await actionCenter.perform(request)
            var state = episodeStates[episode.id] ?? EpisodeState()
            state.soraText = (result.text ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            state.soraWarning = nil
            episodeStates[episode.id] = state
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmSoraForCurrentEpisode() {
        guard let episode = currentEpisode else { return }
        guard let draft = episodeStates[episode.id]?.soraText else {
            errorMessage = "暂无提示词结果，请先生成。"
            return
        }
        let outcome = writer.applySoraPrompts(
            draft,
            episode: episode,
            storyboardStore: storyboardStore
        )
        var state = episodeStates[episode.id] ?? EpisodeState()
        state.confirmedSora = outcome.updatedCount > 0
        state.soraWarning = outcome.warning
        episodeStates[episode.id] = state
        if let warning = outcome.warning {
            errorMessage = warning
            return
        }
    }

    func goToNextStoryboardEpisode() {
        if currentEpisodeIndex + 1 < episodes.count {
            currentEpisodeIndex += 1
        } else {
            currentEpisodeIndex = 0
            phase = .sora
        }
    }

    func goToNextSoraEpisode() {
        if currentEpisodeIndex + 1 < episodes.count {
            currentEpisodeIndex += 1
        } else {
            phase = .completed
        }
    }

    func cancel() {
        phase = .cancelled
    }

    private func parseContextSections(from text: String) -> (projectSummary: String, characterSummary: String, episodeOverview: String) {
        let markers = ["【项目简介】", "【角色概述】", "【剧集概述】"]
        var result: [String: String] = [:]
        var current: String?
        var buffer: [String] = []
        func flush() {
            if let key = current {
                result[key] = buffer.joined(separator: "\n").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            }
            buffer = []
        }
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if markers.contains(where: { line.contains($0) }) {
                flush()
                current = markers.first(where: { line.contains($0) })
                continue
            }
            buffer.append(line)
        }
        flush()
        let project = result["【项目简介】"] ?? text
        let roles = result["【角色概述】"] ?? ""
        let episodes = result["【剧集概述】"] ?? ""
        return (project, roles, episodes)
    }
}
