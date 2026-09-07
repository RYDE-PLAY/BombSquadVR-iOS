import Foundation
import GameController

final class VRControllerBridge {
    private struct ControllerState {
        var thumbX: Float = 0
        var thumbY: Float = 0
        var dpadX: Float = 0
        var dpadY: Float = 0
        var sentX: Float = 0
        var sentY: Float = 0
        var buttons = Set<Int>()
    }

    private weak var host: BombSquadVRBallisticaHost?
    private var isStarted = false
    private var notificationObservers: [NSObjectProtocol] = []
    private var configuredControllerIDs = Set<String>()
    private var controllerStates: [String: ControllerState] = [:]

    init(host: BombSquadVRBallisticaHost) {
        self.host = host
    }

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true

        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else {
                    return
                }
                self?.configure(controller)
            }
        )
        notificationObservers.append(
            center.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else {
                    return
                }
                self?.disconnect(controller)
            }
        )
        GCController.controllers().forEach(configure)
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    func stop() {
        guard isStarted else {
            return
        }
        isStarted = false
        GCController.stopWirelessControllerDiscovery()
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        notificationObservers.removeAll()
        configuredControllerIDs.forEach { identifier in
            host?.disconnectController(withIdentifier: identifier)
        }
        configuredControllerIDs.removeAll()
        controllerStates.removeAll()
    }

    private func configure(_ controller: GCController) {
        let identifier = identifier(for: controller)
        guard !configuredControllerIDs.contains(identifier) else {
            return
        }
        configuredControllerIDs.insert(identifier)
        controllerStates[identifier] = ControllerState()

        host?.connectController(
            withName: controller.vendorName ?? "iOS Controller",
            identifier: identifier
        )

        if let gamepad = controller.extendedGamepad {
            configureExtendedGamepad(gamepad, controller: controller)
        } else if let gamepad = controller.microGamepad {
            configureMicroGamepad(gamepad, controller: controller)
        }
    }

    private func disconnect(_ controller: GCController) {
        let identifier = identifier(for: controller)
        guard configuredControllerIDs.remove(identifier) != nil else {
            return
        }
        controllerStates.removeValue(forKey: identifier)
        host?.disconnectController(withIdentifier: identifier)
    }

    private func configureExtendedGamepad(
        _ gamepad: GCExtendedGamepad,
        controller: GCController
    ) {
        gamepad.leftThumbstick.valueChangedHandler = { [weak self, weak controller] _, x, y in
            guard let controller else {
                return
            }
            DispatchQueue.main.async {
                self?.setThumbstick(controller: controller, x: x, y: y)
            }
        }
        gamepad.dpad.valueChangedHandler = { [weak self, weak controller] _, x, y in
            guard let controller else {
                return
            }
            DispatchQueue.main.async {
                self?.setDPad(controller: controller, x: x, y: y)
            }
        }
        gamepad.buttonA.pressedChangedHandler = buttonHandler(controller: controller, button: 0)
        gamepad.buttonX.pressedChangedHandler = buttonHandler(controller: controller, button: 1)
        gamepad.buttonB.pressedChangedHandler = buttonHandler(controller: controller, button: 2)
        gamepad.buttonY.pressedChangedHandler = buttonHandler(controller: controller, button: 3)
        gamepad.leftShoulder.pressedChangedHandler = buttonHandler(controller: controller, button: 5)
        gamepad.rightShoulder.pressedChangedHandler = buttonHandler(controller: controller, button: 6)

        if #available(iOS 13.0, *) {
            gamepad.buttonMenu.pressedChangedHandler = buttonHandler(controller: controller, button: 4)
        }
    }

    private func configureMicroGamepad(
        _ gamepad: GCMicroGamepad,
        controller: GCController
    ) {
        gamepad.allowsRotation = true
        gamepad.reportsAbsoluteDpadValues = true
        gamepad.dpad.valueChangedHandler = { [weak self, weak controller] _, x, y in
            guard let controller else {
                return
            }
            DispatchQueue.main.async {
                self?.setDPad(controller: controller, x: x, y: y)
            }
        }
        gamepad.buttonA.pressedChangedHandler = buttonHandler(controller: controller, button: 0)
        gamepad.buttonX.pressedChangedHandler = buttonHandler(controller: controller, button: 2)
    }

    private func buttonHandler(
        controller: GCController,
        button: Int
    ) -> GCControllerButtonValueChangedHandler {
        { [weak self, weak controller] _, _, pressed in
            guard let controller else {
                return
            }
            DispatchQueue.main.async {
                self?.setButton(controller: controller, button: button, pressed: pressed)
            }
        }
    }

    private func setThumbstick(controller: GCController, x: Float, y: Float) {
        let identifier = identifier(for: controller)
        guard var state = controllerStates[identifier] else {
            return
        }
        state.thumbX = deadzone(x)
        state.thumbY = deadzone(y)
        controllerStates[identifier] = state
        publishAxes(identifier: identifier)
    }

    private func setDPad(controller: GCController, x: Float, y: Float) {
        let identifier = identifier(for: controller)
        guard var state = controllerStates[identifier] else {
            return
        }
        state.dpadX = deadzone(x)
        state.dpadY = deadzone(y)
        controllerStates[identifier] = state
        publishAxes(identifier: identifier)
    }

    private func setButton(controller: GCController, button: Int, pressed: Bool) {
        let identifier = identifier(for: controller)
        guard var state = controllerStates[identifier] else {
            return
        }
        if pressed {
            guard state.buttons.insert(button).inserted else {
                return
            }
        } else {
            guard state.buttons.remove(button) != nil else {
                return
            }
        }
        controllerStates[identifier] = state
        host?.pushControllerButton(
            withIdentifier: identifier,
            button: button,
            pressed: pressed
        )
    }

    private func publishAxes(identifier: String) {
        guard var state = controllerStates[identifier] else {
            return
        }
        let x = abs(state.dpadX) > 0 ? state.dpadX : state.thumbX
        let y = abs(state.dpadY) > 0 ? state.dpadY : state.thumbY
        let engineY = -y

        if x != state.sentX {
            host?.pushControllerAxis(withIdentifier: identifier, axis: 0, value: x)
            state.sentX = x
        }
        if engineY != state.sentY {
            host?.pushControllerAxis(withIdentifier: identifier, axis: 1, value: engineY)
            state.sentY = engineY
        }
        controllerStates[identifier] = state
    }

    private func deadzone(_ value: Float) -> Float {
        abs(value) < 0.12 ? 0 : value
    }

    private func identifier(for controller: GCController) -> String {
        "\(ObjectIdentifier(controller))"
    }
}
