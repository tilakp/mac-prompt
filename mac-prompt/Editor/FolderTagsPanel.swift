//
//  FolderTagsPanel.swift
//  mac-prompt
//

import SwiftData
import SwiftUI

struct FolderTagsPanel: View {
    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.createdAt) private var folders: [Folder]
    @Bindable var script: Script

    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FOLDER & TAGS")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundColor(theme.textFaint)

            Menu {
                Button("No Folder") { script.folder = nil }
                ForEach(folders) { folder in
                    Button(folder.name) { script.folder = folder }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(theme.accentPalette[script.accentIndex % theme.accentPalette.count])
                        .frame(width: 8, height: 8)
                    Text(script.folder?.name ?? "No Folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.text)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(theme.textFaint)
                }
            }
            .menuStyle(.borderlessButton)

            FlowTags(tags: script.tags, onRemove: { tag in script.tags.removeAll { $0 == tag } })

            HStack(spacing: 6) {
                TextField("Add tag…", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(theme.text)
                    .onSubmit(addTag)
                Button(action: addTag) {
                    Image(systemName: "plus.circle.fill").foregroundColor(theme.textFaint)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(theme.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(16)
        .cardBackground()
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !script.tags.contains(trimmed) else { return }
        script.tags.append(trimmed)
        newTag = ""
    }
}

private struct FlowTags: View {
    @Environment(\.theme) private var theme
    let tags: [String]
    var onRemove: (String) -> Void

    var body: some View {
        if !tags.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                        Button(action: { onRemove(tag) }) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(theme.textDim)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(theme.surface2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
        }
    }
}
