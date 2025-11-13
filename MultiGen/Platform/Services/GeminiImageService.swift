//
//  GeminiImageService.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation
import os

struct GeminiGenerateImagesRequest: Encodable {
    let prompt: String
}

struct GeminiGenerateImagesResponse: Decodable {
    struct GeneratedImage: Decodable {
        let data: String?
        let mimeType: String?
        let url: String?
        let storageUri: String?
    }

    let generatedImages: [GeneratedImage]?
}

public final class GeminiImageService: GeminiImageServiceProtocol {
    private let credentialsStore: CredentialsStoreProtocol
    private let session: URLSession
    private let modelProvider: @Sendable () async -> GeminiModel
    private let logger = Logger(subsystem: "com.joe.MultiGen", category: "GeminiImage")

    public init(
        credentialsStore: CredentialsStoreProtocol,
        session: URLSession = .shared,
        modelProvider: @escaping @Sendable () async -> GeminiModel
    ) {
        self.credentialsStore = credentialsStore
        self.session = session
        self.modelProvider = modelProvider
    }

    public func generateImage(for request: SceneJobRequest) async throws -> SceneJobResult {
        let apiKey = try credentialsStore.fetchAPIKey()
        guard !apiKey.isEmpty else { throw GeminiServiceError.missingAPIKey }

        let model = await modelProvider()
        logger.log("Image request using model: \(model.rawValue, privacy: .public)")

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model.rawValue):generateImages?key=\(apiKey)") else {
            throw GeminiServiceError.invalidRequest
        }

        let promptText = promptBody(for: request)
        let payload = GeminiGenerateImagesRequest(prompt: promptText)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            logger.error("Image transport error: \(error.localizedDescription, privacy: .public)")
            throw GeminiServiceError.transportFailure(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.transportFailure(underlying: URLError(.badServerResponse))
        }

        logger.log("Image response status: \(httpResponse.statusCode, privacy: .public)")

        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? "<binary>"
            logger.error("Gemini image error payload: \(bodyString, privacy: .public)")
            if let apiError = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data) {
                throw GeminiServiceError.serverRejected(reason: apiError.error.message)
            }
            throw GeminiServiceError.serverRejected(reason: "HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let responseBody = try? decoder.decode(GeminiGenerateImagesResponse.self, from: data),
              let imageData = responseBody.generatedImages?.first?.data else {
            let debugText = String(data: data, encoding: .utf8) ?? "<binary>"
            logger.error("Failed to decode image payload: \(debugText, privacy: .public)")
            throw GeminiServiceError.decodingFailed
        }

        logger.log("Image payload received (base64 size: \(imageData.count, privacy: .public))")

        let metadata = SceneJobResult.Metadata(
            prompt: promptText,
            model: model.displayName,
            duration: 0
        )

        return SceneJobResult(imageURL: nil, imageBase64: imageData, metadata: metadata)
    }

    private func promptBody(for request: SceneJobRequest) -> String {
        let sortedFields = request.fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)：\($0.value)" }
            .joined(separator: ", ")

        return "\(request.action.displayName)：\(sortedFields)"
    }
}
