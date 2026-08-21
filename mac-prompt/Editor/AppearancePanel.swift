//
//  AppearancePanel.swift
//  mac-prompt
//

import SwiftUI

struct AppearancePanel: View {
    @Environment(\.theme) private var theme
    @Bindable var script: Script

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("APPEARANCE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundColor(theme.textFaint)

            HStack {
                Text("Editor text size")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(theme.textDim)
                Spacer()
                HStack(spacing: 10) {
                    stepButton("minus") { script.editorFontSize = max(12, script.editorFontSize - 1) }
                    Text("\(Int(script.editorFontSize))")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(theme.text)
                        .frame(width: 22)
                    stepButton("plus") { script.editorFontSize = min(32, script.editorFontSize + 1) }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Line spacing (Prompter)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(theme.textDim)
                PillSegmentedControl(
                    options: LineSpacingStyle.allCases,
                    selection: Binding(
                        get: { script.lineSpacingStyle },
                        set: { script.lineSpacingStyle = $0 }
                    ),
                    label: \.label
                )
            }
        }
        .padding(16)
        .cardBackground()
    }

    private func stepButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(theme.textDim)
                .frame(width: 26, height: 26)
                .background(theme.surface2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
