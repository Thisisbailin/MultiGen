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
    private let imageURLField = "image_url"
    private let imageBase64Field = "image_base64"
    private let imageMimeField = "image_mime"
    private let openAIContentField = "openai_content"

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

        let body = RelayChatRequest(
            model: snapshot.model,
            messages: makeMessages(for: request, model: snapshot.model),
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
              let message = result.choices.first?.message else {
            throw AIServiceError.decodingFailed
        }
        let text = message.contentText

        if let usage = result.usage {
            print("[RelayTextService] Usage -> prompt: \(usage.promptTokens ?? 0), completion: \(usage.completionTokens ?? 0), total: \(usage.totalTokens ?? 0)")
        }

        let primaryURL = message.firstImageURL
        var parsedImage = Self.parseImageURL(primaryURL)
        // Fallback: 直接解析原始 JSON 中的 images 数组（与 GenMe 相同逻辑）
        if parsedImage.url == nil && parsedImage.base64 == nil,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let msg = first["message"] as? [String: Any],
           let images = msg["images"] as? [[String: Any]],
           let imgObj = images.first,
           let imgURLObj = imgObj["image_url"] as? [String: Any],
           let urlString = imgURLObj["url"] as? String {
            parsedImage = Self.parseImageURL(urlString)
        }

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
                        messages: makeMessages(for: request, model: snapshot.model),
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

    private func makeMessages(for request: SceneJobRequest, model: String) -> [RelayChatRequest.Message] {
        var messages: [RelayChatRequest.Message] = []
        if let systemPrompt = request.fields["systemPrompt"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           systemPrompt.isEmpty == false {
            messages.append(.system(systemPrompt))
        }
        let contentParts = makeContentParts(for: request, model: model)
        messages.append(.user(contentParts))
        return messages
    }

    private func makeContentParts(for request: SceneJobRequest, model: String) -> [RelayChatRequest.Message.Content] {
        if let openAIContent = request.fields[openAIContentField],
           let parsed = parseOpenAIContent(openAIContent) {
            return parsed
        }
        var parts: [RelayChatRequest.Message.Content] = [
            .text(makeCombinedPrompt(for: request, model: model))
        ]
        if let imageURL = preferredImageURL(from: request.fields) {
            parts.append(.imageURL(imageURL))
        }
        return parts
    }

    private func parseOpenAIContent(_ jsonText: String) -> [RelayChatRequest.Message.Content]? {
        guard let data = jsonText.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        var parts: [RelayChatRequest.Message.Content] = []
        for item in array {
            guard let type = item["type"] as? String else { continue }
            if type == "text", let text = item["text"] as? String {
                parts.append(.text(text))
            } else if type == "image_url",
                      let imageURL = (item["image_url"] as? [String: Any])?["url"] as? String {
                parts.append(.imageURL(imageURL))
            }
        }
        return parts.isEmpty ? nil : parts
    }

    private func preferredImageURL(from fields: [String: String]) -> String? {
        if let inline = fields[imageURLField], inline.isEmpty == false {
            return inline
        }
        if let base64 = fields[imageBase64Field], base64.isEmpty == false {
            let mime = fields[imageMimeField] ?? "image/jpeg"
            return "data:\(mime);base64,\(base64)"
        }
        return nil
    }

    private func makeCombinedPrompt(for request: SceneJobRequest, model: String) -> String {
        let filteredFields = request.fields.filter { key, _ in
            key != "systemPrompt"
            && key != modelOverrideField
            && key != imageURLField
            && key != imageBase64Field
            && key != imageMimeField
            && key != openAIContentField
        }
        return promptBody(action: request.action, fields: filteredFields, assetRefs: request.assetReferences)
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
        let content: [Content]

        init(role: String, content: [Content]) {
            self.role = role
            self.content = content
        }

        static func system(_ text: String) -> Message {
            Message(role: "system", content: [.text(text)])
        }

        static func user(_ content: [Content]) -> Message {
            Message(role: "user", content: content)
        }

        enum Content: Encodable {
            case text(String)
            case imageURL(String)

            enum CodingKeys: String, CodingKey {
                case type
                case text
                case imageURL = "image_url"
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let text):
                    try container.encode("text", forKey: .type)
                    try container.encode(text, forKey: .text)
                case .imageURL(let url):
                    try container.encode("image_url", forKey: .type)
                    try container.encode(ImageURL(url: url), forKey: .imageURL)
                }
            }
        }

        struct ImageURL: Encodable {
            let url: String
        }
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let stream: Bool?
}

private struct RelayChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let contentText: String
            let explicitImages: [ImagePayload]?
            let contentImages: [ImagePayload]

            var firstImageURL: String? {
                (explicitImages ?? []).first?.imageURL?.url ?? contentImages.first?.imageURL?.url
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)

                // content 既可能是字符串，也可能是数组（text/image_url 混合）
                if let text = try? container.decode(String.self, forKey: .content) {
                    contentText = text
                    contentImages = []
                } else if let parts = try? container.decode([ContentPart].self, forKey: .content) {
                    contentText = parts.compactMap { $0.text }.joined()
                    contentImages = parts.compactMap { $0.imagePayload }
                } else {
                    contentText = ""
                    contentImages = []
                }

                explicitImages = try? container.decodeIfPresent([ImagePayload].self, forKey: .images)
            }

            enum CodingKeys: String, CodingKey {
                case content
                case images
            }
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

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let string = try? single.decode(String.self) {
                url = string
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decodeIfPresent(String.self, forKey: .url)
        }

        private enum CodingKeys: String, CodingKey {
            case url
        }
    }
    let type: String?
    let index: Int?
    let imageURL: ImageURL?

    enum CodingKeys: String, CodingKey {
        case type
        case index
        case imageURL = "image_url"
    }
}

private struct ContentPart: Decodable {
    let type: String?
    let text: String?
    let imageURL: ImagePayload.ImageURL?

    var imagePayload: ImagePayload? {
        guard let imageURL else { return nil }
        return ImagePayload(type: type, index: nil, imageURL: imageURL)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
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
