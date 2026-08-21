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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accent)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(red: 0.10, green: 0.06, blue: 0.07))
                    )
                Text("Prompt")
                    .font(.heading(16.5))
                    .foregroundColor(theme.text)
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
                    Text("FOLDERS")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(theme.textFaint)
                    Spacer()
                    Button {
                        isPresentingNewFolder = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(theme.textFaint)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)

                ForEach(folders) { folder in
                    Button {
                        selection = .folder(folder.id)
                    } label: {
                        Label {
                            Text(folder.name)
                        } icon: {
                            Circle().fill(theme.accentPalette[folder.accentIndex % theme.accentPalette.count]).frame(width: 7, height: 7)
                        }
                    }
                    .buttonStyle(NavItemStyle(isActive: selection == .folder(folder.id)))
                }
            }

            Spacer()

            Text("\(scriptCount) script\(scriptCount == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundColor(theme.textFaint)
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
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let folder = Folder(name: name, accentIndex: folders.count)
        modelContext.insert(folder)
        newFolderName = ""
    }
}
