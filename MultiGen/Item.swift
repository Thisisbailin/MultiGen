//
//  Item.swift
//  MultiGen
//
//  Created by Joe on 2025/11/12.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
