/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A custom pinch gesture reconizer that fires only when a threshold is passed.
一个自定义的捏合手势识别器,只有超过阈值时才会触发.
*/

import UIKit.UIGestureRecognizerSubclass

class ThresholdPinchGestureRecognizer: UIPinchGestureRecognizer {
    
    /// The threshold in screen pixels after which this gesture is detected.
    // 屏幕像素阈值,超过后手势都会被检测到.
    private static let threshold: CGFloat = 50
    
    /// Indicates whether the currently active gesture has exceeeded the threshold.
    // 指示当前活跃的手势是否已超过了阈值.
    private(set) var isThresholdExceeded = false
    
    var initialTouchDistance: CGFloat = 0
    
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
            }
        }
    }
    
    func touchDistance(from touches: Set<UITouch>) -> CGFloat {
        guard touches.count == 2 else {
            return 0
        }
        
        var points: [CGPoint] = []
        for touch in touches {
            points.append(touch.location(in: view))
        }
        let distance = sqrt((points[0].x - points[1].x) * (points[0].x - points[1].x) + (points[0].y - points[1].y) * (points[0].y - points[1].y))
        return distance
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 2 else {
            return
        }
        
        super.touchesMoved(touches, with: event)
        
        switch state {
        case .began:
            initialTouchDistance = touchDistance(from: touches)
        case .changed:
            let touchDistance = self.touchDistance(from: touches)
            if abs(touchDistance - initialTouchDistance) > ThresholdPinchGestureRecognizer.threshold {
                isThresholdExceeded = true
            }
        default:
            break
        }
        
        if !isThresholdExceeded {
            scale = 1.0
        }
    }
}
