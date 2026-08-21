//
//  Folder.swift
//  mac-prompt
//

import Foundation
import SwiftData

@Model
final class Folder {
    var id: UUID
    var name: String
    var accentIndex: Int
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Script.folder)
    var scripts: [Script] = []

    init(name: String, accentIndex: Int) {
        self.id = UUID()
        self.name = name
        self.accentIndex = accentIndex
        self.createdAt = .now
    }
}
