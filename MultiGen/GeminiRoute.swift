//
//  GeminiRoute.swift
//  MultiGen
//
//  Created by Codex on 2025/02/16.
//

enum GeminiRoute: String {
    case official
    case relay

    var displayName: String {
        switch self {
        case .official: return "官网"
        case .relay: return "中转"
        }
    }
}
