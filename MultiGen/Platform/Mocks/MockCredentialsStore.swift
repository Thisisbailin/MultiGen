//
//  MockCredentialsStore.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

public final class MockCredentialsStore: CredentialsStoreProtocol {
    private var apiKey: String?

    public init(initialKey: String? = "mock-demo-key") {
        self.apiKey = initialKey
    }

    public func fetchAPIKey() throws -> String {
        guard let apiKey else { throw CredentialsStoreError.notFound }
        return apiKey
    }

    public func save(apiKey: String) throws {
        self.apiKey = apiKey
    }

    public func clear() throws {
        apiKey = nil
    }
}
