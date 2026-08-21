//
//  CameraPreviewView.swift
//  mac-prompt
//

import AVFoundation
import SwiftUI

/// Renders a live `AVCaptureSession` full-bleed, for the Prompter's camera passthrough
/// background. Purely presentational — session lifecycle lives in RecordingController.
///
/// Always mirrors like a normal self-view (front webcams read naturally mirrored, as
/// in a mirror). The separate "Mirror flip" control (M) in Prompter flips the *entire*
/// composed view — camera, text, and guide band together — for use with physical
/// teleprompter beam-splitter rigs that need the whole display reversed; see
/// `PrompterView`.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        nsView.previewLayer.connection?.isVideoMirrored = true
    }

    final class PreviewNSView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = previewLayer
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
