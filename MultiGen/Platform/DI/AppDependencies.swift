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
    let auditRepository: AuditRepositoryProtocol
    private let relayTextService: AITextServiceProtocol
    private let relayImageService: AIImageServiceProtocol
    private let relayVideoService: RelayVideoService

    init(
        configuration: AppConfiguration,
        auditRepository: AuditRepositoryProtocol,
        relayTextService: AITextServiceProtocol,
        relayImageService: AIImageServiceProtocol,
        relayVideoService: RelayVideoService
    ) {
        self.configuration = configuration
        self.auditRepository = auditRepository
        self.relayTextService = relayTextService
        self.relayImageService = relayImageService
        self.relayVideoService = relayVideoService
    }

    func textService() -> AITextServiceProtocol {
        relayTextService
    }

    func imageService() -> AIImageServiceProtocol {
        relayImageService
    }

    func videoService() -> RelayVideoService {
        relayVideoService
    }

    func currentTextRoute() -> AIRoute { .relay }
    func currentImageRoute() -> AIRoute { .relay }
    func currentVideoRoute() -> AIRoute { .relay }

    func currentTextModelLabel() -> String {
        configuration.relaySelectedTextModel ?? "未配置模型"
    }

    func currentImageModelLabel() -> String {
        configuration.relaySelectedImageModel ?? "未配置模型"
    }

    func currentVideoModelLabel() -> String {
        configuration.relaySelectedVideoModel ?? "未配置模型"
    }

    func currentMultimodalModelLabel() -> String {
        configuration.relaySelectedMultimodalModel ?? configuration.relaySelectedTextModel ?? "未配置模型"
    }
}

extension AppDependencies {
    static func live() -> AppDependencies {
        let configuration = AppConfiguration()
        let auditRepository = FileAuditRepository()
        let relayService = RelayTextService(configuration: configuration)
        let relayImageService = RelayImageService(configuration: configuration)
        let relayVideoService = RelayVideoService(configuration: configuration)

        return AppDependencies(
            configuration: configuration,
            auditRepository: auditRepository,
            relayTextService: relayService,
            relayImageService: relayImageService,
            relayVideoService: relayVideoService
        )
    }

    static func preview() -> AppDependencies {
        let defaults = UserDefaults(suiteName: "preview.multigen.\(UUID().uuidString)")!
        let configuration = AppConfiguration(defaults: defaults)
        let auditRepository = MemoryAuditRepository()
        let relayService = RelayTextService(configuration: configuration)
        let relayImageService = RelayImageService(configuration: configuration)
        let relayVideoService = RelayVideoService(configuration: configuration)

        return AppDependencies(
            configuration: configuration,
            auditRepository: auditRepository,
            relayTextService: relayService,
            relayImageService: relayImageService,
            relayVideoService: relayVideoService
        )
    }
}
