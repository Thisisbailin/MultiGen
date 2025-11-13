//
//  MemoryAuditRepository.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

public actor MemoryAuditRepository: AuditRepositoryProtocol {
    private var entries: [AuditLogEntry] = []

    public init(entries: [AuditLogEntry] = []) {
        self.entries = entries
    }

    public func record(_ entry: AuditLogEntry) async {
        entries.append(entry)
        entries.sort { $0.createdAt > $1.createdAt }
    }

    public func fetchRecent(limit: Int) async -> [AuditLogEntry] {
        Array(entries.prefix(limit))
    }

    public func clearAll() async {
        entries.removeAll()
    }
}
