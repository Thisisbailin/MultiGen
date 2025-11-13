//
//  GeminiAPIModels.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

struct GeminiGenerateContentRequest: Encodable {
    struct Content: Encodable {
        struct Part: Encodable {
            let text: String?
        }

        let role: String
        let parts: [Part]

        init(role: String = "user", parts: [Part]) {
            self.role = role
            self.parts = parts
        }
    }

    struct GenerationConfig: Encodable {
        let temperature: Double?
        let topP: Double?
        let topK: Int?
    }

    let contents: [Content]
    let generationConfig: GenerationConfig?

    init(contents: [Content], generationConfig: GenerationConfig? = nil) {
        self.contents = contents
        self.generationConfig = generationConfig
    }
}

struct GeminiGenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }

            let parts: [Part]
        }

        let content: Content?
    }

    let candidates: [Candidate]?
}

struct GeminiErrorResponse: Decodable {
    struct APIError: Decodable {
        let code: Int?
        let message: String
        let status: String?
    }

    let error: APIError
}
