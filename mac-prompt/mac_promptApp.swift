//
//  mac_promptApp.swift
//  mac-prompt
//

import SwiftData
import SwiftUI

@main
struct mac_promptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            LibraryView(libraryOpenError: appDelegate.libraryOpenError)
                .themed()
        }
        .modelContainer(appDelegate.modelContainer)

        // Opened from EditorView with `openWindow(id: "prompter", value: script.id)`.
        WindowGroup(id: "prompter", for: UUID.self) { $scriptID in
            PrompterView(scriptID: scriptID)
                .themed()
        }
        .modelContainer(appDelegate.modelContainer)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
        }
    }
}

/// Owns what lives as long as the app: the library store, and the work that must
/// finish before the app quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let modelContainer: ModelContainer
    /// Set when the saved library could not be opened and a temporary one is used.
    let libraryOpenError: String?
    private var didReplyToTerminate = false

    override init() {
        AppSettingsDefaults.register()
        let schema = Schema([Script.self, Folder.self])
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
            libraryOpenError = nil
        } catch {
            // Do not crash, and do not touch the store file: if the problem is temporary
            // (e.g. a full disk), the saved library opens again at the next launch.
            // LibraryView tells the user that this session's changes are not saved.
            do {
                modelContainer = try ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
            } catch {
                fatalError("Could not create even an in-memory ModelContainer: \(error)")
            }
            libraryOpenError = error.localizedDescription
        }
        super.init()
    }

    /// A movie file that is not finished loses its end or does not open, so the app
    /// finishes any recording before it quits. The time limit makes sure a recording
    /// that never reports its end cannot stop the app from quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard RecordingController.isAnyRecording else { return .terminateNow }
        didReplyToTerminate = false
        Task {
            await RecordingController.finishAllRecordings()
            replyToTerminate(sender)
        }
        Task {
            try? await Task.sleep(for: .seconds(10))
            replyToTerminate(sender)
        }
        return .terminateLater
    }

    private func replyToTerminate(_ sender: NSApplication) {
        guard !didReplyToTerminate else { return }
        didReplyToTerminate = true
        sender.reply(toApplicationShouldTerminate: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Autosave runs after a delay, so save the last edits now.
        try? modelContainer.mainContext.save()
    }
}
