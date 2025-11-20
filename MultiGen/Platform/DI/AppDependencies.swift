//
//  AppDependencies.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Combine
import Foundation

@MainActor
final class AppDependencies: ObservableObject {
    let configuration: AppConfiguration
    let credentialsStore: CredentialsStoreProtocol
    let auditRepository: AuditRepositoryProtocol
    private let primaryTextService: GeminiTextServiceProtocol
    private let primaryImageService: GeminiImageServiceProtocol
    private let relayTextService: GeminiTextServiceProtocol
    private let relayImageService: GeminiImageServiceProtocol

    init(
        configuration: AppConfiguration,
        credentialsStore: CredentialsStoreProtocol,
        auditRepository: AuditRepositoryProtocol,
        primaryTextService: GeminiTextServiceProtocol,
        primaryImageService: GeminiImageServiceProtocol,
        relayTextService: GeminiTextServiceProtocol,
        relayImageService: GeminiImageServiceProtocol
    ) {
        self.configuration = configuration
        self.credentialsStore = credentialsStore
        self.auditRepository = auditRepository
        self.primaryTextService = primaryTextService
        self.primaryImageService = primaryImageService
        self.relayTextService = relayTextService
        self.relayImageService = relayImageService
    }

    func textService() -> GeminiTextServiceProtocol {
        if configuration.relayTextSettingsSnapshot() != nil { return relayTextService }
        return primaryTextService
    }

    func imageService() -> GeminiImageServiceProtocol {
        if configuration.relayImageSettingsSnapshot() != nil { return relayImageService }
        return primaryImageService
    }

    func currentTextRoute() -> GeminiRoute {
        configuration.relayTextSettingsSnapshot() != nil ? .relay : .official
    }

    func currentImageRoute() -> GeminiRoute {
        configuration.relayImageSettingsSnapshot() != nil ? .relay : .official
    }

    func currentTextModelLabel() -> String {
        switch currentTextRoute() {
        case .relay:
            return configuration.relayTextSettingsSnapshot()?.model ?? "未配置中转模型"
        case .official:
            return configuration.textModel.displayName
        }
    }

    func currentImageModelLabel() -> String {
        switch currentImageRoute() {
        case .relay:
            return configuration.relayImageSettingsSnapshot()?.model ?? "未配置中转模型"
        case .official:
            return configuration.imageModel.displayName
        }
    }
}

extension AppDependencies {
    static func live() -> AppDependencies {
        let configuration = AppConfiguration()
        let credentialsStore = KeychainCredentialsStore()
        let auditRepository = FileAuditRepository()
        let textService = GeminiTextService(
            credentialsStore: credentialsStore,
            modelProvider: { [configuration] in
                await MainActor.run {
                    configuration.textModel
                }
            }
        )
        let imageService = GeminiImageService(
            credentialsStore: credentialsStore,
            modelProvider: { [configuration] in
                await MainActor.run {
                    configuration.imageModel
                }
            }
        )
        let relayService = RelayTextService(configuration: configuration)
        let relayImageService = RelayImageService(configuration: configuration)

        return AppDependencies(
            configuration: configuration,
            credentialsStore: credentialsStore,
            auditRepository: auditRepository,
            primaryTextService: textService,
            primaryImageService: imageService,
            relayTextService: relayService,
            relayImageService: relayImageService
        )
    }

    static func preview() -> AppDependencies {
        let defaults = UserDefaults(suiteName: "preview.multigen.\(UUID().uuidString)")!
        let configuration = AppConfiguration(
            defaults: defaults,
            initialTextModel: .flash25,
            initialImageModel: .flash25ImagePreview
        )
        let credentialsStore = MockCredentialsStore()
        let auditRepository = MemoryAuditRepository()
        let mockText = MockGeminiService(simulatedDelay: 0.3)
        let mockImage = MockImageService()
        let relayService = RelayTextService(configuration: configuration)
        let relayImageService = RelayImageService(configuration: configuration)

        return AppDependencies(
            configuration: configuration,
            credentialsStore: credentialsStore,
            auditRepository: auditRepository,
            primaryTextService: mockText,
            primaryImageService: mockImage,
            relayTextService: relayService,
            relayImageService: relayImageService
        )
    }
}
