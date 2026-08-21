//
//  ScriptCardView.swift
//  mac-prompt
//

import SwiftUI

struct ScriptCardView: View {
    @Environment(\.theme) private var theme
    let script: Script
    var onOpen: () -> Void
    var onToggleFavorite: () -> Void
    var onDelete: () -> Void

    private var accentColor: Color { theme.accentPalette[script.accentIndex % theme.accentPalette.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(accentColor).frame(height: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(accentColor).frame(width: 7, height: 7)
                        Text(script.folder?.name ?? "No Folder")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(theme.textDim)
                    }
                    Spacer()
                    if script.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(theme.amber)
                    }
                    Menu {
                        Button(script.isFavorite ? "Remove from Favorites" : "Add to Favorites", action: onToggleFavorite)
                        Button(script.isTrashed ? "Delete Permanently" : "Move to Trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(theme.textFaint)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 18)
                }

                Text(script.title)
                    .font(.heading(15.5))
                    .foregroundColor(theme.text)
                    .lineLimit(2)

                Text(script.snippet.isEmpty ? "Empty script" : script.snippet)
                    .font(.system(size: 12.5))
                    .foregroundColor(theme.textDim)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                    Text("\(script.wordCount) words")
                    Text("·").opacity(0.5)
                    Image(systemName: "clock")
                    Text(script.estimatedDuration)
                    Text("·").opacity(0.5)
                    Text(script.editedAt.formatted(.relative(presentation: .named)))
                }
                .font(.system(size: 11))
                .foregroundColor(theme.textFaint)
            }
            .padding(16)
        }
        .frame(height: 190)
        .cardBackground()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button(script.isFavorite ? "Remove from Favorites" : "Add to Favorites", action: onToggleFavorite)
            Button(script.isTrashed ? "Delete Permanently" : "Move to Trash", role: .destructive, action: onDelete)
        }
    }
}
