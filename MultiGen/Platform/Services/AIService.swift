//
//  AIService.swift
//  MultiGen
//
//  Created by Codex on 2025/02/16.
//

import Foundation

public enum AIServiceError: Error, LocalizedError {
    case missingAPIKey
    case invalidRequest
    case transportFailure(underlying: Error)
    case serverRejected(reason: String)
    case decodingFailed
    case relayConfigurationMissing

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "尚未配置 API Key。请在设置中输入有效密钥。"
        case .invalidRequest:
            return "请求内容不完整或不符合接口要求。"
        case .transportFailure(let underlying):
            return "网络请求失败：\(underlying.localizedDescription)"
        case .serverRejected(let reason):
            return "服务拒绝了请求：\(reason)"
        case .decodingFailed:
            return "无法解析返回结果。"
        case .relayConfigurationMissing:
            return "中转服务配置不完整，请检查地址、密钥及模型选择。"
        }
    }
}

public struct AITextStreamChunk: Sendable {
    public let textDelta: String
    public let modelIdentifier: String?
    public let isTerminal: Bool
}

public protocol AITextServiceProtocol: Sendable {
    func submit(job request: SceneJobRequest) async throws -> SceneJobResult
    func stream(job request: SceneJobRequest) -> AsyncThrowingStream<AITextStreamChunk, Error>
}

public extension AITextServiceProtocol {
    func stream(job request: SceneJobRequest) -> AsyncThrowingStream<AITextStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await submit(job: request)
                    continuation.yield(
                        AITextStreamChunk(
                            textDelta: result.metadata.prompt,
                            modelIdentifier: result.metadata.model,
                            isTerminal: true
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

public protocol AIImageServiceProtocol: Sendable {
    func generateImage(for request: SceneJobRequest) async throws -> SceneJobResult
}
