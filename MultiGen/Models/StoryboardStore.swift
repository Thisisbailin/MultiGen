//
//  StoryboardStore.swift
//  MultiGen
//
//  Created by Joe on 2025/11/13.
//

import Foundation
import Combine

@MainActor
final class StoryboardStore: ObservableObject {
    @Published private(set) var workspaces: [StoryboardWorkspace]

    private let storageURL: URL

    init() {
        storageURL = StoryboardStore.makeStorageURL()
        workspaces = StoryboardStore.load(from: storageURL)
    }

    func workspace(for episodeID: UUID) -> StoryboardWorkspace? {
        workspaces.first { $0.episodeID == episodeID }
    }

    func ensureWorkspace(for episode: ScriptEpisode) -> StoryboardWorkspace {
        if let existing = workspace(for: episode.id) {
            return existing
        }
        let workspace = StoryboardWorkspace(
            id: episode.id,
            episodeID: episode.id,
            episodeNumber: episode.episodeNumber,
            episodeTitle: episode.displayLabel,
            episodeSynopsis: Self.makeSynopsis(from: episode.markdown)
        )
        workspaces.append(workspace)
        persist()
        return workspace
    }

    func updateWorkspace(for episodeID: UUID, update: (inout StoryboardWorkspace) -> Void) {
        guard let index = workspaces.firstIndex(where: { $0.episodeID == episodeID }) else { return }
        update(&workspaces[index])
        workspaces[index].updatedAt = .now
        persist()
    }

    func saveEntries(_ entries: [StoryboardEntry], for episodeID: UUID) {
        updateWorkspace(for: episodeID) { workspace in
            workspace.entries = entries
        }
    }

    func appendDialogueTurn(_ turn: StoryboardDialogueTurn) {
        if workspace(for: turn.episodeID) == nil {
            let placeholderEpisode = ScriptEpisode(
                id: turn.episodeID,
                episodeNumber: 0,
                markdown: ""
            )
            _ = ensureWorkspace(for: placeholderEpisode)
        }

        updateWorkspace(for: turn.episodeID) { workspace in
            workspace.dialogueTurns.append(turn)
        }
    }

    func replaceWorkspaces(_ newValue: [StoryboardWorkspace]) {
        workspaces = newValue
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(workspaces)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("StoryboardStore persist error: \(error)")
        }
    }

    private static func load(from url: URL) -> [StoryboardWorkspace] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([StoryboardWorkspace].self, from: data)) ?? []
    }

    private static func makeStorageURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("MultiGen", isDirectory: true)
            .appendingPathComponent("storyboard-workspaces.json")
    }

    private static func makeSynopsis(from markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "尚未提供剧本文本。" }
        let prefix = trimmed.prefix(240)
        return String(prefix)
    }

}
