//
//  RelayVideoService.swift
//  MultiGen
//
//  Created by Codex on 2025/02/16.
//

import Foundation

final class RelayVideoService {
    private let configuration: AppConfiguration
    private let session: URLSession

    init(configuration: AppConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func generateVideo(for request: SceneJobRequest) async throws -> SceneJobResult {
        let snapshot = await MainActor.run { configuration.relayVideoSettingsSnapshot() }
        guard let snapshot else {
            throw AIServiceError.relayConfigurationMissing
        }

        let endpoint = snapshot.endpoint(for: "/videos/generations")
        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidRequest
        }

        let body = RelayVideoRequest(
            model: snapshot.model,
            prompt: promptBody(for: request)
        )
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(snapshot.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.transportFailure(underlying: URLError(.badServerResponse))
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? "<binary>"
            print("[RelayVideoService] HTTP \(httpResponse.statusCode) error body: \(bodyString)")
            if let relayError = try? JSONDecoder().decode(RelayAPIError.self, from: data) {
                throw AIServiceError.serverRejected(reason: relayError.error.message)
            }
            throw AIServiceError.serverRejected(reason: "HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let relayResponse = try? decoder.decode(RelayVideoResponse.self, from: data),
              let first = relayResponse.data.first else {
            throw AIServiceError.decodingFailed
        }

        let metadata = SceneJobResult.Metadata(
            prompt: body.prompt,
            model: snapshot.model,
            duration: 0
        )

        if let urlString = first.url, let remote = URL(string: urlString) {
            return SceneJobResult(imageURL: nil, imageBase64: nil, videoURL: remote, metadata: metadata)
        }
        if let b64 = first.b64JSON ?? first.b64Json,
           let data = Data(base64Encoded: b64),
           let tmpURL = try? saveTemporaryVideo(data: data) {
            return SceneJobResult(imageURL: nil, imageBase64: nil, videoURL: tmpURL, metadata: metadata)
        }
        throw AIServiceError.decodingFailed
    }

    private func promptBody(for request: SceneJobRequest) -> String {
        let sortedFields = request.fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)：\($0.value)" }
            .joined(separator: ", ")

        return "\(request.action.displayName)：\(sortedFields)"
    }

    private func saveTemporaryVideo(data: Data) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("multigen-video-\(UUID().uuidString).mp4")
        try data.write(to: tmp, options: .atomic)
        return tmp
    }
}

private struct RelayVideoRequest: Encodable {
    let model: String
    let prompt: String
}

private struct RelayVideoResponse: Decodable {
    struct Payload: Decodable {
        let url: String?
        let b64JSON: String?
        let b64Json: String?
    }

    let data: [Payload]
}
