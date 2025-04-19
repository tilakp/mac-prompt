//
//  ContentView.swift
//  mac-prompt
//
//  Created by Patel, Tilak on 4/17/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct ContentView: View {
    @State public var isEditMode = true
    @State public var promptText = "Generative AI is going to reinvent virtually every customer experience we know, and enable altogether new ones about which we’ve only fantasized. The early AI workloads being deployed focus on productivity and cost avoidance (e.g. customer service, business process orchestration, workflow, translation, etc.). This is saving companies a lot of money. Increasingly, you’ll see AI change the norms in coding, search, shopping, personal assistants, primary care, cancer and drug research, biology, robotics, space, financial services, neighborhood networks—everything. Some of these areas are already seeing rapid progress; others are still in their infancy. But, if your customer experiences aren’t planning to leverage these intelligent models, their ability to query giant corpuses of data and quickly find your needle in the haystack, their ability to keep getting smarter with more feedback and data, and their future agentic capabilities, you will not be competitive. How soon? It won’t all happen in a year or two, but, it won’t take ten either. It’s moving faster than almost anything technology has ever seen."
    @State public var bgColor = Color.black
    @State public var textColor = Color.white
    @State public var scrollSpeed: Double = 50 // points per second
    @State public var fontSize: CGFloat = 48
    @State public var scrollOffset: CGFloat = 0
    @State public var timer: Timer? = nil
    @State public var availableHeight: CGFloat = 0
    @State public var lineSpacing: CGFloat = 8
    @State public var isPlaying: Bool = true
    @State public var textHeight: CGFloat = 0 // Track text height for clamping
    @State public var controlsOnRight: Bool = false // User preference for sidebar position
    @State private var undoStack: [String] = []
    @State private var redoStack: [String] = []

    public var body: some View {
        _body
    }
    private var _body: some View {
        VStack(spacing: 0) {
            if isEditMode {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Edit Mode")
                            .font(.title2.weight(.semibold))
                        Spacer()
                        Button(action: { loadTextFile() }) {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.title2)
                                .help("Load text from file")
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        Button(action: { saveTextFile() }) {
                            Image(systemName: "externaldrive")
                                .font(.title2)
                                .help("Save text to file")
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        Button(action: { undoText() }) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.title2)
                                .help("Undo")
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        Button(action: { redoText() }) {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.title2)
                                .help("Redo")
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        Button {
                            withAnimation {
                                isEditMode.toggle()
                                stopScrolling()
                                if !isEditMode { startScrolling() }
                            }
                        } label: {
                            Label("Teleprompt", systemImage: "play.fill")
                                .labelStyle(.iconOnly)
                                .font(.title2)
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                    .padding(.horizontal)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                    TextEditor(text: $promptText)
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.gray.opacity(0.08))
                        )
                        .padding(.horizontal)
                        .padding(.bottom)
                        .onChange(of: promptText) { oldValue, newValue in
                            onPromptTextChanged(oldValue: oldValue, newValue: newValue)
                        }
                }
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 6)
                )
                .padding(.all, 32)
                .transition(.move(edge: .bottom))
            } else {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        if !controlsOnRight {
                            ControlsSidebar(
                                isEditMode: $isEditMode,
                                isPlaying: $isPlaying,
                                scrollOffset: $scrollOffset,
                                scrollSpeed: $scrollSpeed,
                                lineSpacing: $lineSpacing,
                                fontSize: $fontSize,
                                bgColor: $bgColor,
                                textColor: $textColor,
                                controlsOnRight: $controlsOnRight
                            )
                        }
                        GeometryReader { textGeo in
                            ZStack {
                                RoundedRectangle(cornerRadius: 36, style: .continuous)
                                    .fill(bgColor)
                                    .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
                                VStack {
                                    Spacer(minLength: 24)
                                    Spacer(minLength: availableHeight / 2)
                                    Text(promptText)
                                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                                        .foregroundColor(textColor)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineSpacing(lineSpacing)
                                        .offset(y: scrollOffset)
                                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                        .background(GeometryReader { geo in
                                            Color.clear
                                                .onAppear {
                                                    updateGeometry(textGeo: textGeo, geo: geo)
                                                    scrollOffset = availableHeight / 2
                                                }
                                                .onChange(of: promptText) { _, _ in
                                                    updateGeometry(textGeo: textGeo, geo: geo)
                                                    scrollOffset = availableHeight / 2
                                                }
                                                .onChange(of: fontSize) { _, _ in
                                                    updateGeometry(textGeo: textGeo, geo: geo)
                                                    scrollOffset = availableHeight / 2
                                                }
                                        })
                                    Spacer(minLength: availableHeight / 2)
                                    Spacer(minLength: 24)
                                }
                            }
                            .frame(maxHeight: .infinity)
                            .background(
                                KeyboardShortcutView { key in
                                    if key == .space {
                                        if isPlaying {
                                            stopScrolling()
                                        } else {
                                            isPlaying = true
                                            // Resume scrolling without resetting scrollOffset
                                            if timer == nil {
                                                timer = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { _ in
                                                    if isPlaying {
                                                        let minOffset = -(textHeight - availableHeight / 2)
                                                        let maxOffset = availableHeight / 2
                                                        let nextOffset = scrollOffset - CGFloat(scrollSpeed) * 0.008
                                                        withAnimation(.easeInOut(duration: 0.08)) {
                                                            scrollOffset = min(max(nextOffset, minOffset), maxOffset)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            )
                        }
                        if controlsOnRight {
                            ControlsSidebar(
                                isEditMode: $isEditMode,
                                isPlaying: $isPlaying,
                                scrollOffset: $scrollOffset,
                                scrollSpeed: $scrollSpeed,
                                lineSpacing: $lineSpacing,
                                fontSize: $fontSize,
                                bgColor: $bgColor,
                                textColor: $textColor,
                                controlsOnRight: $controlsOnRight
                            )
                        }
                    }
                }
                .onAppear { startScrolling() }
                .onDisappear { stopScrolling() }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isEditMode)
        .onDisappear { stopScrolling() }
    }
    
    // Testable helper for geometry update
    public func updateGeometryForTest(textHeight: CGFloat, availableHeight: CGFloat) {
        self.availableHeight = availableHeight
        self.textHeight = textHeight
        let minOffset = -(textHeight - availableHeight / 2)
        let maxOffset = availableHeight / 2
        if scrollOffset < minOffset {
            scrollOffset = minOffset
        }
        if scrollOffset > maxOffset {
            scrollOffset = maxOffset
        }
    }
    
    func updateGeometry(textGeo: GeometryProxy, geo: GeometryProxy) {
        availableHeight = textGeo.size.height
        textHeight = geo.size.height
        // Clamp scrollOffset so text never scrolls out of bounds
        let minOffset = -(textHeight - availableHeight / 2)
        let maxOffset = availableHeight / 2
        if scrollOffset < minOffset {
            scrollOffset = minOffset
        }
        if scrollOffset > maxOffset {
            scrollOffset = maxOffset
        }
    }
    
    func startScrolling() {
        stopScrolling()
        // Do not reset scrollOffset here; only reset if starting fresh
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { _ in
            if isPlaying {
                // Clamp scrollOffset so text never scrolls out of bounds
                let minOffset = -(textHeight - availableHeight / 2)
                let maxOffset = availableHeight / 2
                let nextOffset = scrollOffset - CGFloat(scrollSpeed) * 0.008
                withAnimation(.easeInOut(duration: 0.08)) {
                    scrollOffset = min(max(nextOffset, minOffset), maxOffset)
                }
            }
        }
    }
    func stopScrolling() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
    }
    
    private func loadTextFile() {
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType.plainText]
        } else {
            panel.allowedFileTypes = ["txt"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            if let content = try? String(contentsOf: url) {
                promptText = content
            }
        }
    }
    
    private func saveTextFile() {
        let panel = NSSavePanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType.plainText]
        } else {
            panel.allowedFileTypes = ["txt"]
        }
        panel.nameFieldStringValue = "Prompt.txt"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try promptText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Show error alert if needed
                let alert = NSAlert()
                alert.messageText = "Failed to save file"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
    
    private func pushUndo() {
        undoStack.append(promptText)
        redoStack.removeAll()
    }
    
    private func undoText() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(promptText)
        promptText = last
    }
    
    private func redoText() {
        guard let last = redoStack.popLast() else { return }
        undoStack.append(promptText)
        promptText = last
    }
    
    // Track text changes for undo
    private func onPromptTextChanged(oldValue: String, newValue: String) {
        if oldValue != newValue {
            pushUndo()
        }
    }
}

