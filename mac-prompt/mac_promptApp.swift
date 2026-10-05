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
    let sharedModelContainer: ModelContainer
    /// Set when the saved library could not be opened and a temporary one is used.
    let libraryOpenError: String?

    init() {
        AppSettingsDefaults.registerDefaults()
        let schema = Schema([Script.self, Folder.self])
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
            libraryOpenError = nil
        } catch {
            // Do not crash, and do not touch the store file: if the problem is temporary
            // (e.g. a full disk), the saved library opens again at the next launch.
            // LibraryView tells the user that this session's changes are not saved.
            do {
                sharedModelContainer = try ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
            } catch {
                fatalError("Could not create even an in-memory ModelContainer: \(error)")
            }
            libraryOpenError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(libraryOpenError: libraryOpenError)
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
