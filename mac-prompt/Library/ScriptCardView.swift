//
//  ScriptCardView.swift
//  mac-prompt
//

import SwiftUI

struct ScriptCardView: View {
    @Environment(\.theme) private var theme
    let script: Script
    var onOpen: () -> Void
    var onDelete: () -> Void

    private var accentColor: Color { theme.accent(at: script.accentIndex) }

    var body: some View {
        let wordCount = script.wordCount
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(accentColor).frame(height: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(accentColor).frame(width: 7, height: 7)
                        Text(script.folder?.name ?? "No Folder")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(theme.textDim)
                    }
                    Spacer()
                    if script.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.amber)
                    }
                    Menu {
                        ScriptMenuItems(script: script, onDelete: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(theme.textFaint)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 18)
                    .help("More")
                    .accessibilityLabel("More actions")
                }

                Text(script.title)
                    .font(.heading(15.5))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)

                Text(script.snippet.isEmpty ? "Empty script" : script.snippet)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textDim)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                    Text("\(wordCount) words")
                    Text("·").opacity(0.5)
                    Image(systemName: "clock")
                    Text(Script.estimatedDuration(wordCount: wordCount, wpm: script.targetWPM))
                    Text("·").opacity(0.5)
                    Text(script.editedAt.formatted(.relative(presentation: .named)))
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.textFaint)
            }
            .padding(16)
        }
        .frame(height: 190)
        .cardBackground()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
        .contextMenu { ScriptMenuItems(script: script, onDelete: onDelete) }
    }
}

/// The actions for one script: its card's menu and the context menus of its card and
/// list row.
struct ScriptMenuItems: View {
    let script: Script
    var onDelete: () -> Void

    var body: some View {
        if script.isTrashed {
            Button("Put Back") { script.isTrashed = false }
        }
        Button(script.isFavorite ? "Remove from Favorites" : "Add to Favorites") { script.isFavorite.toggle() }
        Button(script.isTrashed ? "Delete Permanently" : "Move to Trash", role: .destructive, action: onDelete)
    }
}