// Modern button style
struct ModernButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.7 : 1.0))
            )
            .foregroundColor(.white)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.05 : 0.15), radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

// Sidebar for all controls, reusable for left/right
struct ControlsSidebar: View {
    @Binding var isEditMode: Bool
    @Binding var isPlaying: Bool
    @Binding var scrollOffset: CGFloat
    @Binding var scrollSpeed: Double
    @Binding var lineSpacing: CGFloat
    @Binding var fontSize: CGFloat
    @Binding var bgColor: Color
    @Binding var textColor: Color
    @Binding var controlsOnRight: Bool

    var body: some View {
        VStack(spacing: 18) {
            // Move controls left/right button
            Button(action: {
                controlsOnRight.toggle()
            }) {
                Image(systemName: controlsOnRight ? "arrow.left.square" : "arrow.right.square")
                    .font(.title2)
            }
            .buttonStyle(ModernButtonStyle())
            // Playback controls in a horizontal row
            HStack(spacing: 18) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scrollOffset += 60
                    }
                }) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .buttonStyle(ModernButtonStyle())
                Button(action: {
                    isPlaying.toggle()
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(ModernButtonStyle())
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scrollOffset -= 60
                    }
                }) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .buttonStyle(ModernButtonStyle())
            }
            Divider().padding(.vertical, 8)
            // Edit mode toggle
            Button {
                withAnimation {
                    isEditMode.toggle()
                }
            } label: {
                Label("Edit", systemImage: "pencil")
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
            .buttonStyle(ModernButtonStyle())
            Divider().padding(.vertical, 8)
            // Color and text controls
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("Background:")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    ColorPicker("Background", selection: $bgColor)
                        .labelsHidden()
                        .frame(width: 36, height: 36)
                }
                HStack(spacing: 8) {
                    Text("Text Color:")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    ColorPicker("Text", selection: $textColor)
                        .labelsHidden()
                        .frame(width: 36, height: 36)
                }
                HStack(spacing: 4) {
                    Image(systemName: "hare.fill")
                    Slider(value: $scrollSpeed, in: 10...100)
                        .frame(width: 80)
                    TextField("", value: $scrollSpeed, formatter: NumberFormatter())
                        .frame(width: 36)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Image(systemName: "tortoise.fill")
                }
                HStack(spacing: 4) {
                    Image(systemName: "text.alignleft")
                        .foregroundColor(.secondary)
                    Slider(value: $lineSpacing, in: 0...40, step: 1)
                        .frame(width: 64)
                    TextField("", value: $lineSpacing, formatter: NumberFormatter())
                        .frame(width: 36)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text("\(Int(lineSpacing))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 0) {
                    Button(action: { fontSize = max(10, fontSize - 4) }) {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .buttonStyle(ModernButtonStyle())
                    .frame(width: 28, height: 28)
                    Text("\(Int(fontSize))")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .frame(width: 28)
                    Button(action: { fontSize += 4 }) {
                        Image(systemName: "textformat.size.larger")
                    }
                    .buttonStyle(ModernButtonStyle())
                    .frame(width: 28, height: 28)
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(minWidth: 140, maxWidth: 220)
        .background(
            LinearGradient(gradient: Gradient(colors: [Color(NSColor.windowBackgroundColor), Color.accentColor.opacity(0.08)]), startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }
}

#Preview {
    ContentView()
}

struct KeyboardShortcutView: NSViewRepresentable {
    var onKeyPress: (KeyEquivalent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.onKeyPress = onKeyPress
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class KeyCatcherView: NSView {
        var onKeyPress: ((KeyEquivalent) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if let chars = event.charactersIgnoringModifiers, let first = chars.first {
                if first == " " {
                    onKeyPress?(.space)
                }
            }
        }

        override func viewDidMoveToWindow() {
            window?.makeFirstResponder(self)
        }
    }
}

enum KeyEquivalent: Equatable {
    case space
}
