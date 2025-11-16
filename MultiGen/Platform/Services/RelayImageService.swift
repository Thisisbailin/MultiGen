//
//  RelayImageService.swift
//  MultiGen
//
//  Created by Codex on 2025/02/16.
//

import Foundation

final class RelayImageService: GeminiImageServiceProtocol {
    private let configuration: AppConfiguration
    private let session: URLSession

    init(configuration: AppConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func generateImage(for request: SceneJobRequest) async throws -> SceneJobResult {
        let snapshot = await MainActor.run { configuration.relaySettingsSnapshot() }
        guard let snapshot else {
            throw GeminiServiceError.relayConfigurationMissing
        }

        let endpoint = RelaySettingsSnapshot.normalize(baseURL: snapshot.baseURL) + "/v1/images/generations"
        guard let url = URL(string: endpoint) else {
            throw GeminiServiceError.invalidRequest
        }

        let payload = RelayImageRequest(model: snapshot.model, prompt: promptBody(for: request))
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(snapshot.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw GeminiServiceError.transportFailure(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            if let relayError = try? JSONDecoder().decode(RelayAPIError.self, from: data) {
                throw GeminiServiceError.serverRejected(reason: relayError.error.message)
            }
            throw GeminiServiceError.serverRejected(reason: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let relayResponse = try? decoder.decode(RelayImageResponse.self, from: data),
              let first = relayResponse.data.first else {
            throw GeminiServiceError.decodingFailed
        }

        let metadata = SceneJobResult.Metadata(
            prompt: payload.prompt,
            model: snapshot.model,
            duration: 0
        )

        if let base64 = first.b64JSON {
            return SceneJobResult(imageURL: nil, imageBase64: base64, metadata: metadata)
        } else if let urlString = first.url, let remoteURL = URL(string: urlString) {
            return SceneJobResult(imageURL: remoteURL, imageBase64: nil, metadata: metadata)
        } else {
            throw GeminiServiceError.decodingFailed
        }
    }

    private func promptBody(for request: SceneJobRequest) -> String {
        let sortedFields = request.fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)：\($0.value)" }
            .joined(separator: ", ")

        return "\(request.action.displayName)：\(sortedFields)"
    }
}

private struct RelayImageRequest: Encodable {
    let model: String
    let prompt: String
}

private struct RelayImageResponse: Decodable {
    struct DataPayload: Decodable {
        let url: String?
        let b64JSON: String?
    }

    let data: [DataPayload]
}
