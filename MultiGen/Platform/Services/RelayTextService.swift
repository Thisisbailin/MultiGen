//
//  RelayTextService.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

final class RelayTextService: AITextServiceProtocol {
    private let configuration: AppConfiguration
    private let session: URLSession
    private let modelOverrideField = "__modelOverride"

    init(configuration: AppConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func submit(job request: SceneJobRequest) async throws -> SceneJobResult {
        let snapshot = await snapshot(for: request)
        guard let snapshot else {
            throw AIServiceError.relayConfigurationMissing
        }

        let endpoint = snapshot.endpoint(for: "/chat/completions")
        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidRequest
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(snapshot.apiKey)", forHTTPHeaderField: "Authorization")

        let combinedPrompt = makeCombinedPrompt(for: request, model: snapshot.model)

        let body = RelayChatRequest(
            model: snapshot.model,
            messages: [.init(role: "user", content: combinedPrompt)],
            temperature: 0.85,
            stream: nil
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw AIServiceError.transportFailure(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.transportFailure(underlying: URLError(.badServerResponse))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? "<binary>"
            print("[RelayTextService] HTTP \(httpResponse.statusCode) error body: \(bodyString)")
            if let relayError = try? JSONDecoder().decode(RelayAPIError.self, from: data) {
                throw AIServiceError.serverRejected(reason: relayError.error.message)
            }
            throw AIServiceError.serverRejected(reason: "HTTP \(httpResponse.statusCode)")
        }

        logRawResponse(data)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let result = try? decoder.decode(RelayChatResponse.self, from: data),
              let text = result.choices.first?.message.content else {
            throw AIServiceError.decodingFailed
        }

        if let usage = result.usage {
            print("[RelayTextService] Usage -> prompt: \(usage.promptTokens ?? 0), completion: \(usage.completionTokens ?? 0), total: \(usage.totalTokens ?? 0)")
        }

        let imageURLString = result.choices.first?.message.images?.compactMap { $0.imageURL?.url }.first
        let parsedImage = Self.parseImageURL(imageURLString)

        let metadata = SceneJobResult.Metadata(
            prompt: text,
            model: snapshot.model,
            duration: 0
        )
        return SceneJobResult(
            imageURL: parsedImage.url,
            imageBase64: parsedImage.base64,
            metadata: metadata
        )
    }

    func stream(job request: SceneJobRequest) -> AsyncThrowingStream<AITextStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let snapshot = await snapshot(for: request)
                    guard let snapshot else {
                        throw AIServiceError.relayConfigurationMissing
                    }

                    let endpoint = snapshot.endpoint(for: "/chat/completions")
                    guard let url = URL(string: endpoint) else {
                        throw AIServiceError.invalidRequest
                    }

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.setValue("Bearer \(snapshot.apiKey)", forHTTPHeaderField: "Authorization")

                    let body = RelayChatRequest(
                        model: snapshot.model,
                        messages: [.init(role: "user", content: makeCombinedPrompt(for: request, model: snapshot.model))],
                        temperature: 0.85,
                        stream: true
                    )
                    urlRequest.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIServiceError.transportFailure(underlying: URLError(.badServerResponse))
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        let raw = try await bytes.reduce(into: Data()) { $0.append($1) }
                        let bodyText = String(data: raw, encoding: .utf8) ?? "<binary>"
                        print("[RelayTextService] HTTP \(httpResponse.statusCode) error body: \(bodyText)")
                        if let relayError = try? JSONDecoder().decode(RelayAPIError.self, from: raw) {
                            throw AIServiceError.serverRejected(reason: relayError.error.message)
                        }
                        throw AIServiceError.serverRejected(reason: "HTTP \(httpResponse.statusCode)")
                    }

                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                        print("[RelayTextService][stream raw] \(payload)")
                        if payload == "[DONE]" {
                            break
                        }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? decoder.decode(RelayChatStreamChunk.self, from: data) else {
                            continue
                        }
                        if let text = chunk.deltaText, text.isEmpty == false {
                            continuation.yield(
                                AITextStreamChunk(
                                    textDelta: text,
                                    modelIdentifier: chunk.model,
                                    isTerminal: false
                                )
                            )
                        }
                        if chunk.isFinished {
                            continuation.yield(
                                AITextStreamChunk(
                                    textDelta: "",
                                    modelIdentifier: chunk.model,
                                    isTerminal: true
                                )
                            )
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func snapshot(for request: SceneJobRequest) async -> RelaySettingsSnapshot? {
        await MainActor.run {
            let override = request.fields[modelOverrideField]
            return configuration.relayTextSettingsSnapshot(preferredModel: override)
        }
    }

    private func makeCombinedPrompt(for request: SceneJobRequest, model: String) -> String {
        let systemPrompt = request.fields["systemPrompt"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredFields = request.fields.filter { key, _ in
            key != "systemPrompt" && key != modelOverrideField
        }
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

    private func logRawResponse(_ data: Data) {
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
           let text = String(data: pretty, encoding: .utf8) {
            print("[RelayTextService] Raw response JSON:\n\(text)")
            return
        }
        if let raw = String(data: data, encoding: .utf8) {
            print("[RelayTextService] Raw response: \(raw)")
        } else {
            print("[RelayTextService] Raw response: <binary \(data.count) bytes>")
        }
    }

    private static func parseImageURL(_ urlString: String?) -> (url: URL?, base64: String?) {
        guard let urlString, urlString.isEmpty == false else { return (nil, nil) }
        if urlString.hasPrefix("data:image"),
           let commaIndex = urlString.firstIndex(of: ",") {
            let base64Part = String(urlString[urlString.index(after: commaIndex)...])
            let dataURL = URL(string: urlString)
            return (dataURL, base64Part)
        }
        return (URL(string: urlString), nil)
    }
}

private struct RelayChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let stream: Bool?
}

private struct RelayChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
            let images: [ImagePayload]?
        }
        let message: Message
    }
    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
        let promptTokensDetails: [String: Int]?
        let completionTokensDetails: [String: Int]?
        let cachedTokens: Int?
    }
    let choices: [Choice]
    let usage: Usage?
}

private struct ImagePayload: Decodable {
    struct ImageURL: Decodable {
        let url: String?
    }
    let type: String?
    let index: Int?
    let imageURL: ImageURL?
}

private struct RelayChatStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            struct Fragment: Decodable {
                let text: String?
            }

            let content: String?
            let contentParts: [Fragment]?
        }

        let delta: Delta?
        let finishReason: String?

        var deltaText: String? {
            if let content = delta?.content {
                return content
            }
            if let fragments = delta?.contentParts {
                return fragments.compactMap { $0.text }.joined()
            }
            return nil
        }
    }

    let choices: [Choice]
    let model: String?

    var deltaText: String? { choices.first?.deltaText }
    var isFinished: Bool { choices.first?.finishReason != nil }
}
