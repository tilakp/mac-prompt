//
//  EditorView.swift
//  mac-prompt
//

import SwiftData
import SwiftUI

struct EditorView: View {
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    @Bindable var script: Script
    var onClose: () -> Void
    @StateObject private var cueController = CueTextController()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)
            HStack(spacing: 0) {
                editorColumn
                Divider().overlay(theme.border)
                inspector
            }
        }
        .background(theme.bg)
        .onChange(of: script.body) { _, _ in script.editedAt = .now }
        .onChange(of: script.title) { _, _ in script.editedAt = .now }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Library")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textFaint)
            }
            .buttonStyle(.plain)

            Text("/").foregroundColor(theme.textFaint).opacity(0.5)

            TextField("Untitled Script", text: $script.title)
                .textFieldStyle(.plain)
                .font(.heading(15))
                .foregroundColor(theme.text)
                .frame(minWidth: 120, maxWidth: 360)

            Spacer()

            Text("\(script.wordCount) words · ~\(script.estimatedDuration) at \(script.targetWPM) wpm")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.textFaint)

            Button {
                openWindow(id: "prompter", value: script.id)
            } label: {
                HStack(spacing: 8) {
                    Text("Start Prompting")
                    Image(systemName: "play.fill")
                }
            }
            .buttonStyle(GradientButtonStyle())
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.sidebar)
    }

    private var editorColumn: some View {
        VStack(spacing: 0) {
            CueToolbar(controller: cueController)
                .padding(.top, 18)
                .padding(.bottom, 14)
            CueTextView(text: $script.body, fontSize: script.editorFontSize, controller: cueController)
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspector: some View {
        ScrollView {
            VStack(spacing: 16) {
                ReadingPacePanel(script: script)
                AppearancePanel(script: script)
                FolderTagsPanel(script: script)
            }
            .padding(16)
        }
        .frame(width: 272)
        .background(theme.sidebar)
    }
}

/// The floating formatting toolbar above the text area: bold/italic markdown wrapping
/// plus cue-token insertion buttons.
private struct CueToolbar: View {
    @Environment(\.theme) private var theme
    let controller: CueTextController

    var body: some View {
        HStack(spacing: 2) {
            toolButton("bold") { controller.wrapSelection(with: "**") }
            toolButton("italic") { controller.wrapSelection(with: "*") }
            Rectangle().fill(theme.border).frame(width: 1, height: 18).padding(.horizontal, 3)
            toolButton("pause.circle") { controller.insert(" " + CueToken.pause.insertionText + " ") }
            toolButton("bolt.circle") { controller.insert(" " + CueToken.emphasis.insertionText + " ") }
            toolButton("forward.circle") { controller.insert(" " + CueToken.faster.insertionText + " ") }
            toolButton("backward.circle") { controller.insert(" " + CueToken.slower.insertionText + " ") }
        }
        .padding(5)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    private func toolButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textDim)
                .frame(width: 30, height: 28)
        }
        .buttonStyle(.plain)
    }
}
