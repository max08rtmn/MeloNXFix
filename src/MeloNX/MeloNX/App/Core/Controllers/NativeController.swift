//
//  NativeController.swift
//  MeloNX
//
//  Created by Stossy11 on 19/10/2025.
//

import Foundation
import CoreHaptics
import UIKit
import GameController

class NativeController: BaseController {
    override init(nativeController: GCController?) {
        super.init(nativeController: nativeController)
    }

    var count = 0

    override public func setupController() {
        nativeController?.handlerQueue = inputQueue

        if let gamepad = nativeController?.extendedGamepad {
            setupStandardController(gamepad)
        } else {
            setupSeparatedJoyConFallback()
        }

        setupHaptics()
        setupMotion()
    }

    private func setupStandardController(_ gamepad: GCExtendedGamepad) {
        setupButtonChangeListener(gamepad.buttonA, for: UserDefaults.standard.bool(forKey: "swapBandA") ? .B : .A)
        setupButtonChangeListener(gamepad.buttonB, for: UserDefaults.standard.bool(forKey: "swapBandA") ? .A : .B)
        setupButtonChangeListener(gamepad.buttonX, for: UserDefaults.standard.bool(forKey: "swapBandA") ? .Y : .X)
        setupButtonChangeListener(gamepad.buttonY, for: UserDefaults.standard.bool(forKey: "swapBandA") ? .X : .Y)

        setupButtonChangeListener(gamepad.dpad.up, for: .dPadUp)
        setupButtonChangeListener(gamepad.dpad.down, for: .dPadDown)
        setupButtonChangeListener(gamepad.dpad.left, for: .dPadLeft)
        setupButtonChangeListener(gamepad.dpad.right, for: .dPadRight)

        setupButtonChangeListener(gamepad.leftShoulder, for: .leftShoulder)
        setupButtonChangeListener(gamepad.rightShoulder, for: .rightShoulder)
        gamepad.leftThumbstickButton.map { setupButtonChangeListener($0, for: .leftStick) }
        gamepad.rightThumbstickButton.map { setupButtonChangeListener($0, for: .rightStick) }

        setupButtonChangeListener(gamepad.buttonMenu, for: .start)
        gamepad.buttonOptions.map { setupButtonChangeListener($0, for: .back) }
        gamepad.buttonHome.map { setupButtonChangeListener($0, for: .guide) }

        setupStickChangeListener(gamepad.leftThumbstick, for: .left)
        setupStickChangeListener(gamepad.rightThumbstick, for: .right)

        setupTriggerChangeListener(gamepad.leftTrigger, for: .left)
        setupTriggerChangeListener(gamepad.rightTrigger, for: .right)
    }

    private func setupSeparatedJoyConFallback() {
        let vendor = nativeController?.vendorName ?? "unknown"
        let buttonNames = nativeController?.physicalInputProfile.buttons.keys.sorted() ?? []
        print("JoyConFix NativeController loaded fake path vendor=\(vendor) extendedGamepad=false")
        print("JoyConFix fake physical button keys=\(buttonNames)")

        setupFakeButton(["Button A", "A"], for: UserDefaults.standard.bool(forKey: "swapBandA") ? .B : .A)
        setupFakeButton(["Button B", "B"], for: UserDefaults.standard.bool(forKey: "swapBandA") ? .A : .B)
        setupFakeButton(["Button X", "X"], for: UserDefaults.standard.bool(forKey: "swapBandA") ? .Y : .X)
        setupFakeButton(["Button Y", "Y"], for: UserDefaults.standard.bool(forKey: "swapBandA") ? .X : .Y)

        setupFakeButton(["Direction Pad Up", "Dpad Up", "D-Pad Up"], for: .dPadUp)
        setupFakeButton(["Direction Pad Down", "Dpad Down", "D-Pad Down"], for: .dPadDown)
        setupFakeButton(["Direction Pad Left", "Dpad Left", "D-Pad Left"], for: .dPadLeft)
        setupFakeButton(["Direction Pad Right", "Dpad Right", "D-Pad Right"], for: .dPadRight)

        setupFakeButton(["Left Shoulder", "Left Bumper", "Button L", "L", "Button SL", "SL"], for: .leftShoulder)
        setupFakeButton(["Right Shoulder", "Right Bumper", "Button R", "R", "Button SR", "SR"], for: .rightShoulder)
        setupFakeButton(["Left Trigger", "Button ZL", "ZL"], for: .leftTrigger)
        setupFakeButton(["Right Trigger", "Button ZR", "ZR"], for: .rightTrigger)

        setupFakeButton(["Button Menu", "Menu", "Button Plus", "Plus", "+"], for: .start)
        setupFakeButton(["Button Options", "Options", "Button Minus", "Minus", "-"], for: .back)
        setupFakeButton(["Button Home", "Home"], for: .guide)
        setupFakeButton(["Button Capture", "Capture", "Screenshot", "Button Share", "Share"], for: .guide)

        if let microDpad = nativeController?.microGamepad?.dpad {
            print("JoyConFix fake mapping left stick source=microGamepad.dpad")
            setupStickChangeListener(microDpad, for: .left)
        } else {
            print("JoyConFix fake left stick missing microGamepad.dpad")
        }
    }

    private func physicalButton(named names: [String]) -> GCControllerButtonInput? {
        guard let buttons = nativeController?.physicalInputProfile.buttons else {
            return nil
        }

        for name in names {
            if let button = buttons[name] {
                return button
            }
        }

        return nil
    }

    private func setupFakeButton(_ names: [String], for key: VirtualControllerButton) {
        if let button = physicalButton(named: names) {
            print("JoyConFix fake mapping key=\(key.rawValue) names=\(names)")
            setupButtonChangeListener(button, for: key)
        } else {
            print("JoyConFix fake missing key=\(key.rawValue) names=\(names)")
        }
    }

    func setupButtonChangeListener(_ button: GCControllerButtonInput, for key: VirtualControllerButton) {
        button.valueChangedHandler = { [unowned self] _, _, pressed in
            setButtonState(pressed ? 1 : 0, for: key)
        }
    }

    func setupStickChangeListener(_ button: GCControllerDirectionPad, for key: ThumbstickType) {
        button.valueChangedHandler = { [unowned self] _, xValue, yValue in
            switch key {
            case .left:
                updateAxisValue(x: xValue, y: yValue, forAxis: 1)
            case .right:
                updateAxisValue(x: xValue, y: yValue, forAxis: 2)
            }
        }
    }

    func setupTriggerChangeListener(_ button: GCControllerButtonInput, for key: ThumbstickType) {
        button.valueChangedHandler = { [unowned self] _, _, pressed in
            setButtonState(pressed ? 1 : 0, for: key == .left ? .leftTrigger : .rightTrigger)
        }
    }
}
