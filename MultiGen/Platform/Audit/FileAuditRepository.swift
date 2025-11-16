//
//  FileAuditRepository.swift
//  MultiGen
//
//  Created by Codex on 2025/02/15.
//

import Foundation

public actor FileAuditRepository: AuditRepositoryProtocol {
    private var entries: [AuditLogEntry]
    private let storageURL: URL

    public init(storageURL: URL = FileAuditRepository.defaultURL()) {
        self.storageURL = storageURL
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([AuditLogEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    public func record(_ entry: AuditLogEntry) async {
        entries.append(entry)
        entries.sort { $0.createdAt > $1.createdAt }
        persist()
    }

    public func fetchRecent(limit: Int) async -> [AuditLogEntry] {
        Array(entries.prefix(limit))
    }

    public func clearAll() async {
        entries.removeAll()
        persist()
    }

    public func loadAllEntries() async -> [AuditLogEntry] {
        entries
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("FileAuditRepository persist error: \(error)")
        }
    }

    nonisolated public static func defaultURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("MultiGen", isDirectory: true)
            .appendingPathComponent("audit-log.json")
    }
}
