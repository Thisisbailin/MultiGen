//
//  GeminiModel.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

public enum GeminiModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case flash25 = "gemini-2.5-flash"
    case flash25Pro = "gemini-2.5-pro"
    case flash20 = "gemini-2.0-flash"
    case flash25ImagePreview = "gemini-2.5-flash-image-preview"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .flash25:
            return "Gemini 2.5 Flash"
        case .flash25Pro:
            return "Gemini 2.5 Pro"
        case .flash20:
            return "Gemini 2.0 Flash"
        case .flash25ImagePreview:
            return "Gemini 2.5 Flash Image Preview"
        }
    }

    public static var textOptions: [GeminiModel] { [.flash20, .flash25, .flash25Pro] }
    public static var imageOptions: [GeminiModel] { [.flash25ImagePreview] }

    public static var defaultTextModel: GeminiModel { .flash25 }
    public static var defaultImageModel: GeminiModel { .flash25ImagePreview }
}
