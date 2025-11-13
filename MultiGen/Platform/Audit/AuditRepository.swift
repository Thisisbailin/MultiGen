//
//  AuditRepository.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

public protocol AuditRepositoryProtocol: Sendable {
    func record(_ entry: AuditLogEntry) async
    func fetchRecent(limit: Int) async -> [AuditLogEntry]
    func clearAll() async
}
