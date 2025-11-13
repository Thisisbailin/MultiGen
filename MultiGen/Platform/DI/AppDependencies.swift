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
    let mockTextService: MockGeminiService
    let mockImageService: MockImageService
    let geminiTextService: GeminiTextService
    let geminiImageService: GeminiImageService
    let relayTextService: RelayTextService

    init(
        configuration: AppConfiguration,
        credentialsStore: CredentialsStoreProtocol,
        auditRepository: AuditRepositoryProtocol,
        mockTextService: MockGeminiService,
        mockImageService: MockImageService,
        geminiTextService: GeminiTextService,
        geminiImageService: GeminiImageService,
        relayTextService: RelayTextService
    ) {
        self.configuration = configuration
        self.credentialsStore = credentialsStore
        self.auditRepository = auditRepository
        self.mockTextService = mockTextService
        self.mockImageService = mockImageService
        self.geminiTextService = geminiTextService
        self.geminiImageService = geminiImageService
        self.relayTextService = relayTextService
    }

    func textService() -> GeminiTextServiceProtocol {
        if configuration.useMock { return mockTextService }
        if configuration.relayEnabled { return relayTextService }
        return geminiTextService
    }

    func imageService() -> GeminiImageServiceProtocol {
        configuration.useMock ? mockImageService : geminiImageService
    }
}

extension AppDependencies {
    static func live() -> AppDependencies {
        let configuration = AppConfiguration()
        let credentialsStore = KeychainCredentialsStore()
        let auditRepository = MemoryAuditRepository()
        let mockText = MockGeminiService()
        let mockImage = MockImageService()
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
            mockTextService: mockText,
            mockImageService: mockImage,
            geminiTextService: textService,
            geminiImageService: imageService,
            relayTextService: relayService
        )
    }

    static func preview() -> AppDependencies {
        let defaults = UserDefaults(suiteName: "preview.multigen.\(UUID().uuidString)")!
        let configuration = AppConfiguration(
            defaults: defaults,
            initialTextModel: .flash25,
            initialImageModel: .flash25ImagePreview,
            initialUseMock: true
        )
        let credentialsStore = MockCredentialsStore()
        let auditRepository = MemoryAuditRepository()
        let mockText = MockGeminiService(simulatedDelay: 0.3)
        let mockImage = MockImageService()
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
            mockTextService: mockText,
            mockImageService: mockImage,
            geminiTextService: textService,
            geminiImageService: imageService,
            relayTextService: relayService
        )
    }
}
