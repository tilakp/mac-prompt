//
//  mac_promptApp.swift
//  mac-prompt
//
//  Created by Patel, Tilak on 4/17/25.
//

import SwiftData
import SwiftUI

@main
struct mac_promptApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([Script.self, Folder.self])
        let configuration = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        AppSettingsDefaults.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .themed()
        }
        .modelContainer(sharedModelContainer)

        // Opened from EditorView via `openWindow(id: "prompter", value: script.id)`.
        WindowGroup(id: "prompter", for: UUID.self) { $scriptID in
            PrompterView(scriptID: scriptID)
                .themed()
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
        }
    }
}
