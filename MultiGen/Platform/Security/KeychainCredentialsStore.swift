//
//  KeychainCredentialsStore.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation
import Security

public final class KeychainCredentialsStore: CredentialsStoreProtocol {
    private let service = "com.joe.MultiGen.gemini"
    private let account = "gemini-api-key"

    public init() {}

    public func fetchAPIKey() throws -> String {
        var query: [String: Any] = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else { throw CredentialsStoreError.notFound }
        guard status == errSecSuccess else { throw CredentialsStoreError.saveFailed(status) }

        guard
            let data = item as? Data,
            let key = String(data: data, encoding: .utf8)
        else {
            throw CredentialsStoreError.notAvailable
        }

        return key
    }

    public func save(apiKey: String) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw CredentialsStoreError.invalidEncoding
        }

        var query = baseQuery()
        query[kSecValueData as String] = data

        let status: OSStatus
        if (try? fetchAPIKey()) != nil {
            let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
            status = SecItemUpdate(baseQuery() as CFDictionary, attributesToUpdate as CFDictionary)
        } else {
            status = SecItemAdd(query as CFDictionary, nil)
        }

        guard status == errSecSuccess else { throw CredentialsStoreError.saveFailed(status) }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialsStoreError.deleteFailed(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
    }
}
