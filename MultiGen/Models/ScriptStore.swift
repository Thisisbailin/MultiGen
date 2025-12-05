//
//  ScriptStore.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation
import Combine
import SwiftUI

struct ScriptScene: Identifiable, Codable, Hashable {
    let id: UUID
    var order: Int
    var title: String
    var summary: String
    var body: String
    var locationHint: String
    var timeHint: String

    enum CodingKeys: String, CodingKey {
        case id, order, title, summary, body, locationHint, timeHint
    }

    init(
        id: UUID = UUID(),
        order: Int,
        title: String,
        summary: String = "",
        body: String = "",
        locationHint: String = "",
        timeHint: String = ""
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.summary = summary
        self.body = body
        self.locationHint = locationHint
        self.timeHint = timeHint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        order = try container.decode(Int.self, forKey: .order)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        locationHint = try container.decodeIfPresent(String.self, forKey: .locationHint) ?? ""
        timeHint = try container.decodeIfPresent(String.self, forKey: .timeHint) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(order, forKey: .order)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(body, forKey: .body)
        try container.encode(locationHint, forKey: .locationHint)
        try container.encode(timeHint, forKey: .timeHint)
    }
}

struct ScriptEpisode: Identifiable, Codable, Hashable {
    let id: UUID
    var episodeNumber: Int
    var title: String
    var synopsis: String
    var markdown: String
    var scenes: [ScriptScene]
    var producerID: UUID?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, episodeNumber, title, synopsis, markdown, scenes, producerID, createdAt, updatedAt
    }

    init(
        id: UUID = UUID(),
        episodeNumber: Int,
        title: String = "",
        synopsis: String = "",
        markdown: String,
        scenes: [ScriptScene] = [],
        producerID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.episodeNumber = episodeNumber
        self.title = title
        self.synopsis = synopsis
        self.markdown = markdown
        self.scenes = scenes
        self.producerID = producerID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayLabel: String {
        if title.isEmpty == false { return title }
        return episodeNumber <= 1 ? "整片" : "第\(episodeNumber)集"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        episodeNumber = try container.decode(Int.self, forKey: .episodeNumber)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        synopsis = try container.decodeIfPresent(String.self, forKey: .synopsis) ?? ""
        markdown = try container.decodeIfPresent(String.self, forKey: .markdown) ?? ""
        scenes = try container.decodeIfPresent([ScriptScene].self, forKey: .scenes) ?? []
        producerID = try container.decodeIfPresent(UUID.self, forKey: .producerID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(episodeNumber, forKey: .episodeNumber)
        try container.encode(title, forKey: .title)
        try container.encode(synopsis, forKey: .synopsis)
        try container.encode(markdown, forKey: .markdown)
        try container.encode(scenes, forKey: .scenes)
        try container.encode(producerID, forKey: .producerID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct ProjectCharacterProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var prompt: String
    var imageData: Data?
    var variants: [CharacterVariant]

    init(
        id: UUID = UUID(),
        name: String = "",
        description: String = "",
        prompt: String = "",
        imageData: Data? = nil,
        variants: [CharacterVariant] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.prompt = prompt
        self.imageData = imageData
        self.variants = variants
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, prompt, imageData, variants
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        variants = try container.decodeIfPresent([CharacterVariant].self, forKey: .variants) ?? []
    }

    var primaryImageData: Data? {
        if let cover = variants.first(where: { $0.coverImageData != nil })?.coverImageData {
            return cover
        }
        return imageData
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(variants, forKey: .variants)
    }
}

struct ProjectSceneProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var prompt: String
    var characters: [SceneCharacter]
    var imageData: Data?
    var variants: [SceneVariant]

    init(
        id: UUID = UUID(),
        name: String = "",
        description: String = "",
        prompt: String = "",
        characters: [SceneCharacter] = [],
        imageData: Data? = nil,
        variants: [SceneVariant] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.prompt = prompt
        self.characters = characters
        self.imageData = imageData
        self.variants = variants
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, prompt, characters, imageData, variants
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        characters = try container.decodeIfPresent([SceneCharacter].self, forKey: .characters) ?? []
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        variants = try container.decodeIfPresent([SceneVariant].self, forKey: .variants) ?? []
    }

    var primaryImageData: Data? {
        if let cover = variants.first(where: { $0.coverImageData != nil })?.coverImageData {
            return cover
        }
        return imageData
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(characters, forKey: .characters)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(variants, forKey: .variants)
    }
}

struct CharacterVariant: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    var promptOverride: String
    var images: [CharacterImage]

    init(
        id: UUID = UUID(),
        label: String = "默认形态",
        promptOverride: String = "",
        images: [CharacterImage] = []
    ) {
        self.id = id
        self.label = label
        self.promptOverride = promptOverride
        self.images = images
    }

    var coverImageData: Data? {
        images.first(where: { $0.isCover })?.data ?? images.first?.data
    }
}

struct CharacterImage: Identifiable, Codable, Hashable {
    let id: UUID
    var data: Data?
    var isCover: Bool
    
    init(id: UUID = UUID(), data: Data? = nil, isCover: Bool = false) {
        self.id = id
        self.data = data
        self.isCover = isCover
    }

}

struct SceneVariant: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    var promptOverride: String
    var images: [SceneImage]

    init(
        id: UUID = UUID(),
        label: String = "默认视角",
        promptOverride: String = "",
        images: [SceneImage] = []
    ) {
        self.id = id
        self.label = label
        self.promptOverride = promptOverride
        self.images = images
    }

    var coverImageData: Data? {
        images.first(where: { $0.isCover })?.data ?? images.first?.data
    }
}

