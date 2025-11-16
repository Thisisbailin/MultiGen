//
//  RelaySettingsSnapshot.swift
//  MultiGen
//
//  Created by Codex on 2025/02/16.
//

import Foundation

struct RelaySettingsSnapshot {
    let baseURL: String
    let apiKey: String
    let model: String

    static func normalize(baseURL: String) -> String {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}
