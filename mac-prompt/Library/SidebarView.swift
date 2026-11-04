//
//  SidebarView.swift
//  mac-prompt
//

import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.createdAt) private var folders: [Folder]

    @Binding var selection: LibrarySelection
    var scriptCount: Int
    var onNewScript: () -> Void

    @State private var isPresentingNewFolder = false
    @State private var newFolderName = ""
    @State private var folderToRename: Folder?
    @State private var renameText = ""
    @State private var folderToDelete: Folder?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accent)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.onAccent)
                    )
                Text("Prompt")
                    .font(.heading(16.5))
                    .foregroundStyle(theme.text)
            }
            .padding(.horizontal, 4)

            Button("New Script", systemImage: "plus", action: onNewScript)
                .buttonStyle(GradientButtonStyle())
                .labelStyle(.titleAndIcon)

            VStack(spacing: 2) {
                ForEach(SmartFolder.allCases) { smart in
                    Button {
                        selection = .smart(smart)
                    } label: {
                        Label(smart.rawValue, systemImage: smart.systemImage)
                    }
                    .buttonStyle(NavItemStyle(isActive: selection == .smart(smart)))
                }
            }

            Rectangle().fill(theme.border).frame(height: 1).padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("FOLDERS").panelTitle(size: 10.5)
                    Spacer()
                    Button {
                        isPresentingNewFolder = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(theme.textFaint)
                    }
                    .buttonStyle(.plain)
                    .help("New Folder")
                    .accessibilityLabel("New Folder")
                }
                .padding(.horizontal, 12)

                ForEach(folders) { folder in
                    Button {
                        selection = .folder(folder.id)
                    } label: {
                        Label {
                            Text(folder.name)
                        } icon: {
                            Circle().fill(theme.accent(at: folder.accentIndex)).frame(width: 7, height: 7)
                        }
                    }
                    .buttonStyle(NavItemStyle(isActive: selection == .folder(folder.id)))
                    .contextMenu {
                        Button("Rename…") {
                            renameText = folder.name
                            folderToRename = folder
                        }
                        Button("Delete Folder…", role: .destructive) { folderToDelete = folder }
                    }
                }
            }

            Spacer()

            Text("\(scriptCount) script\(scriptCount == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(theme.textFaint)
                .padding(.horizontal, 4)
        }
        .padding(14)
        .frame(minWidth: 220, idealWidth: 236)
        .background(theme.sidebar)
        .alert("New Folder", isPresented: $isPresentingNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                createFolder()
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { folderToRename != nil },
            set: { if !$0 { folderToRename = nil } }
        )) {
            TextField("Folder name", text: $renameText)
            Button("Rename") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { folderToRename?.name = name }
                folderToRename = nil
            }
            Button("Cancel", role: .cancel) { folderToRename = nil }
        }
        .confirmationDialog(
            "Delete the folder “\(folderToDelete?.name ?? "")”?",
            isPresented: Binding(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderToDelete { deleteFolder(folder) }
                folderToDelete = nil
            }
        } message: {
            Text("The scripts in it are not deleted. They move to No Folder.")
        }
    }

    private func deleteFolder(_ folder: Folder) {
        if selection == .folder(folder.id) { selection = .smart(.library) }
        // The scripts stay, with no folder. The `.nullify` delete rule does the same,
        // but only when the context saves; until then an open editor or card would
        // read the deleted folder, which can stop the app.
        for script in folder.scripts { script.folder = nil }
        modelContext.delete(folder)
        try? modelContext.save()
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let folder = Folder(name: name, accentIndex: folders.count)
        modelContext.insert(folder)
        newFolderName = ""
    }
}
