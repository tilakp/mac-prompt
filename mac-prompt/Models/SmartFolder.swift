//
//  SmartFolder.swift
//  mac-prompt
//

import Foundation

/// Built-in sidebar sections shown above user-created folders. Not persisted —
/// membership is computed from `Script` properties at query time.
enum SmartFolder: String, CaseIterable, Identifiable {
    case library = "Library"
    case recent = "Recent"
    case favorites = "Favorites"
    case trash = "Trash"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .library: return "square.grid.2x2"
        case .recent: return "clock"
        case .favorites: return "star"
        case .trash: return "trash"
        }
    }
}

/// What the Library's detail area is currently showing.
enum LibrarySelection: Hashable {
    case smart(SmartFolder)
    case folder(UUID)
}
