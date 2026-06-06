import AVFoundation
import Foundation
import ImageIO
import Vision

enum VisionAttentionObservation: Equatable {
    case pose(PoseSample)
    case noFace(time: TimeInterval)
    case ambiguous(time: TimeInterval)
    case failed(time: TimeInterval)
}

protocol VisionAttentionAnalyzing {
    func analyze(_ frame: CapturedCameraFrame) -> VisionAttentionObservation
}

struct LiveVisionAttentionAnalyzer: VisionAttentionAnalyzing {
    func analyze(_ frame: CapturedCameraFrame) -> VisionAttentionObservation {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(
            cmSampleBuffer: frame.sampleBuffer,
            orientation: .up,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            return .failed(time: frame.time)
        }

        guard let observations = request.results, !observations.isEmpty else {
            return .noFace(time: frame.time)
        }

        let primary = observations.max { left, right in
            boundingArea(left.boundingBox) < boundingArea(right.boundingBox)
        }

        guard let primary else {
            return .noFace(time: frame.time)
        }

        return Self.observation(
            yawRadians: primary.yaw?.doubleValue,
            pitchRadians: primary.pitch?.doubleValue,
            rollRadians: primary.roll?.doubleValue,
            time: frame.time
        )
    }

    static func observation(
        yawRadians: Double?,
        pitchRadians: Double?,
        rollRadians: Double?,
        time: TimeInterval
    ) -> VisionAttentionObservation {
        guard let yawRadians, let pitchRadians, let rollRadians else {
            return .ambiguous(time: time)
        }

        return .pose(
            PoseSample(
                yawDegrees: degrees(fromRadians: yawRadians),
                pitchDegrees: degrees(fromRadians: pitchRadians),
                rollDegrees: degrees(fromRadians: rollRadians),
                time: time
            )
        )
    }

    private static func degrees(fromRadians radians: Double) -> Double {
        radians * 180.0 / .pi
    }

    private func boundingArea(_ rect: CGRect) -> Double {
        rect.width * rect.height
    }
}
