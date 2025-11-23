//
//  AIRoute.swift
//  MultiGen
//
//  Created by Codex on 2025/02/16.
//

enum AIRoute: String {
    case relay

    var displayName: String {
        switch self {
        case .relay: return "中转"
        }
    }
}
