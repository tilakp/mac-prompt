//
//  ReadingPacePanel.swift
//  mac-prompt
//

import SwiftUI

struct ReadingPacePanel: View {
    @Environment(\.theme) private var theme
    @Bindable var script: Script
    let wordCount: Int

    private let range = AppSettingsDefaults.wpmRange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("READING PACE").panelTitle()

            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(script.targetWPM)")
                        .font(.heading(22))
                        .foregroundStyle(theme.text)
                    Text("wpm")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textFaint)
                }
                Spacer()
                Text("~\(Script.estimatedDuration(wordCount: wordCount, wpm: script.targetWPM))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textFaint)
            }

            Slider(
                value: Binding(
                    get: { Double(script.targetWPM) },
                    set: { script.targetWPM = Int($0) }
                ),
                in: range
            )
            .tint(theme.violet)

            HStack {
                Text("\(Int(range.lowerBound))").font(.system(size: 10.5, weight: .semibold))
                Spacer()
                Text("\(Int(range.upperBound))").font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(theme.textFaint)
        }
        .padding(16)
        .cardBackground()
    }
}
