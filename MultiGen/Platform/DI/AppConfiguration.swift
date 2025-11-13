//
//  AppConfiguration.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Combine
import Foundation

public enum RelayProviderType: String, Codable, Sendable {
    case openai
}

@MainActor
final class AppConfiguration: ObservableObject {
    private enum Keys {
        static let textModel = "app.configuration.textModel"
        static let imageModel = "app.configuration.imageModel"
        static let useMock = "app.configuration.useMock"
        static let relayEnabled = "app.configuration.relay.enabled"
        static let relayProviderName = "app.configuration.relay.name"
        static let relayProviderType = "app.configuration.relay.type"
        static let relayAPIBase = "app.configuration.relay.base"
        static let relayAPIKey = "app.configuration.relay.key"
        static let relayModels = "app.configuration.relay.models"
        static let relaySelectedModel = "app.configuration.relay.selectedModel"
    }

    private let defaults: UserDefaults

    @Published private(set) var textModel: GeminiModel
    @Published private(set) var imageModel: GeminiModel
    @Published private(set) var useMock: Bool

    @Published private(set) var relayEnabled: Bool
    @Published private(set) var relayProviderName: String
    @Published private(set) var relayProviderType: RelayProviderType
    @Published private(set) var relayAPIBase: String
    @Published private(set) var relayAPIKey: String
    @Published private(set) var relayAvailableModels: [String]
    @Published private(set) var relaySelectedModel: String?

    init(
        defaults: UserDefaults = .standard,
        initialTextModel: GeminiModel? = nil,
        initialImageModel: GeminiModel? = nil,
        initialUseMock: Bool? = nil
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

        let storedUseMock = initialUseMock
            ?? defaults.object(forKey: Keys.useMock) as? Bool
            ?? true

        let storedRelayEnabled = defaults.object(forKey: Keys.relayEnabled) as? Bool ?? false
        let storedProviderName = defaults.string(forKey: Keys.relayProviderName) ?? ""
        let storedProviderType = defaults.string(forKey: Keys.relayProviderType)
            .flatMap(RelayProviderType.init(rawValue:)) ?? .openai
        let storedBase = defaults.string(forKey: Keys.relayAPIBase) ?? ""
        let storedKey = defaults.string(forKey: Keys.relayAPIKey) ?? ""
        let storedModels = defaults.data(forKey: Keys.relayModels)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let storedSelected = defaults.string(forKey: Keys.relaySelectedModel)

        _textModel = Published(initialValue: storedText)
        _imageModel = Published(initialValue: storedImage)
        _useMock = Published(initialValue: storedUseMock)
        _relayEnabled = Published(initialValue: storedRelayEnabled)
        _relayProviderName = Published(initialValue: storedProviderName)
        _relayProviderType = Published(initialValue: storedProviderType)
        _relayAPIBase = Published(initialValue: storedBase)
        _relayAPIKey = Published(initialValue: storedKey)
        _relayAvailableModels = Published(initialValue: storedModels)
        _relaySelectedModel = Published(initialValue: storedSelected)
    }

    func updateTextModel(_ model: GeminiModel) {
        textModel = model
        defaults.set(model.rawValue, forKey: Keys.textModel)
    }

    func updateImageModel(_ model: GeminiModel) {
        imageModel = model
        defaults.set(model.rawValue, forKey: Keys.imageModel)
    }

    func updateUseMock(_ flag: Bool) {
        useMock = flag
        defaults.set(flag, forKey: Keys.useMock)
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

    func updateRelayModels(_ models: [String], selected: String?) {
        relayAvailableModels = models
        relaySelectedModel = selected
        if let data = try? JSONEncoder().encode(models) {
            defaults.set(data, forKey: Keys.relayModels)
        }
        defaults.set(selected, forKey: Keys.relaySelectedModel)
    }

    func updateRelaySelectedModel(_ model: String?) {
        relaySelectedModel = model
        defaults.set(model, forKey: Keys.relaySelectedModel)
    }
}
