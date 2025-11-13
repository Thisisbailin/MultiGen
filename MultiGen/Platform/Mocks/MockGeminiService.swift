//
//  MockGeminiService.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

public final class MockGeminiService: GeminiTextServiceProtocol, @unchecked Sendable {
    public var simulatedDelay: TimeInterval
    public var modelIdentifier: String

    public init(simulatedDelay: TimeInterval = 1.2, modelIdentifier: String = "gemini-1.5-flash-mock") {
        self.simulatedDelay = simulatedDelay
        self.modelIdentifier = modelIdentifier
    }

    public func submit(job request: SceneJobRequest) async throws -> SceneJobResult {
        try await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))

        if let formatHint = request.fields["responseFormat"],
           formatHint.contains("JSON"),
           request.channel == .text {
            let json = StoryboardResponseParser.sampleJSON(
                seed: request.id,
                count: 2,
                startingShot: (request.fields["existingEntries"]?.isEmpty == false) ? 3 : 1
            )
            let metadata = SceneJobResult.Metadata(
                prompt: json,
                model: modelIdentifier,
                duration: simulatedDelay
            )
            return SceneJobResult(imageURL: nil, metadata: metadata)
        }

        let promptSummary = request.fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: " | ")

        let metadata = SceneJobResult.Metadata(
            prompt: "[\(request.action.displayName)] \(promptSummary)",
            model: modelIdentifier,
            duration: simulatedDelay
        )

        return SceneJobResult(imageURL: nil, metadata: metadata)
    }
}
