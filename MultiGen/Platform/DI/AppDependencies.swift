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

    init(
        configuration: AppConfiguration,
        credentialsStore: CredentialsStoreProtocol,
        auditRepository: AuditRepositoryProtocol,
        primaryTextService: GeminiTextServiceProtocol,
        primaryImageService: GeminiImageServiceProtocol,
        relayTextService: GeminiTextServiceProtocol
    ) {
        self.configuration = configuration
        self.credentialsStore = credentialsStore
        self.auditRepository = auditRepository
        self.primaryTextService = primaryTextService
        self.primaryImageService = primaryImageService
        self.relayTextService = relayTextService
    }

    func textService() -> GeminiTextServiceProtocol {
        if configuration.relayEnabled { return relayTextService }
        return primaryTextService
    }

    func imageService() -> GeminiImageServiceProtocol {
        primaryImageService
    }
}

extension AppDependencies {
    static func live() -> AppDependencies {
        let configuration = AppConfiguration()
        let credentialsStore = KeychainCredentialsStore()
        let auditRepository = MemoryAuditRepository()
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

        return AppDependencies(
            configuration: configuration,
            credentialsStore: credentialsStore,
            auditRepository: auditRepository,
            primaryTextService: textService,
            primaryImageService: imageService,
            relayTextService: relayService
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

        return AppDependencies(
            configuration: configuration,
            credentialsStore: credentialsStore,
            auditRepository: auditRepository,
            primaryTextService: mockText,
            primaryImageService: mockImage,
            relayTextService: relayService
        )
    }
}
