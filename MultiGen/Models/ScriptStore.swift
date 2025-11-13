//
//  ScriptStore.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation
import Combine

struct ScriptScene: Identifiable, Codable, Hashable {
    let id: UUID
    var order: Int
    var title: String
    var summary: String
    var body: String

    init(
        id: UUID = UUID(),
        order: Int,
        title: String,
        summary: String = "",
        body: String = ""
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.summary = summary
        self.body = body
    }
}

struct ScriptEpisode: Identifiable, Codable, Hashable {
    let id: UUID
    var episodeNumber: Int
    var title: String
    var synopsis: String
    var markdown: String
    var scenes: [ScriptScene]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        episodeNumber: Int,
        title: String = "",
        synopsis: String = "",
        markdown: String,
        scenes: [ScriptScene] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.episodeNumber = episodeNumber
        self.title = title
        self.synopsis = synopsis
        self.markdown = markdown
        self.scenes = scenes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayLabel: String {
        if title.isEmpty == false { return title }
        return episodeNumber <= 1 ? "整片" : "第\(episodeNumber)集"
    }
}

struct ScriptProject: Identifiable, Codable, Hashable {
    enum ProjectType: String, Codable, CaseIterable, Identifiable {
        case standalone
        case episodic

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .standalone: return "单片/短篇"
            case .episodic: return "多集项目"
            }
        }
    }

    let id: UUID
    var title: String
    var synopsis: String
    var tags: [String]
    var type: ProjectType
    var createdAt: Date
    var updatedAt: Date
    var episodes: [ScriptEpisode]

    init(
        id: UUID = UUID(),
        title: String,
        synopsis: String = "",
        tags: [String] = [],
        type: ProjectType = .standalone,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        episodes: [ScriptEpisode] = []
    ) {
        self.id = id
        self.title = title
        self.synopsis = synopsis
        self.tags = tags
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.episodes = episodes
    }

    var orderedEpisodes: [ScriptEpisode] {
        episodes.sorted { lhs, rhs in
            if lhs.episodeNumber == rhs.episodeNumber {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.episodeNumber < rhs.episodeNumber
        }
    }

    var isEpisodic: Bool {
        type == .episodic || episodes.count > 1
    }
}

@MainActor
final class ScriptStore: ObservableObject {
    @Published private(set) var projects: [ScriptProject]
    @Published private(set) var episodes: [ScriptEpisode] = []
    private let storageURL: URL

    init() {
        storageURL = ScriptStore.makeStorageURL()
        projects = ScriptStore.load(from: storageURL)
        rebuildEpisodesCache()
    }

    func addProject(
        title: String,
        synopsis: String,
        type: ScriptProject.ProjectType
    ) -> ScriptProject {
        var project = ScriptProject(
            title: title.isEmpty ? "未命名项目" : title,
            synopsis: synopsis,
            tags: [],
            type: type
        )
        if project.episodes.isEmpty {
            project.episodes = [
                ScriptEpisode(
                    episodeNumber: 1,
                    title: type == .standalone ? "整片" : "第1集",
                    markdown: ""
                )
            ]
        }
        projects.append(project)
        persist()
        rebuildEpisodesCache()
        return project
    }

    func removeProject(id: UUID) {
        projects.removeAll { $0.id == id }
        persist()
        rebuildEpisodesCache()
    }

    func updateProject(id: UUID, update: (inout ScriptProject) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        update(&projects[index])
        projects[index].updatedAt = .now
        persist()
        rebuildEpisodesCache()
    }

    func addEpisode(
        to projectID: UUID,
        number: Int?,
        title: String,
        markdown: String
    ) -> ScriptEpisode? {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let project = projects[index]
        let nextNumber = number ?? ((project.episodes.map(\.episodeNumber).max() ?? 0) + 1)
        var episode = ScriptEpisode(
            episodeNumber: max(nextNumber, 1),
            title: title,
            markdown: markdown
        )
        episode.synopsis = makeSynopsis(from: markdown)
        projects[index].episodes.append(episode)
        projects[index].updatedAt = .now
        persist()
        rebuildEpisodesCache()
        return episode
    }

