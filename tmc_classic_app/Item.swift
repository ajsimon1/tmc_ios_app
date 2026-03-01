//
//  Item.swift
//  tmc_classic_app
//
//  Created by Adam Simon on 3/1/26.
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
