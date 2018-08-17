/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A custom rotation gesture reconizer that fires only when a threshold is passed.
一个自定义的旋转手势识别器,只有超过阈值时才会触发.
*/
import UIKit.UIGestureRecognizerSubclass

class ThresholdRotationGestureRecognizer: UIRotationGestureRecognizer {
    
    /// The threshold after which this gesture is detected.
    // 阈值,超过后手势才会被识别.
    private static let threshold: CGFloat = .pi / 15 // (12°)
    
    /// Indicates whether the currently active gesture has exceeeded the threshold.
    // 指示当前活跃的手势是否已超过了阈值.
    private(set) var isThresholdExceeded = false
    
    var previousRotation: CGFloat = 0
    var rotationDelta: CGFloat = 0
    
    /// Observe when the gesture's `state` changes to reset the threshold.
    // 监听,当手势的'state'变化时,重置阈值.
    override var state: UIGestureRecognizer.State {
        didSet {
            switch state {
            case .began, .changed:
                break
            default:
                // Reset threshold check.
                // 重置阈值检验.
                isThresholdExceeded = false
                previousRotation = 0
                rotationDelta = 0
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        
        if isThresholdExceeded {
            rotationDelta = rotation - previousRotation
            previousRotation = rotation
        }
        
        if !isThresholdExceeded && abs(rotation) > ThresholdRotationGestureRecognizer.threshold {
            isThresholdExceeded = true
            previousRotation = rotation
        }
    }
}