struct SceneImage: Identifiable, Codable, Hashable {
    let id: UUID
    var data: Data?
    var isCover: Bool
    
    init(id: UUID = UUID(), data: Data? = nil, isCover: Bool = false) {
        self.id = id
        self.data = data
        self.isCover = isCover
    }

}

struct EpisodeOutline: Identifiable, Codable, Hashable {
    let id: UUID
    var episodeNumber: Int
    var title: String
    var summary: String

    init(
        id: UUID = UUID(),
        episodeNumber: Int,
        title: String,
        summary: String
    ) {
        self.id = id
        self.episodeNumber = episodeNumber
        self.title = title
        self.summary = summary
    }
}

struct WritingWork: Identifiable, Codable, Hashable {
    enum WritingType: String, Codable, CaseIterable, Identifiable {
        case standalone
        case serialized

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .standalone: return "短篇/单篇"
            case .serialized: return "分章/连载"
            }
        }
    }

    let id: UUID
    var projectID: UUID
    var title: String
    var type: WritingType
    var synopsis: String
    var themeTags: [String]
    var styleHints: String
    var worldNotes: String
    var authorNotes: String
    var body: String
    var chapters: [WritingChapter]

    init(
        id: UUID = UUID(),
        projectID: UUID,
        title: String,
        type: WritingType,
        synopsis: String = "",
        themeTags: [String] = [],
        styleHints: String = "",
        worldNotes: String = "",
        authorNotes: String = "",
        body: String = "",
        chapters: [WritingChapter] = []
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.type = type
        self.synopsis = synopsis
        self.themeTags = themeTags
        self.styleHints = styleHints
        self.worldNotes = worldNotes
        self.authorNotes = authorNotes
        self.body = body
        self.chapters = chapters
    }
}

struct WritingChapter: Identifiable, Codable, Hashable {
    let id: UUID
    var order: Int
    var title: String
    var summary: String
    var body: String
    var pov: String
    var timeAndPlace: String
    var charactersInvolved: [String]

    init(
        id: UUID = UUID(),
        order: Int,
        title: String,
        summary: String = "",
        body: String = "",
        pov: String = "",
        timeAndPlace: String = "",
        charactersInvolved: [String] = []
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.summary = summary
        self.body = body
        self.pov = pov
        self.timeAndPlace = timeAndPlace
        self.charactersInvolved = charactersInvolved
    }
}

