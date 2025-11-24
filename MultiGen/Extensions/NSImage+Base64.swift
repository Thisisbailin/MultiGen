//
//  NSImage+Base64.swift
//  MultiGen
//
//  Created by Codex on 2025/02/16.
//

import AppKit

extension NSImage {
    convenience init?(base64String: String?) {
        guard var base64String else {
            return nil
        }
        if let commaIndex = base64String.firstIndex(of: ",") {
            base64String = String(base64String[base64String.index(after: commaIndex)...])
        }
        guard let data = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            return nil
        }
        self.init(data: data)
    }
}
