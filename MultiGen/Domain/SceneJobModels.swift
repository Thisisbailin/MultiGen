//
//  SceneJobModels.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

public enum SceneJobStatus: String, Codable, Sendable {
    case idle
    case queued
    case running
    case succeeded
    case failed
}

public enum SceneJobChannel: String, Codable, Sendable {
    case text
    case image
    case video
}

public struct SceneJobRequest: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let action: SceneAction
    public let fields: [String: String]
    public let assetReferences: [String]
    public let createdAt: Date
    public let channel: SceneJobChannel

    public init(
        id: UUID = UUID(),
        action: SceneAction,
        fields: [String: String],
        assetReferences: [String] = [],
        createdAt: Date = .now,
        channel: SceneJobChannel = .text
    ) {
        self.id = id
        self.action = action
        self.fields = fields
        self.assetReferences = assetReferences
        self.createdAt = createdAt
        self.channel = channel
    }
}

public struct SceneJobResult: Hashable, Codable, Sendable {
    public struct Metadata: Hashable, Codable, Sendable {
        public let prompt: String
        public let model: String
        public let duration: TimeInterval
    }

    public let imageURL: URL?
    public let imageBase64: String?
    public let videoURL: URL?
    public let metadata: Metadata

    public init(imageURL: URL?, imageBase64: String? = nil, videoURL: URL? = nil, metadata: Metadata) {
        self.imageURL = imageURL
        self.imageBase64 = imageBase64
        self.videoURL = videoURL
        self.metadata = metadata
    }
}

public struct SceneJob: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var status: SceneJobStatus
    public let request: SceneJobRequest
    public var result: SceneJobResult?
    public var errorMessage: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        status: SceneJobStatus = .idle,
        request: SceneJobRequest,
        result: SceneJobResult? = nil,
        errorMessage: String? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.status = status
        self.request = request
        self.result = result
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }
}

public struct AuditLogEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let jobID: UUID
    public let action: SceneAction
    public let promptHash: String
    public let assetRefs: [String]
    public let modelVersion: String
    public let createdAt: Date
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        jobID: UUID,
        action: SceneAction,
        promptHash: String,
        assetRefs: [String],
        modelVersion: String,
        createdAt: Date = .now,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.jobID = jobID
        self.action = action
        self.promptHash = promptHash
        self.assetRefs = assetRefs
        self.modelVersion = modelVersion
        self.createdAt = createdAt
        self.metadata = metadata
    }
}
