//
//  StoryboardModels.swift
//  MultiGen
//
//  Created by Joe on 2025/11/13.
//

import Foundation

public struct StoryboardEntryFields: Codable, Hashable, Sendable {
    public var shotNumber: Int
    public var shotScale: String
    public var cameraMovement: String
    public var duration: String
    public var dialogueOrOS: String
    public var aiPrompt: String

    public init(
        shotNumber: Int = 1,
        shotScale: String = "",
        cameraMovement: String = "",
        duration: String = "",
        dialogueOrOS: String = "",
        aiPrompt: String = ""
    ) {
        self.shotNumber = shotNumber
        self.shotScale = shotScale
        self.cameraMovement = cameraMovement
        self.duration = duration
        self.dialogueOrOS = dialogueOrOS
        self.aiPrompt = aiPrompt
    }
}

public enum StoryboardEntryStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case draft
    case pendingReview
    case approved

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .draft: return "草稿"
        case .pendingReview: return "待确认"
        case .approved: return "已确认"
        }
    }

    public var indicatorColor: String {
        switch self {
        case .draft: return "gray"
        case .pendingReview: return "orange"
        case .approved: return "green"
        }
    }
}

public struct StoryboardRevision: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let version: Int
    public let authorRole: StoryboardDialogueRole
    public let summary: String
    public let fields: StoryboardEntryFields
    public let sourceTurnID: UUID?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        version: Int,
        authorRole: StoryboardDialogueRole,
        summary: String,
        fields: StoryboardEntryFields,
        sourceTurnID: UUID?,
        createdAt: Date = .now
    ) {
        self.id = id
        self.version = version
        self.authorRole = authorRole
        self.summary = summary
        self.fields = fields
        self.sourceTurnID = sourceTurnID
        self.createdAt = createdAt
    }
}

public struct StoryboardEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let episodeID: UUID
    public var fields: StoryboardEntryFields
    public var status: StoryboardEntryStatus
    public var version: Int
    public var notes: String
    public var revisions: [StoryboardRevision]
    public var lastTurnID: UUID?
    public var sceneTitle: String
    public var sceneSummary: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        episodeID: UUID,
        fields: StoryboardEntryFields,
        status: StoryboardEntryStatus = .draft,
        version: Int = 1,
        notes: String = "",
        revisions: [StoryboardRevision] = [],
        lastTurnID: UUID? = nil,
        sceneTitle: String = "未命名场景",
        sceneSummary: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.episodeID = episodeID
        self.fields = fields
        self.status = status
        self.version = version
        self.notes = notes
        self.revisions = revisions
        self.lastTurnID = lastTurnID
        self.sceneTitle = sceneTitle
        self.sceneSummary = sceneSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    enum CodingKeys: String, CodingKey {
        case id
        case episodeID
        case fields
        case status
        case version
        case notes
        case revisions
        case lastTurnID
        case sceneTitle
        case sceneSummary
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        episodeID = try container.decode(UUID.self, forKey: .episodeID)
        fields = try container.decode(StoryboardEntryFields.self, forKey: .fields)
        status = try container.decode(StoryboardEntryStatus.self, forKey: .status)
        version = try container.decode(Int.self, forKey: .version)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        revisions = try container.decodeIfPresent([StoryboardRevision].self, forKey: .revisions) ?? []
        lastTurnID = try container.decodeIfPresent(UUID.self, forKey: .lastTurnID)
        sceneTitle = try container.decodeIfPresent(String.self, forKey: .sceneTitle) ?? "未命名场景"
        sceneSummary = try container.decodeIfPresent(String.self, forKey: .sceneSummary) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(episodeID, forKey: .episodeID)
        try container.encode(fields, forKey: .fields)
        try container.encode(status, forKey: .status)
        try container.encode(version, forKey: .version)
        try container.encode(notes, forKey: .notes)
        try container.encode(revisions, forKey: .revisions)
        try container.encodeIfPresent(lastTurnID, forKey: .lastTurnID)
        try container.encode(sceneTitle, forKey: .sceneTitle)
        try container.encode(sceneSummary, forKey: .sceneSummary)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public enum StoryboardDialogueRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

public struct StoryboardDialogueTurn: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let episodeID: UUID
    public let role: StoryboardDialogueRole
    public let message: String
    public let referencedEntryIDs: [UUID]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        episodeID: UUID,
        role: StoryboardDialogueRole,
        message: String,
        referencedEntryIDs: [UUID] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.episodeID = episodeID
        self.role = role
        self.message = message
        self.referencedEntryIDs = referencedEntryIDs
        self.createdAt = createdAt
    }
}

public struct StoryboardWorkspace: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let episodeID: UUID
    public var episodeNumber: Int
    public var episodeTitle: String
    public var episodeSynopsis: String
    public var entries: [StoryboardEntry]
    public var dialogueTurns: [StoryboardDialogueTurn]
    public var lastSummary: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        episodeID: UUID,
        episodeNumber: Int,
        episodeTitle: String,
        episodeSynopsis: String,
        entries: [StoryboardEntry] = [],
        dialogueTurns: [StoryboardDialogueTurn] = [],
        lastSummary: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.episodeID = episodeID
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.episodeSynopsis = episodeSynopsis
        self.entries = entries
        self.dialogueTurns = dialogueTurns
        self.lastSummary = lastSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var orderedEntries: [StoryboardEntry] {
        entries.sorted { $0.fields.shotNumber < $1.fields.shotNumber }
    }
}
