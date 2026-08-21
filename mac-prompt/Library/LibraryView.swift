//
//  LibraryView.swift
//  mac-prompt
//

import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Script.editedAt, order: .reverse) private var allScripts: [Script]
    @Query(sort: \Folder.createdAt) private var folders: [Folder]

    @State private var selection: LibrarySelection = .smart(.library)
    @State private var selectedScript: Script?
    @State private var searchText = ""
    @State private var isGridLayout = true

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, scriptCount: activeScripts.count, onNewScript: createScript)
        } detail: {
            Group {
                if let selectedScript {
                    EditorView(script: selectedScript, onClose: { self.selectedScript = nil })
                } else {
                    libraryGrid
                }
            }
        }
        .background(theme.bg)
    }

    private var libraryGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if visibleScripts.isEmpty {
                emptyState
            } else if isGridLayout {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 18)], spacing: 18) {
                        ForEach(visibleScripts) { script in
                            ScriptCardView(
                                script: script,
                                onOpen: { selectedScript = script },
                                onToggleFavorite: { script.isFavorite.toggle() },
                                onDelete: { delete(script) }
                            )
                        }
                    }
                    .padding(24)
                }
            } else {
                List(visibleScripts) { script in
                    ScriptRow(script: script, onOpen: { selectedScript = script }, onDelete: { delete(script) })
                }
                .listStyle(.inset)
            }
        }
        .background(theme.bg)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.heading(26))
                    .foregroundColor(theme.text)
                Text("\(activeScripts.count) scripts · \(folders.count) folders")
                    .font(.system(size: 13))
                    .foregroundColor(theme.textFaint)
            }
            Spacer()
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(theme.textFaint)
                    TextField("Search scripts…", text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundColor(theme.text)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .frame(width: 240)
                .background(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                layoutToggleButton(systemImage: "square.grid.2x2", isActive: isGridLayout) { isGridLayout = true }
                layoutToggleButton(systemImage: "list.bullet", isActive: !isGridLayout) { isGridLayout = false }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 26)
        .padding(.bottom, 22)
    }

    private func layoutToggleButton(systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 34, height: 34)
                .foregroundColor(isActive ? theme.text : theme.textDim)
                .background(isActive ? theme.text.opacity(0.1) : theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "text.alignleft")
                .font(.system(size: 34))
                .foregroundColor(theme.textFaint)
            Text(searchText.isEmpty ? "No scripts here yet" : "No scripts match “\(searchText)”")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.textDim)
            if searchText.isEmpty {
                Button("New Script", action: createScript)
                    .buttonStyle(GradientButtonStyle())
                    .frame(width: 160)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch selection {
        case .smart(let smart): return smart.rawValue
        case .folder(let id): return folders.first(where: { $0.id == id })?.name ?? "Folder"
        }
    }

    private var activeScripts: [Script] { allScripts.filter { !$0.isTrashed } }

    private var visibleScripts: [Script] {
        let base: [Script]
        switch selection {
        case .smart(.library):
            base = activeScripts
        case .smart(.recent):
            base = Array(activeScripts.prefix(20))
        case .smart(.favorites):
            base = activeScripts.filter(\.isFavorite)
        case .smart(.trash):
            base = allScripts.filter(\.isTrashed)
        case .folder(let id):
            base = activeScripts.filter { $0.folder?.id == id }
        }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) || $0.body.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func createScript() {
        let defaultWPM = UserDefaults.standard.integer(forKey: AppSettingsKey.defaultWPM)
        let folder: Folder? = { if case .folder(let id) = selection { return folders.first(where: { $0.id == id }) } else { return nil } }()
        let script = Script(
            targetWPM: defaultWPM == 0 ? 150 : defaultWPM,
            accentIndex: allScripts.count
        )
        script.folder = folder
        modelContext.insert(script)
        selectedScript = script
    }

    private func delete(_ script: Script) {
        if script.isTrashed {
            modelContext.delete(script)
        } else {
            script.isTrashed = true
        }
        if selectedScript === script { selectedScript = nil }
    }
}

private struct ScriptRow: View {
    @Environment(\.theme) private var theme
    let script: Script
    var onOpen: () -> Void
    var onDelete: () -> Void

    private var accentColor: Color { theme.accentPalette[script.accentIndex % theme.accentPalette.count] }

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(accentColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(script.title).font(.system(size: 13, weight: .semibold)).foregroundColor(theme.text)
                Text(script.snippet).font(.system(size: 11.5)).foregroundColor(theme.textFaint).lineLimit(1)
            }
            Spacer()
            Text("\(script.wordCount) words").font(.system(size: 11)).foregroundColor(theme.textFaint)
            Text(script.estimatedDuration).font(.system(size: 11)).foregroundColor(theme.textFaint)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button(script.isTrashed ? "Delete Permanently" : "Move to Trash", role: .destructive, action: onDelete)
        }
    }
}
