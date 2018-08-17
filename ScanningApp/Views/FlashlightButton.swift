/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A button with two states that toggles the flashlight.
一个有两种状态的按钮,用来触发闪光灯.
*/

import UIKit
import AVFoundation

@IBDesignable
class FlashlightButton: RoundedButton {
    
    override var isHidden: Bool {
        didSet {
            // Never show this button if there is no torch on this device.
            // 如果设备上没有闪光灯,不显示该按钮.
            guard let captureDevice = AVCaptureDevice.default(for: .video), captureDevice.hasTorch else {
                if !isHidden {
                    isHidden = true
                }
                return
            }
            
            if isHidden {
                // Toggle the flashlight off when hiding the button.
                // 当隐藏按钮时,触发闪光灯关闭.
                toggledOn = false
            }
        }
    }
    
    override var toggledOn: Bool {
        didSet {
            // Update UI
            // 更新UI
            if toggledOn {
                setTitle("Light On", for: [])
                backgroundColor = .appBlue
            } else {
                setTitle("Light Off", for: [])
                backgroundColor = .appLightBlue
            }
            
            // Toggle flashlight
            // 触发闪光灯
            guard let captureDevice = AVCaptureDevice.default(for: .video), captureDevice.hasTorch else {
                if toggledOn {
                    toggledOn = false
                }
                return
            }
            
            do {
                try captureDevice.lockForConfiguration()
                let mode: AVCaptureDevice.TorchMode = toggledOn ? .on : .off
                if captureDevice.isTorchModeSupported(mode) {
                    captureDevice.torchMode = mode
                }
                captureDevice.unlockForConfiguration()
            } catch {
                print("Error while attempting to access flashlight.")
            }
        }
    }
}
