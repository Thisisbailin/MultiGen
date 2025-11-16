//
//  RelayAPIModels.swift
//  MultiGen
//
//  Created by Codex on 2025/02/16.
//

import Foundation

struct RelayAPIError: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
