//
//  GeminiTextService.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation
import os

public final class GeminiTextService: GeminiTextServiceProtocol {
    private let credentialsStore: CredentialsStoreProtocol
    private let session: URLSession
    private let modelProvider: @Sendable () async -> GeminiModel
    private let logger = Logger(subsystem: "com.joe.MultiGen", category: "GeminiText")

    public init(
        credentialsStore: CredentialsStoreProtocol,
        session: URLSession = .shared,
        modelProvider: @escaping @Sendable () async -> GeminiModel
    ) {
        self.credentialsStore = credentialsStore
        self.session = session
        self.modelProvider = modelProvider
    }

    public func submit(job request: SceneJobRequest) async throws -> SceneJobResult {
        let apiKey = try credentialsStore.fetchAPIKey()
        guard !apiKey.isEmpty else { throw GeminiServiceError.missingAPIKey }

        let model = await modelProvider()
        logger.log("Text request using model: \(model.rawValue, privacy: .public)")
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model.rawValue):generateContent?key=\(apiKey)") else {
            throw GeminiServiceError.invalidRequest
        }

        let combinedPrompt = makeCombinedPrompt(for: request)

        let payload = GeminiGenerateContentRequest(
            contents: [
                .init(
                    role: "user",
                    parts: [.init(text: combinedPrompt)]
                )
            ],
            generationConfig: .init(temperature: 0.85, topP: 0.95, topK: 32)
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            logger.error("Transport error: \(error.localizedDescription, privacy: .public)")
            throw GeminiServiceError.transportFailure(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.transportFailure(underlying: URLError(.badServerResponse))
        }

        logger.log("Text response status: \(httpResponse.statusCode, privacy: .public)")

        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? "<binary>"
            logger.error("Gemini text error payload: \(bodyString, privacy: .public)")
            if let apiError = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data) {
                throw GeminiServiceError.serverRejected(reason: apiError.error.message)
            }
            throw GeminiServiceError.serverRejected(reason: "HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let responseBody = try? decoder.decode(GeminiGenerateContentResponse.self, from: data),
              let text = responseBody.candidates?.first?.content?.parts.first?.text else {
            let debugText = String(data: data, encoding: .utf8) ?? "<binary>"
            logger.error("Failed to decode text payload: \(debugText, privacy: .public)")
            throw GeminiServiceError.decodingFailed
        }
        if let raw = String(data: data, encoding: .utf8) {
            print("[GeminiTextService] Raw response: \(raw)")
        }

        logger.log("Text response snippet: \(text.prefix(100), privacy: .public)")

        let metadata = SceneJobResult.Metadata(
            prompt: text,
            model: model.displayName,
            duration: 0
        )

        return SceneJobResult(imageURL: nil, imageBase64: nil, metadata: metadata)
    }

    private func makeCombinedPrompt(for request: SceneJobRequest) -> String {
        let systemPrompt = request.fields["systemPrompt"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredFields = request.fields.filter { $0.key != "systemPrompt" }
        let body = promptBody(action: request.action, fields: filteredFields, assetRefs: request.assetReferences)
        if let systemPrompt, systemPrompt.isEmpty == false {
            return "\(systemPrompt)\n\(body)"
        }
        return body
    }

    private func promptBody(action: SceneAction, fields: [String: String], assetRefs: [String]) -> String {
        let sortedFields = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)：\($0.value)" }
            .joined(separator: "\n")

        let assetRefsText = assetRefs.isEmpty
            ? ""
            : "\n参考素材：\(assetRefs.joined(separator: ", "))"

        return """
        操作：\(action.displayName)
        字段：
        \(sortedFields)\(assetRefsText)
        """
    }
}
