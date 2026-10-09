import Foundation

struct VRHeadingCalibration {
    private var reference: Float = 0

    mutating func recenter(heading: Float) {
        reference = heading
    }

    func engineYaw(heading: Float) -> Float {
        let delta = heading - reference
        // Keep heading continuous across the sensor's -pi/pi seam. Ballistica
        // applies its own pi base rotation, so recenter returns zero here.
        return atan2f(sinf(delta), cosf(delta))
    }
}
