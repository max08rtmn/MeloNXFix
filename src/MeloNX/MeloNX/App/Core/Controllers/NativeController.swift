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
        guard let gamepad = nativeController?.extendedGamepad
        else { return }
        
        nativeController?.handlerQueue = inputQueue
        
        let buttonA = physicalButton(named: "Button A", "A") ?? gamepad.buttonA
        let buttonB = physicalButton(named: "Button B", "B") ?? gamepad.buttonB
        let buttonX = physicalButton(named: "Button X", "X") ?? gamepad.buttonX
        let buttonY = physicalButton(named: "Button Y", "Y") ?? gamepad.buttonY
        let leftShoulder = physicalButton(named: "Left Shoulder", "Left Bumper") ?? gamepad.leftShoulder
        let rightShoulder = physicalButton(named: "Right Shoulder", "Right Bumper") ?? gamepad.rightShoulder
        
        setupButtonChangeListener(buttonA, for: UserDefaults.standard.bool(forKey: "swapBandA") ? .B : .A)
        setupButtonChangeListener(buttonB, for: UserDefaults.standard.bool(forKey: "swapBandA") ? .A : .B)
        setupButtonChangeListener(buttonX, for: UserDefaults.standard.bool(forKey: "swapBandA") ? .Y : .X)
        setupButtonChangeListener(buttonY, for: UserDefaults.standard.bool(forKey: "swapBandA") ? .X : .Y)

        setupButtonChangeListener(gamepad.dpad.up, for: .dPadUp)
        setupButtonChangeListener(gamepad.dpad.down, for: .dPadDown)
        setupButtonChangeListener(gamepad.dpad.left, for: .dPadLeft)
        setupButtonChangeListener(gamepad.dpad.right, for: .dPadRight)

        setupButtonChangeListener(leftShoulder, for: .leftShoulder)
        setupButtonChangeListener(rightShoulder, for: .rightShoulder)
        gamepad.leftThumbstickButton.map { setupButtonChangeListener($0, for: .leftStick) }
        gamepad.rightThumbstickButton.map { setupButtonChangeListener($0, for: .rightStick) }

        setupButtonChangeListener(gamepad.buttonMenu, for: .start)
        gamepad.buttonOptions.map { setupButtonChangeListener($0, for: .back) }

        setupStickChangeListener(gamepad.leftThumbstick, for: .left)
        setupStickChangeListener(gamepad.rightThumbstick, for: .right)

        setupTriggerChangeListener(gamepad.leftTrigger, for: .left)
        setupTriggerChangeListener(gamepad.rightTrigger, for: .right)
        /*
        gamepad.buttonHome?.valueChangedHandler = { [unowned self] _, _, pressed in
            if pressed {
                count += 1
                
                if count == 2 {
                    count = 0
                    
                    
                }
            }
        }
         */
        

        setupHaptics()
        
        setupMotion()
    }
    
    private func physicalButton(named names: String...) -> GCControllerButtonInput? {
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
