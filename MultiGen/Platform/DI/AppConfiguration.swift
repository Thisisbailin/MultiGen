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

@MainActor
final class AppConfiguration: ObservableObject {
    private enum Keys {
        static let relayProviderName = "app.configuration.relay.name"
        static let relayAPIBase = "app.configuration.relay.base"
        static let relayAPIKey = "app.configuration.relay.key"
        static let relayModels = "app.configuration.relay.models"
        static let relaySelectedTextModel = "app.configuration.relay.selectedTextModel"
        static let appearance = "app.configuration.appearance"
        static let memoryEnabled = "app.configuration.memoryEnabled"
        static let aiMemoryEnabled = "app.configuration.aiMemoryEnabled"
    }

    private let defaults: UserDefaults

    @Published private(set) var relayProviderName: String
    @Published private(set) var relayAPIBase: String
    @Published private(set) var relayAPIKey: String
    @Published private(set) var relayAvailableModels: [String]
    @Published private(set) var relaySelectedTextModel: String?
    @Published private(set) var appearance: AppAppearance
    @Published private(set) var memoryEnabled: Bool
    @Published private(set) var aiMemoryEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedProviderName = defaults.string(forKey: Keys.relayProviderName) ?? "OpenRouter"
        let storedBase = defaults.string(forKey: Keys.relayAPIBase) ?? ""
        let storedKey = defaults.string(forKey: Keys.relayAPIKey) ?? ""
        let storedModels = defaults.data(forKey: Keys.relayModels)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let storedTextSelected = defaults.string(forKey: Keys.relaySelectedTextModel)
        let storedAppearance = defaults.string(forKey: Keys.appearance)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
        let storedMemoryEnabled = defaults.object(forKey: Keys.memoryEnabled) as? Bool ?? true
        let storedAIMemoryEnabled = defaults.object(forKey: Keys.aiMemoryEnabled) as? Bool ?? false

        _relayProviderName = Published(initialValue: storedProviderName)
        _relayAPIBase = Published(initialValue: storedBase)
        _relayAPIKey = Published(initialValue: storedKey)
        _relayAvailableModels = Published(initialValue: storedModels)
        _relaySelectedTextModel = Published(initialValue: storedTextSelected)
        _appearance = Published(initialValue: storedAppearance)
        _memoryEnabled = Published(initialValue: storedMemoryEnabled)
        _aiMemoryEnabled = Published(initialValue: storedAIMemoryEnabled)
    }

    func updateRelayProvider(name: String) {
        relayProviderName = name
        defaults.set(name, forKey: Keys.relayProviderName)
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

    func updateMemoryEnabled(_ enabled: Bool) {
        memoryEnabled = enabled
        defaults.set(enabled, forKey: Keys.memoryEnabled)
    }

    func updateAIMemoryEnabled(_ enabled: Bool) {
        aiMemoryEnabled = enabled
        defaults.set(enabled, forKey: Keys.aiMemoryEnabled)
    }

    func relayTextSettingsSnapshot(preferredModel: String? = nil) -> RelaySettingsSnapshot? {
        let override = preferredModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (override?.isEmpty == false ? override : relaySelectedTextModel)
        guard let model, model.isEmpty == false else { return nil }
        return makeRelaySnapshot(selectedModel: model)
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
