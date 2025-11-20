//
//  AppConfiguration.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Combine
import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public enum RelayProviderType: String, Codable, Sendable {
    case openai
}

@MainActor
final class AppConfiguration: ObservableObject {
    private enum Keys {
        static let textModel = "app.configuration.textModel"
        static let imageModel = "app.configuration.imageModel"
        static let relayEnabled = "app.configuration.relay.enabled"
        static let relayProviderName = "app.configuration.relay.name"
        static let relayProviderType = "app.configuration.relay.type"
        static let relayAPIBase = "app.configuration.relay.base"
        static let relayAPIKey = "app.configuration.relay.key"
        static let relayModels = "app.configuration.relay.models"
        static let relaySelectedTextModel = "app.configuration.relay.selectedTextModel"
        static let relaySelectedImageModel = "app.configuration.relay.selectedImageModel"
        static let appearance = "app.configuration.appearance"
        static let memoryEnabled = "app.configuration.memoryEnabled"
        static let aiMemoryEnabled = "app.configuration.aiMemoryEnabled"
    }

    private let defaults: UserDefaults

    @Published private(set) var textModel: GeminiModel
    @Published private(set) var imageModel: GeminiModel

    @Published private(set) var relayEnabled: Bool
    @Published private(set) var relayProviderName: String
    @Published private(set) var relayProviderType: RelayProviderType
    @Published private(set) var relayAPIBase: String
    @Published private(set) var relayAPIKey: String
    @Published private(set) var relayAvailableModels: [String]
    @Published private(set) var relaySelectedTextModel: String?
    @Published private(set) var relaySelectedImageModel: String?
    @Published private(set) var appearance: AppAppearance
    @Published private(set) var memoryEnabled: Bool
    @Published private(set) var aiMemoryEnabled: Bool

    init(
        defaults: UserDefaults = .standard,
        initialTextModel: GeminiModel? = nil,
        initialImageModel: GeminiModel? = nil
    ) {
        self.defaults = defaults

        let storedText = initialTextModel
            ?? defaults.string(forKey: Keys.textModel)
                .flatMap(GeminiModel.init(rawValue:))
            ?? GeminiModel.defaultTextModel

        let storedImage = initialImageModel
            ?? defaults.string(forKey: Keys.imageModel)
                .flatMap(GeminiModel.init(rawValue:))
            ?? GeminiModel.defaultImageModel

        let storedRelayEnabled = defaults.object(forKey: Keys.relayEnabled) as? Bool ?? false
        let storedProviderName = defaults.string(forKey: Keys.relayProviderName) ?? ""
        let storedProviderType = defaults.string(forKey: Keys.relayProviderType)
            .flatMap(RelayProviderType.init(rawValue:)) ?? .openai
        let storedBase = defaults.string(forKey: Keys.relayAPIBase) ?? ""
        let storedKey = defaults.string(forKey: Keys.relayAPIKey) ?? ""
        let storedModels = defaults.data(forKey: Keys.relayModels)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let storedTextSelected = defaults.string(forKey: Keys.relaySelectedTextModel)
        let storedImageSelected = defaults.string(forKey: Keys.relaySelectedImageModel)
        let storedAppearance = defaults.string(forKey: Keys.appearance)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
        defaults.set(true, forKey: Keys.memoryEnabled)
        let storedMemoryEnabled = true
        let storedAIMemoryEnabled = defaults.object(forKey: Keys.aiMemoryEnabled) as? Bool ?? false

        _textModel = Published(initialValue: storedText)
        _imageModel = Published(initialValue: storedImage)
        _relayEnabled = Published(initialValue: storedRelayEnabled)
        _relayProviderName = Published(initialValue: storedProviderName)
        _relayProviderType = Published(initialValue: storedProviderType)
        _relayAPIBase = Published(initialValue: storedBase)
        _relayAPIKey = Published(initialValue: storedKey)
        _relayAvailableModels = Published(initialValue: storedModels)
        _relaySelectedTextModel = Published(initialValue: storedTextSelected)
        _relaySelectedImageModel = Published(initialValue: storedImageSelected)
        _appearance = Published(initialValue: storedAppearance)
        _memoryEnabled = Published(initialValue: storedMemoryEnabled)
        _aiMemoryEnabled = Published(initialValue: storedAIMemoryEnabled)
    }

    func updateTextModel(_ model: GeminiModel) {
        textModel = model
        defaults.set(model.rawValue, forKey: Keys.textModel)
    }

    func updateImageModel(_ model: GeminiModel) {
        imageModel = model
        defaults.set(model.rawValue, forKey: Keys.imageModel)
    }

    func updateRelayEnabled(_ enabled: Bool) {
        relayEnabled = enabled
        defaults.set(enabled, forKey: Keys.relayEnabled)
    }

    func updateRelayProvider(name: String, type: RelayProviderType = .openai) {
        relayProviderName = name
        relayProviderType = type
        defaults.set(name, forKey: Keys.relayProviderName)
        defaults.set(type.rawValue, forKey: Keys.relayProviderType)
    }

    func updateRelayEndpoint(baseURL: String, apiKey: String) {
        relayAPIBase = baseURL
        relayAPIKey = apiKey
        defaults.set(baseURL, forKey: Keys.relayAPIBase)
        defaults.set(apiKey, forKey: Keys.relayAPIKey)
    }

    func updateRelayModels(_ models: [String]) {
        relayAvailableModels = models
        if let data = try? JSONEncoder().encode(models) {
            defaults.set(data, forKey: Keys.relayModels)
        }
    }

    func updateRelaySelectedTextModel(_ model: String?) {
        relaySelectedTextModel = model
        defaults.set(model, forKey: Keys.relaySelectedTextModel)
    }

    func updateRelaySelectedImageModel(_ model: String?) {
        relaySelectedImageModel = model
        defaults.set(model, forKey: Keys.relaySelectedImageModel)
    }

    func updateMemoryEnabled(_ enabled: Bool) {
        memoryEnabled = enabled
        defaults.set(enabled, forKey: Keys.memoryEnabled)
    }

    func updateAIMemoryEnabled(_ enabled: Bool) {
        aiMemoryEnabled = enabled
        defaults.set(enabled, forKey: Keys.aiMemoryEnabled)
    }

    func relayTextSettingsSnapshot() -> RelaySettingsSnapshot? {
        guard relayEnabled,
              relayProviderType == .openai,
              let selected = relaySelectedTextModel,
              selected.isEmpty == false else { return nil }
        return makeRelaySnapshot(selectedModel: selected)
    }

    func relayImageSettingsSnapshot() -> RelaySettingsSnapshot? {
        guard relayEnabled,
              relayProviderType == .openai,
              let selected = relaySelectedImageModel,
              selected.isEmpty == false else { return nil }
        return makeRelaySnapshot(selectedModel: selected)
    }

    private func makeRelaySnapshot(selectedModel: String) -> RelaySettingsSnapshot? {
        let base = relayAPIBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = relayAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard base.isEmpty == false, key.isEmpty == false else { return nil }
        return RelaySettingsSnapshot(baseURL: base, apiKey: key, model: selectedModel)
    }

    func updateAppearance(_ appearance: AppAppearance) {
        self.appearance = appearance
        defaults.set(appearance.rawValue, forKey: Keys.appearance)
    }
}
