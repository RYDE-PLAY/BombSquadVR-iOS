import GLKit
import UIKit

final class VRGameViewController: GLKViewController, GLKViewControllerDelegate {
    private let host = BombSquadVRBallisticaHost.shared()
    private let poseProvider = VRPoseProvider()
    private let cardboardSession = CardboardSession()
    private lazy var controllerBridge = VRControllerBridge(host: host)
    private var glContext: EAGLContext?
    private var controllerBridgeStarted = false
    private var distortionCopyTexture: GLuint = 0
    private var distortionVertexArray: GLuint = 0
    private var distortionCopyWidth = 0
    private var distortionCopyHeight = 0

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscapeRight
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        .landscapeRight
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureGL()
        configureGestures()
        startBallistica()
        poseProvider.start()
        cardboardSession.resume()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestLandscapeGeometry()
    }

    deinit {
        let previousContext = EAGLContext.current()
        if let glContext {
            EAGLContext.setCurrent(glContext)
        }
        controllerBridge.stop()
        poseProvider.stop()
        cardboardSession.pause()
        cardboardSession.shutdownRendering()
        if distortionCopyTexture != 0 {
            var texture = distortionCopyTexture
            glDeleteTextures(1, &texture)
            distortionCopyTexture = 0
        }
        if distortionVertexArray != 0 {
            var vertexArray = distortionVertexArray
            glDeleteVertexArrays(1, &vertexArray)
            distortionVertexArray = 0
        }
        if let previousContext, previousContext !== glContext {
            EAGLContext.setCurrent(previousContext)
        } else {
            EAGLContext.setCurrent(nil)
        }
    }

    func pauseRendering() {
        isPaused = true
        poseProvider.stop()
        cardboardSession.pause()
    }

    func resumeRendering() {
        poseProvider.start()
        cardboardSession.resume()
        isPaused = false
    }

    private func configureGL() {
        let context = EAGLContext(api: .openGLES3) ?? EAGLContext(api: .openGLES2)
        guard let context else {
            fatalError("Unable to create an OpenGL ES context")
        }

        glContext = context
        EAGLContext.setCurrent(context)

        let glView = GLKView(frame: view.bounds, context: context)
        glView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        glView.drawableColorFormat = .RGBA8888
        glView.drawableDepthFormat = .format24
        glView.drawableStencilFormat = .format8
        glView.enableSetNeedsDisplay = false
        glView.accessibilityIdentifier = "vrGameView"
        view = glView

        preferredFramesPerSecond = 60
        delegate = self
    }

    private func requestLandscapeGeometry() {
        guard #available(iOS 16.0, *),
              let windowScene = view.window?.windowScene else {
            return
        }
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
            NSLog("BombSquadVR landscape geometry request failed: \(error.localizedDescription)")
        }
        setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private func startBallistica() {
        guard let resourcePath = Bundle.main.path(forResource: "BallisticaResources", ofType: nil) else {
            assertionFailure("Ballistica resources missing")
            return
        }
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheURL = urls[0].appendingPathComponent("BombSquadVRBallisticaCache", isDirectory: true)
        let configURL = urls[0].appendingPathComponent("BombSquadVRBallisticaConfig", isDirectory: true)
        host.start(
            withResourcePath: resourcePath,
            cachePath: cacheURL.path,
            configPath: configURL.path
        )
    }

    private func configureGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(panGesture)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        view.addGestureRecognizer(tapGesture)

        let viewerGesture = UITapGestureRecognizer(target: self, action: #selector(handleViewerTap(_:)))
        viewerGesture.numberOfTouchesRequired = 2
        viewerGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(viewerGesture)
        tapGesture.require(toFail: viewerGesture)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        poseProvider.adjustManual(
            deltaYaw: Float(-translation.x * 0.004),
            deltaPitch: Float(-translation.y * 0.004)
        )
        gesture.setTranslation(.zero, in: view)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            poseProvider.recenter()
            cardboardSession.recenter()
        }
    }

    @objc private func handleViewerTap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            cardboardSession.scanViewerQRCode()
        }
    }

    func glkViewControllerUpdate(_ controller: GLKViewController) {
        guard host.isStarted else {
            return
        }
        if !host.isInitialized {
            _ = host.stepInitialization()
        }
        if host.isInitialized && !controllerBridgeStarted {
            controllerBridgeStarted = true
            controllerBridge.start()
        }
    }

    override func glkView(_ view: GLKView, drawIn rect: CGRect) {
        guard glContext != nil else {
            return
        }
        EAGLContext.setCurrent(glContext)

        let drawableWidth = Int(view.drawableWidth)
        let drawableHeight = Int(view.drawableHeight)
        let time = CACurrentMediaTime()
        let cardboardFrame = cardboardSession.frameState(
            drawableWidth: drawableWidth,
            drawableHeight: drawableHeight
        )
        let pose = cardboardFrame?.headPose ?? poseProvider.currentPose(time: time)
        let leftEye = cardboardFrame?.leftEyeRenderState ?? .fallback(eye: .left)
        let rightEye = cardboardFrame?.rightEyeRenderState ?? .fallback(eye: .right)

        var leftValues = leftEye.arrayValue
        var rightValues = rightEye.arrayValue
        let rendered = leftValues.withUnsafeBufferPointer { leftBuffer in
            rightValues.withUnsafeBufferPointer { rightBuffer in
                host.renderStereoFrame(
                    withDrawableWidth: drawableWidth,
                    height: drawableHeight,
                    headYaw: pose.yaw,
                    headPitch: pose.pitch,
                    headRoll: pose.roll,
                    leftEye: leftBuffer.baseAddress!,
                    rightEye: rightBuffer.baseAddress!
                )
            }
        }

        if !rendered {
            glDisable(GLenum(GL_SCISSOR_TEST))
            glClearColor(0.02, 0.025, 0.03, 1.0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
        } else if cardboardFrame != nil {
            _ = applyCardboardDistortion(
                drawableWidth: drawableWidth,
                drawableHeight: drawableHeight
            )
        }
    }

    private func applyCardboardDistortion(drawableWidth: Int, drawableHeight: Int) -> Bool {
        guard glContext?.api == .openGLES3, drawableWidth > 0, drawableHeight > 0 else {
            return false
        }

        var targetFramebuffer: GLint = 0
        var viewport = [GLint](repeating: 0, count: 4)
        var scissorBox = [GLint](repeating: 0, count: 4)
        var activeTexture: GLint = 0
        var texture0Binding: GLint = 0
        var arrayBufferBinding: GLint = 0
        var elementArrayBufferBinding: GLint = 0
        var currentProgram: GLint = 0
        var vertexArrayBinding: GLint = 0
        var clearColor = [GLfloat](repeating: 0, count: 4)
        var colorWriteMask = [GLboolean](repeating: GLboolean(GL_TRUE), count: 4)
        var depthWriteMask = GLboolean(GL_TRUE)
        let scissorEnabled = glIsEnabled(GLenum(GL_SCISSOR_TEST)) == GLboolean(GL_TRUE)
        let cullFaceEnabled = glIsEnabled(GLenum(GL_CULL_FACE)) == GLboolean(GL_TRUE)
        let depthTestEnabled = glIsEnabled(GLenum(GL_DEPTH_TEST)) == GLboolean(GL_TRUE)
        let blendEnabled = glIsEnabled(GLenum(GL_BLEND)) == GLboolean(GL_TRUE)

        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &targetFramebuffer)
        viewport.withUnsafeMutableBufferPointer {
            glGetIntegerv(GLenum(GL_VIEWPORT), $0.baseAddress!)
        }
        scissorBox.withUnsafeMutableBufferPointer {
            glGetIntegerv(GLenum(GL_SCISSOR_BOX), $0.baseAddress!)
        }
        glGetIntegerv(GLenum(GL_ACTIVE_TEXTURE), &activeTexture)
        glActiveTexture(GLenum(GL_TEXTURE0))
        glGetIntegerv(GLenum(GL_TEXTURE_BINDING_2D), &texture0Binding)
        glActiveTexture(GLenum(activeTexture))
        glGetIntegerv(GLenum(GL_ARRAY_BUFFER_BINDING), &arrayBufferBinding)
        glGetIntegerv(GLenum(GL_ELEMENT_ARRAY_BUFFER_BINDING), &elementArrayBufferBinding)
        glGetIntegerv(GLenum(GL_CURRENT_PROGRAM), &currentProgram)
        glGetIntegerv(GLenum(GL_VERTEX_ARRAY_BINDING), &vertexArrayBinding)
        clearColor.withUnsafeMutableBufferPointer {
            glGetFloatv(GLenum(GL_COLOR_CLEAR_VALUE), $0.baseAddress!)
        }
        colorWriteMask.withUnsafeMutableBufferPointer {
            glGetBooleanv(GLenum(GL_COLOR_WRITEMASK), $0.baseAddress!)
        }
        glGetBooleanv(GLenum(GL_DEPTH_WRITEMASK), &depthWriteMask)

        defer {
            glBindVertexArray(GLuint(vertexArrayBinding))
            glUseProgram(GLuint(currentProgram))
            glBindBuffer(GLenum(GL_ARRAY_BUFFER), GLuint(arrayBufferBinding))
            glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), GLuint(elementArrayBufferBinding))
            glActiveTexture(GLenum(GL_TEXTURE0))
            glBindTexture(GLenum(GL_TEXTURE_2D), GLuint(texture0Binding))
            glActiveTexture(GLenum(activeTexture))
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(targetFramebuffer))
            glViewport(viewport[0], viewport[1], GLsizei(viewport[2]), GLsizei(viewport[3]))
            glScissor(
                scissorBox[0],
                scissorBox[1],
                GLsizei(scissorBox[2]),
                GLsizei(scissorBox[3])
            )
            glClearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3])
            glColorMask(colorWriteMask[0], colorWriteMask[1], colorWriteMask[2], colorWriteMask[3])
            glDepthMask(depthWriteMask)
            setGLEnabled(GLenum(GL_SCISSOR_TEST), scissorEnabled)
            setGLEnabled(GLenum(GL_CULL_FACE), cullFaceEnabled)
            setGLEnabled(GLenum(GL_DEPTH_TEST), depthTestEnabled)
            setGLEnabled(GLenum(GL_BLEND), blendEnabled)
        }

        glActiveTexture(GLenum(GL_TEXTURE0))
        guard ensureDistortionCopyTexture(width: drawableWidth, height: drawableHeight),
              ensureDistortionVertexArray() else {
            return false
        }

        glBindTexture(GLenum(GL_TEXTURE_2D), distortionCopyTexture)
        glCopyTexSubImage2D(
            GLenum(GL_TEXTURE_2D),
            0,
            0,
            0,
            0,
            0,
            GLsizei(drawableWidth),
            GLsizei(drawableHeight)
        )

        glBindVertexArray(distortionVertexArray)
        glDisable(GLenum(GL_DEPTH_TEST))
        glDisable(GLenum(GL_BLEND))
        glColorMask(GLboolean(GL_TRUE), GLboolean(GL_TRUE), GLboolean(GL_TRUE), GLboolean(GL_TRUE))
        glDepthMask(GLboolean(GL_TRUE))
        return cardboardSession.renderDistortion(
            sourceTexture: distortionCopyTexture,
            targetFramebuffer: GLuint(targetFramebuffer),
            drawableWidth: drawableWidth,
            drawableHeight: drawableHeight
        )
    }

    private func setGLEnabled(_ capability: GLenum, _ enabled: Bool) {
        if enabled {
            glEnable(capability)
        } else {
            glDisable(capability)
        }
    }

    private func ensureDistortionVertexArray() -> Bool {
        if distortionVertexArray == 0 {
            glGenVertexArrays(1, &distortionVertexArray)
        }
        return distortionVertexArray != 0
    }

    private func ensureDistortionCopyTexture(width: Int, height: Int) -> Bool {
        if distortionCopyTexture == 0 {
            glGenTextures(1, &distortionCopyTexture)
            glBindTexture(GLenum(GL_TEXTURE_2D), distortionCopyTexture)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
            distortionCopyWidth = 0
            distortionCopyHeight = 0
        } else {
            glBindTexture(GLenum(GL_TEXTURE_2D), distortionCopyTexture)
        }

        if distortionCopyWidth != width || distortionCopyHeight != height {
            glTexImage2D(
                GLenum(GL_TEXTURE_2D),
                0,
                GL_RGBA,
                GLsizei(width),
                GLsizei(height),
                0,
                GLenum(GL_RGBA),
                GLenum(GL_UNSIGNED_BYTE),
                nil
            )
            distortionCopyWidth = width
            distortionCopyHeight = height
        }
        return distortionCopyTexture != 0
    }

}
