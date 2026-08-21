//
//  ReadingPacePanel.swift
//  mac-prompt
//

import SwiftUI

struct ReadingPacePanel: View {
    @Environment(\.theme) private var theme
    @Bindable var script: Script

    private let range: ClosedRange<Double> = 100...220

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("READING PACE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundColor(theme.textFaint)

            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(script.targetWPM)")
                        .font(.heading(22))
                        .foregroundColor(theme.text)
                    Text("wpm")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.textFaint)
                }
                Spacer()
                Text("~\(script.estimatedDuration)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.textFaint)
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
            .foregroundColor(theme.textFaint)
        }
        .padding(16)
        .cardBackground()
    }
}
