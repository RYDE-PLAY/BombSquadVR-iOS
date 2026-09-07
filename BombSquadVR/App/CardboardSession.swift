import GLKit
import Foundation

enum StereoEye {
    case left
    case right
}

struct CardboardStereoFrame {
    var headPose: VRHeadPose
    var leftProjection: GLKMatrix4
    var rightProjection: GLKMatrix4
    var leftEyeOffsetX: Float
    var rightEyeOffsetX: Float
    var leftEyeRenderState: VREyeRenderState
    var rightEyeRenderState: VREyeRenderState
    var isUsingFallbackViewer: Bool

    func projection(for eye: StereoEye) -> GLKMatrix4 {
        eye == .left ? leftProjection : rightProjection
    }

    func eyeOffsetX(for eye: StereoEye) -> Float {
        eye == .left ? leftEyeOffsetX : rightEyeOffsetX
    }

    func eyeRenderState(for eye: StereoEye) -> VREyeRenderState {
        eye == .left ? leftEyeRenderState : rightEyeRenderState
    }
}

struct VREyeRenderState {
    var tanLeft: Float
    var tanRight: Float
    var tanBottom: Float
    var tanTop: Float
    var eyeX: Float
    var eyeY: Float
    var eyeZ: Float

    var arrayValue: [Float] {
        [tanLeft, tanRight, tanBottom, tanTop, eyeX, eyeY, eyeZ]
    }

    static func fallback(eye: StereoEye) -> VREyeRenderState {
        let tangent = tanf(GLKMathDegreesToRadians(45))
        let eyeX: Float = eye == .left ? -0.032 : 0.032
        return VREyeRenderState(
            tanLeft: tangent,
            tanRight: tangent,
            tanBottom: tangent,
            tanTop: tangent,
            eyeX: eyeX,
            eyeY: 0,
            eyeZ: 0
        )
    }
}

final class CardboardSession {
    private let bridge = BSCardboardBridge()
    private let predictionNanos: Int64 = 50_000_000
    private let eyeMatrixWorldScale: Float = 10.5

    func resume() {
        bridge.resume()
    }

    func pause() {
        bridge.pause()
    }

    func recenter() {
        bridge.recenter()
    }

    func scanViewerQRCode() {
        bridge.scanViewerQRCode()
    }

    func shutdownRendering() {
        bridge.destroyDistortionRenderer()
    }

    func renderDistortion(
        sourceTexture: GLuint,
        targetFramebuffer: GLuint,
        drawableWidth: Int,
        drawableHeight: Int
    ) -> Bool {
        bridge.renderDistortion(
            withSourceTexture: sourceTexture,
            targetFramebuffer: targetFramebuffer,
            width: Int32(drawableWidth),
            height: Int32(drawableHeight)
        )
    }

    func frameState(drawableWidth: Int, drawableHeight: Int) -> CardboardStereoFrame? {
        guard bridge.updateLens(withDisplayWidth: Int32(drawableWidth), height: Int32(drawableHeight)) else {
            return nil
        }

        let headPose = currentHeadPose()
        let leftProjection = projection(eye: 0)
        let rightProjection = projection(eye: 1)
        let leftEyeOffset = eyeOffsetX(eye: 0)
        let rightEyeOffset = eyeOffsetX(eye: 1)
        let leftRenderState = eyeRenderState(eye: 0)
        let rightRenderState = eyeRenderState(eye: 1)

        return CardboardStereoFrame(
            headPose: headPose,
            leftProjection: leftProjection,
            rightProjection: rightProjection,
            leftEyeOffsetX: leftEyeOffset,
            rightEyeOffsetX: rightEyeOffset,
            leftEyeRenderState: leftRenderState,
            rightEyeRenderState: rightRenderState,
            isUsingFallbackViewer: bridge.isUsingFallbackViewer
        )
    }

    private func currentHeadPose() -> VRHeadPose {
        var position = [Float](repeating: 0, count: 3)
        var orientation = [Float](repeating: 0, count: 4)
        position.withUnsafeMutableBufferPointer { positionBuffer in
            orientation.withUnsafeMutableBufferPointer { orientationBuffer in
                bridge.copyHeadPosition(
                    positionBuffer.baseAddress!,
                    orientation: orientationBuffer.baseAddress!,
                    predictionNanos: predictionNanos,
                    viewportOrientation: Int32(CardboardViewport.landscapeRight.rawValue)
                )
            }
        }

        let quaternion = GLKQuaternionMake(
            orientation[0],
            orientation[1],
            orientation[2],
            orientation[3]
        )
        let rotation = GLKMatrix4MakeWithQuaternion(quaternion)
        let forward = GLKMatrix4MultiplyVector4(rotation, GLKVector4Make(0, 0, -1, 0))
        let up = GLKMatrix4MultiplyVector4(rotation, GLKVector4Make(0, 1, 0, 0))
        // Ballistica's VR camera applies its own 180-degree base yaw. Offset
        // Cardboard's recentered forward vector so a tap faces the arena, and
        // flip yaw/pitch deltas to match the engine's camera convention.
        let yaw = Float.pi - atan2f(forward.x, -forward.z)
        let pitch = -asinf(max(-1, min(1, forward.y)))
        let roll = atan2f(up.x, up.y) + Float.pi
        return VRHeadPose(yaw: yaw, pitch: pitch, roll: roll)
    }

    private func projection(eye: Int32) -> GLKMatrix4 {
        var matrix = [Float](repeating: 0, count: 16)
        matrix.withUnsafeMutableBufferPointer { buffer in
            bridge.copyProjection(
                forEye: eye,
                near: 0.08,
                far: 80,
                into: buffer.baseAddress!
            )
        }
        return matrix.withUnsafeMutableBufferPointer { GLKMatrix4MakeWithArray($0.baseAddress!) }
    }

    private func eyeOffsetX(eye: Int32) -> Float {
        var matrix = [Float](repeating: 0, count: 16)
        matrix.withUnsafeMutableBufferPointer { buffer in
            bridge.copyEyeFromHead(forEye: eye, into: buffer.baseAddress!)
        }
        return -matrix[12] * eyeMatrixWorldScale
    }

    private func eyeRenderState(eye: Int32) -> VREyeRenderState {
        var fov = [Float](repeating: 0, count: 4)
        fov.withUnsafeMutableBufferPointer { buffer in
            bridge.copyFieldOfView(forEye: eye, into: buffer.baseAddress!)
        }

        var eyeFromHead = [Float](repeating: 0, count: 16)
        eyeFromHead.withUnsafeMutableBufferPointer { buffer in
            bridge.copyEyeFromHead(forEye: eye, into: buffer.baseAddress!)
        }

        return VREyeRenderState(
            tanLeft: tanf(fov[0]),
            tanRight: tanf(fov[1]),
            tanBottom: tanf(fov[2]),
            tanTop: tanf(fov[3]),
            eyeX: -eyeFromHead[12],
            eyeY: eyeFromHead[13],
            eyeZ: eyeFromHead[14]
        )
    }
}

private enum CardboardViewport: Int32 {
    case landscapeLeft = 0
    case landscapeRight = 1
    case portrait = 2
    case portraitUpsideDown = 3
}
