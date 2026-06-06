import AVFoundation
import Foundation

enum CameraCaptureState: Equatable {
    case idle
    case running
    case permissionDenied
    case unavailable
}

enum CameraFrameCaptureError: Error, Equatable {
    case unavailable
}

struct CapturedCameraFrame {
    var sampleBuffer: CMSampleBuffer
    var time: TimeInterval
}

protocol CameraFrameCapturing: AnyObject {
    var frameHandler: ((CapturedCameraFrame) -> Void)? { get set }

    func start() async throws
    func stop()
}

final class LiveCameraFrameCapture: NSObject, CameraFrameCapturing, @unchecked Sendable {
    private let session: AVCaptureSession
    private let output: AVCaptureVideoDataOutput
    private let captureQueue: DispatchQueue
    private var isConfigured = false

    var frameHandler: ((CapturedCameraFrame) -> Void)?

    override init() {
        self.session = AVCaptureSession()
        self.output = AVCaptureVideoDataOutput()
        self.captureQueue = DispatchQueue(label: "com.metatron.GlanceHold.camera.capture")
        super.init()
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            captureQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraFrameCaptureError.unavailable)
                    return
                }

                do {
                    try self.configureIfNeeded()
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        captureQueue.async { [weak self] in
            guard let self else {
                return
            }

            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.frameHandler = nil
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else {
            return
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraFrameCaptureError.unavailable
        }

        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input) else {
            throw CameraFrameCaptureError.unavailable
        }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(output) else {
            throw CameraFrameCaptureError.unavailable
        }
        session.addOutput(output)

        isConfigured = true
    }
}

extension LiveCameraFrameCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        frameHandler?(CapturedCameraFrame(sampleBuffer: sampleBuffer, time: timestamp.seconds))
    }
}