    func removeEpisode(projectID: UUID, episodeID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].episodes.removeAll { $0.id == episodeID }
        projects[index].updatedAt = .now
        persist()
        rebuildEpisodesCache()
    }

    func updateEpisode(
        projectID: UUID,
        episodeID: UUID,
        update: (inout ScriptEpisode) -> Void
    ) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        guard let episodeIndex = projects[projectIndex].episodes.firstIndex(where: { $0.id == episodeID }) else { return }
        update(&projects[projectIndex].episodes[episodeIndex])
        projects[projectIndex].episodes[episodeIndex].updatedAt = .now
        projects[projectIndex].updatedAt = .now
        persist()
        rebuildEpisodesCache()
    }

    func project(id: UUID?) -> ScriptProject? {
        guard let id else { return nil }
        return projects.first(where: { $0.id == id })
    }

    func episode(projectID: UUID?, episodeID: UUID?) -> ScriptEpisode? {
        guard
            let projectID,
            let episodeID,
            let project = project(id: projectID)
        else { return nil }
        return project.episodes.first(where: { $0.id == episodeID })
    }

    func nextEpisodeNumber(for projectID: UUID) -> Int {
        guard let project = project(id: projectID) else { return 1 }
        return (project.episodes.map(\.episodeNumber).max() ?? 0) + 1
    }

    private func rebuildEpisodesCache() {
        episodes = projects.flatMap(\.episodes)
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(projects)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("ScriptStore persist error: \(error)")
        }
    }

    private static func load(from url: URL) -> [ScriptProject] {
        guard let data = try? Data(contentsOf: url) else {
            return ScriptProject.sampleData
        }
        return (try? JSONDecoder().decode([ScriptProject].self, from: data)) ?? ScriptProject.sampleData
    }

    private static func makeStorageURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("MultiGen", isDirectory: true)
            .appendingPathComponent("script-projects.json")
    }

    private func makeSynopsis(from markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        return String(trimmed.prefix(320))
    }
}

private extension ScriptProject {
    static let sampleData: [ScriptProject] = [
        ScriptProject(
            title: "霓虹潮汐：港城追击",
            synopsis: "赛博港城里的短篇动作故事，描述凌然潜入雾港并揭露“潮汐”实验。",
            tags: ["赛博朋克", "短片"],
            type: .standalone,
            episodes: [
                ScriptEpisode(
                    episodeNumber: 1,
                    title: "整片",
                    synopsis: "凌然潜入雾港，发现潮汐实验的真相。",
                    markdown: """
## 场景一：港口天际
- **时间**：黎明
- **地点**：雾港天际线
- **人物**：凌然、港口守卫

凌然抵达雾港，天色微亮，远处的塔楼被薄雾环绕。守卫盘查他的身份，他用伪造证件蒙混过关。

## 场景二：地下隧道
- **时间**：夜
- **地点**：废弃地铁隧道
- **人物**：凌然、林克、小队成员

众人点亮头灯，在水汽弥漫的狭窄空间中前行。墙面布满旧时代的涂鸦，远处隐约传来机械声。
"""
                )
            ]
        ),
        ScriptProject(
            title: "深海纪事",
            synopsis: "系列科幻剧，记录深海城市科考队的危机与抉择。",
            tags: ["科幻", "连续剧"],
            type: .episodic,
            episodes: [
                ScriptEpisode(
                    episodeNumber: 1,
                    title: "第1集 · 入夜信号",
                    synopsis: "科考队抵达深海站，接收来自未知角落的求救信号。",
                    markdown: "第一集 Markdown 正文……"
                ),
                ScriptEpisode(
                    episodeNumber: 2,
                    title: "第2集 · 潮汐背面",
                    synopsis: "队员深入海沟，目睹有机城市残骸。",
                    markdown: "第二集 Markdown 正文……"
                )
            ]
        )
    ]
}
