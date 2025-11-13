//
//  RelayTextService.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

final class RelayTextService: GeminiTextServiceProtocol {
    private let configuration: AppConfiguration
    private let session: URLSession

    init(configuration: AppConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func submit(job request: SceneJobRequest) async throws -> SceneJobResult {
        let snapshot = await MainActor.run { relaySnapshot() }
        guard let snapshot else {
            throw GeminiServiceError.relayConfigurationMissing
        }

        let endpoint = RelayTextService.normalize(baseURL: snapshot.baseURL) + "/v1/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw GeminiServiceError.invalidRequest
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(snapshot.apiKey)", forHTTPHeaderField: "Authorization")

        let body = RelayChatRequest(
            model: snapshot.model,
            messages: [
                .init(role: "system", content: "You are a helpful visual assistant, please follow the user's instructions exactly."),
                .init(role: "user", content: promptBody(for: request))
            ],
            temperature: 0.85
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw GeminiServiceError.transportFailure(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.transportFailure(underlying: URLError(.badServerResponse))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let relayError = try? JSONDecoder().decode(RelayAPIError.self, from: data) {
                throw GeminiServiceError.serverRejected(reason: relayError.error.message)
            }
            throw GeminiServiceError.serverRejected(reason: "HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let result = try? decoder.decode(RelayChatResponse.self, from: data),
              let text = result.choices.first?.message.content else {
            throw GeminiServiceError.decodingFailed
        }

        let metadata = SceneJobResult.Metadata(
            prompt: text,
            model: snapshot.model,
            duration: 0
        )
        return SceneJobResult(imageURL: nil, imageBase64: nil, metadata: metadata)
    }

    @MainActor
    private func relaySnapshot() -> RelaySettingsSnapshot? {
        guard configuration.relayEnabled,
              configuration.relayProviderType == .openai,
              let selected = configuration.relaySelectedModel,
              !selected.isEmpty else { return nil }

        let base = configuration.relayAPIBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = configuration.relayAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard base.isEmpty == false, key.isEmpty == false else { return nil }
        return RelaySettingsSnapshot(baseURL: base, apiKey: key, model: selected)
    }

    private func promptBody(for request: SceneJobRequest) -> String {
        let sortedFields = request.fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)：\($0.value)" }
            .joined(separator: "\n")

        let assetRefs = request.assetReferences.isEmpty
            ? ""
            : "\n参考素材：\(request.assetReferences.joined(separator: ", "))"

        return """
        操作：\(request.action.displayName)
        字段：
        \(sortedFields)\(assetRefs)
        """
    }

    static func normalize(baseURL: String) -> String {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}

private struct RelaySettingsSnapshot {
    let baseURL: String
    let apiKey: String
    let model: String
}

private struct RelayChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct RelayChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct RelayAPIError: Decodable {
    struct APIError: Decodable {
        let message: String
    }
    let error: APIError
}