struct ProjectContainer: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var writing: WritingWork?
    var script: ScriptProject?

    init(
        id: UUID = UUID(),
        title: String,
        tags: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        writing: WritingWork? = nil,
        script: ScriptProject? = nil
    ) {
        self.id = id
        self.title = title
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.writing = writing
        self.script = script
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
    var productionStartDate: Date?
    var productionEndDate: Date?
    var notes: String
    var mainCharacters: [ProjectCharacterProfile]
    var keyScenes: [ProjectSceneProfile]
    var episodeOutlines: [EpisodeOutline]
    var productionMembers: [ProductionMember]
    var productionTasks: [ProductionTask]
    var createdAt: Date
    var updatedAt: Date
    var episodes: [ScriptEpisode]

    init(
        id: UUID = UUID(),
        title: String,
        synopsis: String = "",
        tags: [String] = [],
        type: ProjectType = .standalone,
        productionStartDate: Date? = nil,
        productionEndDate: Date? = nil,
        notes: String = "",
        mainCharacters: [ProjectCharacterProfile] = [],
        keyScenes: [ProjectSceneProfile] = [],
        episodeOutlines: [EpisodeOutline] = [],
        productionMembers: [ProductionMember] = [],
        productionTasks: [ProductionTask] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        episodes: [ScriptEpisode] = []
    ) {
        self.id = id
        self.title = title
        self.synopsis = synopsis
        self.tags = tags
        self.type = type
        self.productionStartDate = productionStartDate
        self.productionEndDate = productionEndDate
        self.notes = notes
        self.mainCharacters = mainCharacters
        self.keyScenes = keyScenes
        self.episodeOutlines = episodeOutlines
        self.productionMembers = productionMembers
        self.productionTasks = productionTasks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.episodes = episodes
    }

    enum CodingKeys: String, CodingKey {
        case id, title, synopsis, tags, type, productionStartDate, productionEndDate, notes, mainCharacters, keyScenes, episodeOutlines, productionMembers, productionTasks, createdAt, updatedAt, episodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        synopsis = try container.decode(String.self, forKey: .synopsis)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        type = try container.decode(ProjectType.self, forKey: .type)
        productionStartDate = try container.decodeIfPresent(Date.self, forKey: .productionStartDate)
        productionEndDate = try container.decodeIfPresent(Date.self, forKey: .productionEndDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        mainCharacters = try container.decodeIfPresent([ProjectCharacterProfile].self, forKey: .mainCharacters) ?? []
        keyScenes = try container.decodeIfPresent([ProjectSceneProfile].self, forKey: .keyScenes) ?? []
        episodeOutlines = try container.decodeIfPresent([EpisodeOutline].self, forKey: .episodeOutlines) ?? []
        productionMembers = try container.decodeIfPresent([ProductionMember].self, forKey: .productionMembers) ?? []
        productionTasks = try container.decodeIfPresent([ProductionTask].self, forKey: .productionTasks) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        episodes = try container.decodeIfPresent([ScriptEpisode].self, forKey: .episodes) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(synopsis, forKey: .synopsis)
        try container.encode(tags, forKey: .tags)
        try container.encode(type, forKey: .type)
        try container.encode(productionStartDate, forKey: .productionStartDate)
        try container.encode(productionEndDate, forKey: .productionEndDate)
        try container.encode(notes, forKey: .notes)
        try container.encode(mainCharacters, forKey: .mainCharacters)
        try container.encode(keyScenes, forKey: .keyScenes)
        try container.encode(productionMembers, forKey: .productionMembers)
        try container.encode(productionTasks, forKey: .productionTasks)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(episodes, forKey: .episodes)
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

struct ProductionMember: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

@MainActor
final class ScriptStore: ObservableObject {
    @Published private(set) var containers: [ProjectContainer]
    @Published private(set) var episodes: [ScriptEpisode] = []
    private let storageURL: URL

    /// Convenience: 已有脚本形态的项目列表，供现有 UI 兼容。
    var projects: [ScriptProject] {
        containers.compactMap { $0.script }
    }

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? ScriptStore.makeStorageURL()
        containers = ScriptStore.load(from: self.storageURL)
        containers = containers.map { container in
            var copy = container
            if var script = copy.script {
                for idx in script.episodes.indices {
                    normalizeScenes(in: &script.episodes[idx])
                }
                normalizeAssets(in: &script)
                copy.script = script
            }
            return copy
        }
        rebuildEpisodesCache()
    }

    // MARK: - Project Container / Writing / Script Forms

    func addProject(
        title: String,
        synopsis: String,
        type: ScriptProject.ProjectType,
        writingTitle: String? = nil,
        scriptTitle: String? = nil,
        mainCharacters: [ProjectCharacterProfile] = [],
        outlines: [EpisodeOutline] = [],
        addDefaultEpisode: Bool = true
    ) -> ProjectContainer {
        let projectID = UUID()
        let writingType: WritingWork.WritingType = (type == .episodic) ? .serialized : .standalone
        let writing = WritingWork(
            projectID: projectID,
            title: writingTitle?.isEmpty == false ? writingTitle! : title,
            type: writingType,
            synopsis: synopsis,
            chapters: [
                WritingChapter(
                    order: 1,
                    title: writingType == .serialized ? "第1章" : "草稿",
                    summary: "",
                    body: ""
                )
            ]
        )
        var container = ProjectContainer(
            id: projectID,
            title: title.isEmpty ? "未命名项目" : title,
            tags: [],
            createdAt: .now,
            updatedAt: .now,
            writing: writing,
            script: nil
        )
        containers.append(container)
        _ = attachScriptForm(
            to: projectID,
            type: type,
            mainCharacters: [],
            outlines: outlines,
            addDefaultEpisode: addDefaultEpisode
        )
        if let idx = containerIndex(for: projectID) {
            containers[idx].script?.title = scriptTitle?.isEmpty == false ? scriptTitle! : containers[idx].title
            containers[idx].updatedAt = .now
            persist()
            rebuildEpisodesCache()
        }
        return containers.last!
    }

    func attachScriptForm(
        to projectID: UUID,
        type: ScriptProject.ProjectType,
        mainCharacters: [ProjectCharacterProfile] = [],
        outlines: [EpisodeOutline] = [],
        addDefaultEpisode: Bool = true
    ) -> ScriptProject? {
        guard let index = containerIndex(for: projectID) else { return nil }
        if containers[index].script != nil { return containers[index].script }
        var script = ScriptProject(
            id: projectID,
            title: containers[index].title,
            synopsis: containers[index].writing?.synopsis ?? "",
            tags: [],
            type: type,
            mainCharacters: mainCharacters,
            episodeOutlines: outlines
        )
        if addDefaultEpisode {
            script.episodes = [
                ScriptEpisode(
                    episodeNumber: 1,
                    title: type == .standalone ? "整片" : "第1集",
                    markdown: ""
                )
            ]
        }
        containers[index].script = script
        containers[index].updatedAt = .now
        persist()
        rebuildEpisodesCache()
        return script
    }

    func removeProject(id: UUID) {
        containers.removeAll { $0.id == id }
        persist()
        rebuildEpisodesCache()
    }

    func updateProject(id: UUID, update: (inout ScriptProject) -> Void) {
        guard let index = containerIndex(for: id) else { return }
        guard containers[index].script != nil else { return }
        update(&containers[index].script!)
        normalizeAssets(in: &containers[index].script!)
        containers[index].script!.updatedAt = .now
        containers[index].updatedAt = .now
        persist()
        rebuildEpisodesCache()
    }

    func updateProductionMetadata(
        projectID: UUID,
        members: [ProductionMember],
        tasks: [ProductionTask],
        assignments: [UUID: UUID?]
    ) {
        updateProject(id: projectID) { editable in
            editable.productionMembers = members
            editable.productionTasks = tasks
            editable.episodes = editable.episodes.map { episode in
                var updated = episode
                if let override = assignments[episode.id] {
                    updated.producerID = override
                }
                return updated
            }
        }
    }

    func reorderCharacters(projectID: UUID, source: IndexSet, destination: Int) {
        guard let index = containerIndex(for: projectID), containers[index].script != nil else { return }
        containers[index].script!.mainCharacters.move(fromOffsets: source, toOffset: destination)
        containers[index].script!.updatedAt = .now
        containers[index].updatedAt = .now
        persist()
    }

    func reorderScenes(projectID: UUID, source: IndexSet, destination: Int) {
        guard let index = containerIndex(for: projectID), containers[index].script != nil else { return }
        containers[index].script!.keyScenes.move(fromOffsets: source, toOffset: destination)
        containers[index].script!.updatedAt = .now
        containers[index].updatedAt = .now
        persist()
    }

    func ensureWriting(projectID: UUID, type: WritingWork.WritingType = .standalone) -> WritingWork? {
        guard let idx = containerIndex(for: projectID) else { return nil }
        if let writing = containers[idx].writing { return writing }
        let writing = WritingWork(
            projectID: projectID,
            title: containers[idx].title,
            type: type,
            chapters: [WritingChapter(order: 1, title: type == .serialized ? "第1章" : "草稿")]
        )
        containers[idx].writing = writing
        containers[idx].updatedAt = .now
        persist()
        return writing
    }

    func updateWriting(projectID: UUID, update: (inout WritingWork) -> Void) {
        guard let idx = containerIndex(for: projectID) else { return }
        var writing = containers[idx].writing ?? WritingWork(projectID: projectID, title: containers[idx].title, type: .standalone, chapters: [WritingChapter(order: 1, title: "草稿")])
        update(&writing)
        writing.projectID = projectID
        containers[idx].writing = writing
        containers[idx].updatedAt = .now
        persist()
    }
    func replaceScript(projectID: UUID, with payload: ScriptImportPayload) {
        let scriptType: ScriptProject.ProjectType = payload.episodes.count > 1 ? .episodic : .standalone
        guard let script = ensureScript(projectID: projectID, type: scriptType) else { return }
        updateProject(id: projectID) { editable in
            editable.title = editable.title.isEmpty ? "未命名剧本" : editable.title
            editable.synopsis = payload.synopsis
            editable.notes = payload.synopsis
            editable.mainCharacters = payload.characters
            editable.keyScenes = payload.episodes.flatMap { $0.scenes }.map {
                ProjectSceneProfile(
                    id: UUID(),
                    name: $0.title,
                    description: $0.body
                )
            }
            editable.episodeOutlines = payload.outlines
            editable.type = scriptType
            editable.productionStartDate = editable.productionStartDate ?? Date()
            editable.productionTasks = []
            editable.episodes = []
        }
        for item in payload.episodes {
            let episodeMarkdown: String
            if item.scenes.isEmpty {
                episodeMarkdown = item.body
            } else {
                episodeMarkdown = item.scenes.map { $0.body }.joined(separator: "\n\n")
            }
            if let episode = addEpisode(to: projectID, number: item.episodeNumber, title: item.title, markdown: episodeMarkdown) {
                let scenes: [ScriptScene]
                if item.scenes.isEmpty {
                    scenes = [
                        ScriptScene(
                            order: 1,
                            title: "未命名场景",
                            summary: "",
                            body: item.body
                        )
                    ]
                } else {
                    scenes = item.scenes.map { scene in
                        ScriptScene(
                            order: scene.index,
                            title: scene.title,
                            summary: "",
                            body: scene.body,
                            locationHint: scene.locationHint,
                            timeHint: scene.timeHint
                        )
                    }
                }
                updateEpisode(projectID: projectID, episodeID: episode.id) { editable in
                    editable.scenes = scenes
                }
            }
        }
        rebuildEpisodesCache()
    }

    func addEpisode(
        to projectID: UUID,
        number: Int?,
        title: String,
        markdown: String
    ) -> ScriptEpisode? {
        guard let index = containerIndex(for: projectID) else { return nil }
        guard containers[index].script != nil else { return nil }
        let project = containers[index].script!
        let nextNumber = number ?? ((project.episodes.map(\.episodeNumber).max() ?? 0) + 1)
        var episode = ScriptEpisode(
            episodeNumber: max(nextNumber, 1),
            title: title,
            markdown: markdown
        )
        episode.synopsis = makeSynopsis(from: markdown)
        normalizeScenes(in: &episode)
        containers[index].script!.episodes.append(episode)
        containers[index].script!.updatedAt = .now
        containers[index].updatedAt = .now
        persist()
        rebuildEpisodesCache()
        return episode
    }

    func removeEpisode(projectID: UUID, episodeID: UUID) {
        guard let index = containerIndex(for: projectID), containers[index].script != nil else { return }
        containers[index].script!.episodes.removeAll { $0.id == episodeID }
        containers[index].script!.updatedAt = .now
        containers[index].updatedAt = .now
        persist()
        rebuildEpisodesCache()
    }

    func updateEpisode(
        projectID: UUID,
        episodeID: UUID,
        update: (inout ScriptEpisode) -> Void
    ) {
        guard let projectIndex = containerIndex(for: projectID), containers[projectIndex].script != nil else { return }
        guard let episodeIndex = containers[projectIndex].script!.episodes.firstIndex(where: { $0.id == episodeID }) else { return }
        update(&containers[projectIndex].script!.episodes[episodeIndex])
        normalizeScenes(in: &containers[projectIndex].script!.episodes[episodeIndex])
        containers[projectIndex].script!.episodes[episodeIndex].updatedAt = .now
        containers[projectIndex].script!.updatedAt = .now
        containers[projectIndex].updatedAt = .now
        persist()
        rebuildEpisodesCache()
    }

    func project(id: UUID?) -> ScriptProject? {
        guard let id else { return nil }
        return containers.first(where: { $0.id == id })?.script
    }

    func ensureScript(projectID: UUID, type: ScriptProject.ProjectType = .standalone) -> ScriptProject? {
        if let existing = project(id: projectID) {
            return existing
        }
        return attachScriptForm(to: projectID, type: type)
    }

    func episode(projectID: UUID?, episodeID: UUID?) -> ScriptEpisode? {
        guard
            let projectID,
            let episodeID,
            let project = project(id: projectID)
        else { return nil }
        return project.episodes.first(where: { $0.id == episodeID })
    }

    func addScene(
        to projectID: UUID,
        episodeID: UUID,
        title: String,
        locationHint: String = "",
        timeHint: String = ""
    ) -> ScriptScene? {
        var newSceneID: UUID?
        updateEpisode(projectID: projectID, episodeID: episodeID) { episode in
            let nextOrder = (episode.scenes.map(\.order).max() ?? 0) + 1
            var scene = ScriptScene(
                order: nextOrder,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名场景 \(nextOrder)" : title,
                summary: "",
                body: "",
                locationHint: locationHint.trimmingCharacters(in: .whitespacesAndNewlines),
                timeHint: timeHint.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            scene.summary = makeSynopsis(from: scene.body)
            episode.scenes.append(scene)
            newSceneID = scene.id
        }
        guard let id = newSceneID else { return nil }
        return episode(projectID: projectID, episodeID: episodeID)?.scenes.first(where: { $0.id == id })
    }

    func updateSceneTitle(projectID: UUID, episodeID: UUID, sceneID: UUID, title: String) {
        updateEpisode(projectID: projectID, episodeID: episodeID) { episode in
            guard let index = episode.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
            episode.scenes[index].title = title
        }
    }

    func updateSceneBody(projectID: UUID, episodeID: UUID, sceneID: UUID, body: String) {
        updateEpisode(projectID: projectID, episodeID: episodeID) { episode in
            guard let index = episode.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
            episode.scenes[index].body = body
            episode.scenes[index].summary = makeSynopsis(from: body)
        }
    }

    func updateSceneLocationHint(projectID: UUID, episodeID: UUID, sceneID: UUID, hint: String) {
        updateEpisode(projectID: projectID, episodeID: episodeID) { episode in
            guard let index = episode.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
            episode.scenes[index].locationHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func updateSceneTimeHint(projectID: UUID, episodeID: UUID, sceneID: UUID, hint: String) {
        updateEpisode(projectID: projectID, episodeID: episodeID) { episode in
            guard let index = episode.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
            episode.scenes[index].timeHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func deleteScene(projectID: UUID, episodeID: UUID, sceneID: UUID) {
        updateEpisode(projectID: projectID, episodeID: episodeID) { episode in
            guard episode.scenes.count > 1 else { return }
            episode.scenes.removeAll { $0.id == sceneID }
        }
    }

    func nextEpisodeNumber(for projectID: UUID) -> Int {
        guard let project = project(id: projectID) else { return 1 }
        return (project.episodes.map(\.episodeNumber).max() ?? 0) + 1
    }

    private func rebuildEpisodesCache() {
        episodes = containers.compactMap { $0.script?.episodes }.flatMap { $0 }
    }

    private func containerIndex(for id: UUID) -> Int? {
        containers.firstIndex { $0.id == id }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(containers)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("ScriptStore persist error: \(error)")
        }
    }

    private static func load(from url: URL) -> [ProjectContainer] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([ProjectContainer].self, from: data)) ?? []
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

    private func normalizeScenes(in episode: inout ScriptEpisode) {
        if episode.scenes.isEmpty {
            let body = episode.markdown
            var scene = ScriptScene(order: 1, title: "未命名场景 1", summary: "", body: body)
            scene.summary = makeSynopsis(from: body)
            episode.scenes = [scene]
        }
        episode.scenes.sort { $0.order < $1.order }
        for index in episode.scenes.indices {
            episode.scenes[index].order = index + 1
            if episode.scenes[index].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                episode.scenes[index].title = "未命名场景 \(index + 1)"
            }
            episode.scenes[index].summary = makeSynopsis(from: episode.scenes[index].body)
        }
        episode.markdown = composeMarkdown(from: episode.scenes)
        episode.synopsis = makeSynopsis(from: episode.markdown)
    }

    private func composeMarkdown(from scenes: [ScriptScene]) -> String {
        scenes
            .sorted { $0.order < $1.order }
            .map { $0.body }
            .joined(separator: "\n\n")
    }

    private func normalizeAssets(in project: inout ScriptProject) {
        for idx in project.mainCharacters.indices {
            project.mainCharacters[idx].variants = normalizeCharacterVariants(
                variants: project.mainCharacters[idx].variants,
                fallbackImage: project.mainCharacters[idx].imageData
            )
        }
        for idx in project.keyScenes.indices {
            project.keyScenes[idx].variants = normalizeSceneVariants(
                variants: project.keyScenes[idx].variants,
                fallbackImage: project.keyScenes[idx].imageData
            )
        }
    }

    private func normalizeCharacterVariants(variants: [CharacterVariant], fallbackImage: Data?) -> [CharacterVariant] {
        if variants.isEmpty {
            var variant = CharacterVariant(label: "默认形态", promptOverride: "", images: [])
            if let fallbackImage {
                variant.images = [CharacterImage(data: fallbackImage, isCover: true)]
            }
            return [variant]
        }
        return variants.map { variant in
            var copy = variant
            if copy.images.isEmpty, let fallbackImage {
                copy.images = [CharacterImage(data: fallbackImage, isCover: true)]
            } else {
                copy.images = ensureCoverFlag(copy.images)
            }
            return copy
        }
    }

    private func normalizeSceneVariants(variants: [SceneVariant], fallbackImage: Data?) -> [SceneVariant] {
        if variants.isEmpty {
            var variant = SceneVariant(label: "默认视角", promptOverride: "", images: [])
            if let fallbackImage {
                variant.images = [SceneImage(data: fallbackImage, isCover: true)]
            }
            return [variant]
        }
        return variants.map { variant in
            var copy = variant
            if copy.images.isEmpty, let fallbackImage {
                copy.images = [SceneImage(data: fallbackImage, isCover: true)]
            } else {
                copy.images = ensureCoverFlag(copy.images)
            }
            return copy
        }
    }

    private func ensureCoverFlag<T: VariantImageRepresentable>(_ images: [T]) -> [T] {
        guard images.isEmpty == false else { return images }
        var updated = images
        if updated.contains(where: { $0.isCover }) == false {
            updated[0].isCover = true
        } else {
            var firstCoverSet = false
            for idx in updated.indices {
                if updated[idx].isCover {
                    if firstCoverSet {
                        updated[idx].isCover = false
                    } else {
                        firstCoverSet = true
                    }
                }
            }
        }
        return updated
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
