//
//  MockImageService.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

public final class MockImageService: GeminiImageServiceProtocol {
    public init() {}

    public func generateImage(for request: SceneJobRequest) async throws -> SceneJobResult {
        try await Task.sleep(nanoseconds: 50_000_000)
        let placeholder = Data("mock-image-\(request.id.uuidString.prefix(8))".utf8).base64EncodedString()
        let metadata = SceneJobResult.Metadata(
            prompt: "Mock image for \(request.action.displayName)",
            model: "Mock Image Service",
            duration: 0.05
        )
        return SceneJobResult(imageURL: nil, imageBase64: placeholder, metadata: metadata)
    }
}
