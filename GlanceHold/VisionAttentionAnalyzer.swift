import AVFoundation
import Foundation
import ImageIO
import os
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

enum AttentionAnalyzerFactory {
    static func live() -> VisionAttentionAnalyzing {
        LiveVisionAttentionAnalyzer()
    }
}

struct LiveVisionAttentionAnalyzer: VisionAttentionAnalyzing {
    private static let logger = Logger(subsystem: "com.metatron.GlanceHold", category: "VisionAttentionAnalyzer")

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
            Self.logger.warning("Vision face request failed during attention analysis")
            return .failed(time: frame.time)
        }

        guard let observations = request.results, !observations.isEmpty else {
            return .noFace(time: frame.time)
        }

        if observations.count > 1 {
            Self.logger.debug("Vision detected multiple face candidates count=\(observations.count, privacy: .public)")
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
        guard let yawRadians, let pitchRadians else {
            return .ambiguous(time: time)
        }

        return .pose(
            PoseSample(
                yawDegrees: degrees(fromRadians: yawRadians),
                pitchDegrees: degrees(fromRadians: pitchRadians),
                rollDegrees: rollRadians.map(degrees(fromRadians:)) ?? 0.0,
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
