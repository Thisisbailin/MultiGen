//
//  NSImage+Base64.swift
//  MultiGen
//
//  Created by Codex on 2025/02/16.
//

import AppKit

extension NSImage {
    convenience init?(base64String: String?) {
        guard
            let base64String,
            let data = Data(base64Encoded: base64String)
        else {
            return nil
        }
        self.init(data: data)
    }
}
