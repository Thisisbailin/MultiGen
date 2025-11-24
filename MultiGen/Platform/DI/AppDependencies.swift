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

    init(
        configuration: AppConfiguration,
        auditRepository: AuditRepositoryProtocol,
        relayTextService: AITextServiceProtocol
    ) {
        self.configuration = configuration
        self.auditRepository = auditRepository
        self.relayTextService = relayTextService
    }

    func textService() -> AITextServiceProtocol {
        relayTextService
    }

    func currentTextRoute() -> AIRoute { .relay }

    func currentTextModelLabel() -> String {
        configuration.relaySelectedTextModel ?? "未配置模型"
    }
}

extension AppDependencies {
    static func live() -> AppDependencies {
        let configuration = AppConfiguration()
        let auditRepository = FileAuditRepository()
        let relayService = RelayTextService(configuration: configuration)

        return AppDependencies(
            configuration: configuration,
            auditRepository: auditRepository,
            relayTextService: relayService
        )
    }

    static func preview() -> AppDependencies {
        let defaults = UserDefaults(suiteName: "preview.multigen.\(UUID().uuidString)")!
        let configuration = AppConfiguration(defaults: defaults)
        let auditRepository = MemoryAuditRepository()
        let relayService = RelayTextService(configuration: configuration)

        return AppDependencies(
            configuration: configuration,
            auditRepository: auditRepository,
            relayTextService: relayService
        )
    }
}
