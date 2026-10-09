import Foundation

struct VRHeadingCalibration {
    private var reference: Float = 0

    mutating func recenter(heading: Float) {
        reference = heading
    }

    func engineYaw(heading: Float) -> Float {
        let delta = heading - reference
        // Keep heading continuous across the sensor's -pi/pi seam. Ballistica
        // adds its own pi base rotation; pi here keeps neutral facing the arena.
        return Float.pi + atan2f(sinf(delta), cosf(delta))
    }
}
