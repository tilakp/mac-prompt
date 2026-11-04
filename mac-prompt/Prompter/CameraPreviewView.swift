//
//  CameraPreviewView.swift
//  mac-prompt
//

import AVFoundation
import SwiftUI

/// Shows a live `AVCaptureSession` as the Prompter's full-window camera background.
/// `RecordingController` starts and stops the session.
///
/// The image is always mirrored, like a mirror or a video call self-view. The Prompter's
/// "Mirror flip" (M) is different: it flips the whole window (camera, text and guide
/// band) for a beam-splitter teleprompter rig.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    /// The preview layer's connection exists only after the session gets a camera
    /// input, so mirroring is applied again when this turns true.
    let isCameraReady: Bool

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
