//
//  CredentialsStore.swift
//  MultiGen
//
//  Created by Codex on 2025/02/14.
//

import Foundation

public enum CredentialsStoreError: Error, LocalizedError {
    case notFound
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case notAvailable
    case invalidEncoding

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "尚未存储 API Key。"
        case .saveFailed(let code):
            return "写入凭证失败（\(code)）。"
        case .deleteFailed(let code):
            return "删除凭证失败（\(code)）。"
        case .notAvailable:
            return "当前环境无法访问 Keychain。"
        case .invalidEncoding:
            return "输入的密钥编码无效。"
        }
    }
}

public protocol CredentialsStoreProtocol: AnyObject {
    func fetchAPIKey() throws -> String
    func save(apiKey: String) throws
    func clear() throws
}
