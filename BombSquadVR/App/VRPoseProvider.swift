import CoreMotion
import Foundation

struct VRHeadPose {
    var yaw: Float
    var pitch: Float
    var roll: Float
}

final class VRPoseProvider {
    private let motionManager = CMMotionManager()
    private var referenceYaw: Float?
    private var manualYaw: Float = 0
    private var manualPitch: Float = 0

    func start() {
        guard motionManager.isDeviceMotionAvailable else {
            return
        }
        motionManager.deviceMotionUpdateInterval = 1.0 / 90.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    func recenter() {
        referenceYaw = motionManager.deviceMotion.map { Float($0.attitude.yaw) }
        manualYaw = 0
        manualPitch = 0
    }

    func adjustManual(deltaYaw: Float, deltaPitch: Float) {
        manualYaw += deltaYaw
        manualPitch = max(-0.85, min(0.85, manualPitch + deltaPitch))
    }

    func currentPose(time: TimeInterval) -> VRHeadPose {
        guard let attitude = motionManager.deviceMotion?.attitude else {
            return VRHeadPose(
                yaw: manualYaw + Float(sin(time * 0.15)) * 0.07,
                pitch: manualPitch,
                roll: 0
            )
        }

        let yaw = Float(attitude.yaw)
        if referenceYaw == nil {
            referenceYaw = yaw
        }

        return VRHeadPose(
            yaw: yaw - (referenceYaw ?? 0) + manualYaw,
            pitch: Float(attitude.pitch) + manualPitch,
            roll: Float(attitude.roll)
        )
    }
}
