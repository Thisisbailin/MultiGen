import Foundation

@MainActor
struct AIChatStreamOutcome {
    let result: AIActionResult?
    let collectedText: String
}

@MainActor
struct AIChatStreamingPipeline {
    let actionCenter: AIActionCenter

    func run(request: AIActionRequest, onPartial: (String) -> Void) async throws -> AIChatStreamOutcome {
        var collected = ""
        var finalResult: AIActionResult?
        let stream = actionCenter.stream(request)
        for try await event in stream {
            switch event {
            case .partial(let chunk):
                collected += chunk
                onPartial(collected)
            case .completed(let result):
                finalResult = result
            }
        }
        return AIChatStreamOutcome(result: finalResult, collectedText: collected)
    }
}
